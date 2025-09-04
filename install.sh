#!/bin/sh
set -eu
REPO="ghcr.io/frinknet/gelli"
IMAGE="${REPO##*/}"
PREFIX="${HOME}/bin"
VER="${1:-latest}"

# Create wrapper bin directory
mkdir -p "$PREFIX"
case ":$PATH:" in
  *:"$PREFIX":*) ;;
  *) printf '\nexport PATH="%s:$PATH"\n' "$PREFIX" >> "$HOME/.bashrc" || true ;;
esac

# Pull and tag the image as before
OLD_ID="$(docker image inspect -f '{{.Id}}' "$IMAGE" 2>/dev/null || true)"
if ! docker image pull "$REPO:$VER"; then
  echo "could not pull docker image $REPO:$VER" >&2
  exit 1
fi

docker image tag "$REPO:$VER" "$IMAGE"

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
cat > "$WRAP" <<EOF
#!/bin/sh
set -eu

IMAGE="$IMAGE"
VERSION="$VER"

case "\${1:-}" in
update)
  TMP="\$(mktemp)"

  trap 'rm -f "\$TMP"' EXIT

  curl -fsSL "https://github.com/${REPO#*/}/raw/main/install.sh" -o "\$TMP"

  exec sh "\$TMP" "\$VERSION"

  ;;
shell)
  exec docker run -it --entrypoint sh \\
    -v "\$(pwd):/work" \\
    -v ~/.vimrc:/root/.vimrc \\
    -v gelli-models:/models \\
    -v gelli-loras:/loras \\
    -e GELLI_CONTEXT \\
    -e GELLI_MODEL \\
    -e GELLI_LORAS \\
    -e GELLI_PORT \\
    -e TERM \\
    "\$IMAGE"
  ;;
*)
  exec docker run --rm -i \\
    -v "\$(pwd):/work" \\
    -v gelli-models:/models \\
    -v gelli-loras:/loras \\
    -e GELLI_CONTEXT \\
    -e GELLI_MODEL \\
    -e GELLI_LORAS \\
    -e GELLI_PORT \\
    "\$IMAGE" "\$@"
  ;;
esac
EOF

chmod +x "$WRAP"

# prove it worked
echo
echo "✓ installed: $WRAP"
echo
"$WRAP" version 
echo
