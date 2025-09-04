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

cd \$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

[ -f ".env" ] && source .env

# Set memory limit if not specified (leave 2GB for system)
if [ -z "\${GELLI_MEMORY:-}" ]; then
  GELLI_MEMORY=\$(awk '/MemAvailable/ {print int(\$2/1024/1024)}' /proc/meminfo 2>/dev/null || echo "4")
  GELLI_MEMORY=\$((GELLI_MEMORY * 0.8))
fi

# Set context size if not specified
if [ -z "\${GELLI_CONTEXT:-}" ]; then
  if [ \$GELLI_MEMORY -lt 1 ]; then
    export GELLI_CONTEXT=512
  elif [ \$GELLI_MEMORY -lt 2 ]; then
    export GELLI_CONTEXT=1024
  elif [ \$GELLI_MEMORY -lt 4 ]; then
    export GELLI_CONTEXT=2048
  elif [ \$GELLI_MEMORY -lt 8 ]; then
    export GELLI_CONTEXT=4096
  elif [ \$GELLI_MEMORY -lt 16 ]; then
    export GELLI_CONTEXT=8192
  else
    export GELLI_CONTEXT=0  # Use model's full context
  fi
fi

# Set batch size if not specified
if [ -z "\${GELLI_BATCH:-}" ]; then
  if [ \$GELLI_MEMORY -lt 1 ]; then
    export GELLI_BATCH=128
  elif [ \$GELLI_MEMORY -lt 2 ]; then
    export GELLI_BATCH=256
  elif [ \$GELLI_MEMORY -lt 4 ]; then
    export GELLI_BATCH=512
  elif [ \$GELLI_MEMORY -lt 8 ]; then
    export GELLI_BATCH=1024
  else
    export GELLI_BATCH=2048
  fi
fi

case "\${1:-}" in
update)
  VER=\${2:-$VER}
  curl -fsSL "https://github.com/${REPO#*/}/raw/main/install.sh" | sh "\$VER"

  ;;
shell)
  exec docker run -it --entrypoint sh \\
    -m \${GELLI_MEMORY}g \\
    -v "\$PWD:/work" \\
    -v ~/.vimrc:/root/.vimrc \\
    -v gelli-models:/models \\
    -v gelli-loras:/loras \\
    -e GELLI_MEMORY \\
    -e GELLI_CONTEXT \\
    -e GELLI_BATCH \\
    -e GELLI_MODEL \\
    -e GELLI_LORAS \\
    -e GELLI_PORT \\
    -e TERM \\
    "\$IMAGE"
  ;;
*)
  exec docker run --rm -i \\
    -m \${GELLI_MEMORY}g \\
    -v "\$PWD:/work" \\
    -v gelli-models:/models \\
    -v gelli-loras:/loras \\
    -e GELLI_MEMORY \\
    -e GELLI_CONTEXT \\
    -e GELLI_BATCH \\
    -e GELLI_MODEL \\
    -e GELLI_LORAS \\
    -e GELLI_PORT \\
    -e TERM \\
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
