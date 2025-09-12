#!/bin/sh
set -eu
REPO="ghcr.io/frinknet/gelli"
IMAGE="${REPO##*/}"
PREFIX="${HOME}/bin"
VER="${1:-latest}"

# Create wrapper bin directory
mkdir -p "$PREFIX"
case ":$PATH:" in
  *:"$PREFIX"|"$PREFIX":*|*:"$PREFIX":*) ;;
  *) printf '\nexport PATH="%s:$PATH"\n' "$PREFIX" >> "$HOME/bashrc" || true ;;
esac

# Pull and tag the image as before
OLD_ID="$(docker image inspect -f '{{.Id}}' "$IMAGE" 2>/dev/null || true)"

if [ "$VER" = "local" ]; then
  VERSION="local-$(git rev-parse --short HEAD 2>/dev/null || echo local)"

  docker build --build-arg VERSION=$VERSION -t "$IMAGE:$VER" .
  docker image tag "$IMAGE:$VER" "$IMAGE"
elif ! docker image pull "$REPO:$VER"; then
  echo "could not pull docker image $REPO:$VER" >&2
  exit 1
else
  docker image tag "$REPO:$VER" "$IMAGE"
fi

NEW_ID="$(docker image inspect -f '{{.Id}}' "$IMAGE")"

if [ -n "${OLD_ID:-}" ] && [ "$OLD_ID" != "$NEW_ID" ]; then
  docker image rm "$OLD_ID" >/dev/null 2>&1 || true
fi
docker image prune -f >/dev/null 2>&1 || true

# Ensure persistent Docker volumes exist
docker volume inspect gelli-models >/dev/null 2>&1 || docker volume create gelli-models >/dev/null
docker volume inspect gelli-loras >/dev/null 2>&1 || docker volume create gelli-loras >/dev/null

# Wrapper script
WRAP="$PREFIX/$IMAGE"

# Get the right branch
case "$VER" in
  v[0-9]*.[0-9]*|latest) BRANCH=main ;;
  *)              BRANCH=$VER ;;
esac

# Install the script
if [ "$VER" = "local" ]; then
  cat gelli.sh | sed "s/^VERSION=\"latest\"/VERSION=\"$VER\"/g" > "$WRAP"
else
  curl -fsSL "https://github.com/${REPO#*/}/raw/$BRANCH/gelli.sh" | sed "s/^VERSION=\"latest\"/VERSION=\"$VER\"/g" > "$WRAP"
fi

# Make it runnable
chmod +x "$WRAP"

# prove it worked
echo
echo "✓ installed: $WRAP"
echo
"$WRAP" version 
echo
