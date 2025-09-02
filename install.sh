#!/bin/sh
set -eu

REPO="ghcr.io/frinknet/gelli"
IMAGE="${REPO##*/}"
PREFIX="${HOME}/bin"
VER="${1:-latest}"

mkdir -p "$PREFIX"

case ":$PATH:" in
  *:"$PREFIX":*) ;;
  *) printf '\nexport PATH="%s:$PATH"\n' "$PREFIX" >> "$HOME/.bashrc" || true ;;
esac

# Record old local alias ID (if any)
OLD_ID="$(docker image inspect -f '{{.Id}}' "$IMAGE:latest" 2>/dev/null || true)"

# Pull new image
if ! docker image pull "$REPO:$VER"; then
  echo "could not pull docker image $REPO:$VER" >&2
  exit 1
fi

# Retag to a stable local alias
docker image tag "$REPO:$VER" "$IMAGE:latest"

# Remove the previous image ID if it changed (skips if referenced)
NEW_ID="$(docker image inspect -f '{{.Id}}' "$IMAGE:latest")"
if [ -n "${OLD_ID:-}" ] && [ "$OLD_ID" != "$NEW_ID" ]; then
  docker image rm "$OLD_ID" >/dev/null 2>&1 || true
fi

# Opportunistic cleanup of danglers
docker image prune -f >/dev/null 2>&1 || true

# Create a shell wrapper
WRAP="$PREFIX/$IMAGE"
cat > "$WRAP" <<EOF
#!/bin/sh
set -eu
IMAGE="$IMAGE:latest"
VERSION="$VER"
if [ "\${1:-}" = "update" ]; then
  TMP="\$(mktemp)"
  trap 'rm -f "\$TMP"' EXIT
  curl -fsSL "https://github.com/${REPO#*/}/raw/main/install.sh" -o "\$TMP"
  exec sh "\$TMP" "\$VERSION"
else
  exec docker run --rm -it \
    -u "\$(id -u):\$(id -g)" \
    -v "\$(pwd):/work" \
    "\$IMAGE" "\$@"
fi
EOF
chmod +x "$WRAP"

echo
echo "✓ installed: $WRAP"
echo
"$WRAP" version 
echo
