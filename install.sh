#!/bin/sh
set -eu
REPO="ghcr.io/frinknet/gelli"
IMAGE="${REPO##*/}"
PREFIX="${HOME}/bin"
VER="${1:-latest}"
RUNNING=0

# Create wrapper bin directory
mkdir -p "$PREFIX"
case ":$PATH:" in
  *:"$PREFIX":*) ;;
  *) printf '\nexport PATH="%s:$PATH"\n' "$PREFIX" >> "$HOME/.bashrc" || true ;;
esac

# Do we have a previous image
OLD_ID="$(docker image inspect -f '{{.Id}}' "$IMAGE" 2>/dev/null || true)"

# Stop running processes
if ids=$(docker ps --filter "ancestor=${OLD_ID:-no-such-image}" -q); [ -n "$ids" ]; then
  echo "Stopping old $IMAGE..."

  docker stop $ids

  RUNNING=1
fi

# If local then build it
if [ "$VER" = "local" ]; then
  VERSION="local-$(git rev-parse --short HEAD 2>/dev/null || echo local)"

  docker buildx build \
    --memory=4g \
    --build-arg VERSION=$VERSION \
    --build-arg IMAGE=$IMAGE \
    -t "$REPO:$VER" .

# Otherwise pull the image
elif ! docker image pull "$REPO:$VER"; then
  echo "could not pull docker image $REPO:$VER" >&2

  exit 1
fi

# Tag the new image properly
docker image tag "$REPO:$VER" "$IMAGE"

# get the new ID
NEW_ID="$(docker image inspect -f '{{.Id}}' "$IMAGE")"

# If the new ID is different remove the old image
if [ -n "${OLD_ID:-}" ] && [ "$OLD_ID" != "$NEW_ID" ]; then
  docker image rm "$OLD_ID" >/dev/null 2>&1 || true
fi

# prune the old image
docker image prune -f >/dev/null 2>&1 || true

# Ensure persistent Docker volumes exist
docker volume inspect gelli-models >/dev/null 2>&1 || docker volume create gelli-models >/dev/null
docker volume inspect gelli-database >/dev/null 2>&1 || docker volume create gelli-database >/dev/null

# Wrapper script
WRAP="$PREFIX/$IMAGE"

# Get the right branch
case "$VER" in
  v[0-9]*.[0-9]*|latest) BRANCH=main ;;
  *)                     BRANCH=$VER ;;
esac

# Install the script
if [ "$VER" = "local" ]; then
  cat cli.sh | sed "s/^VERSION=\"latest\"/VERSION=\"$VER\"/g" > "$WRAP"
else
  curl -fsSL "https://github.com/${REPO#*/}/raw/$BRANCH/cli.sh" | sed "s/^VERSION=\"latest\"/VERSION=\"$VER\"/g" > "$WRAP"
fi

# Make it runnable
chmod +x "$WRAP"

# Restart if needed
[ $RUNNING = 1 ] && "$WRAP" restart

# Share success
echo
echo "✓ installed: $WRAP"
echo

# prove it worked
"$WRAP" version
