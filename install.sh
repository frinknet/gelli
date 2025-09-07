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
  *) printf '\nexport PATH="%s:$PATH"\n' "$PREFIX" >> "$HOME/bashrc" || true ;;
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

# Set memory
if [ -z "\${GELLI_MEMORY:-}" ]; then
  # Auto-detect leave 20% for system
  GELLI_MEMORY=\$(awk '/MemAvailable/ {print int(\$2/1024)}' /proc/meminfo 2>/dev/null || echo "4000")
  GELLI_MEMORY=\$((GELLI_MEMORY * 4 / 5))
else
  # Parse from .env value
  GELLI_MEMORY=\$(echo "\$GELLI_MEMORY" | awk '
  {
    if (match($0, /^([0-9]+)(.*)/, arr)) {
      num = arr[1]
      unit = tolower(arr[2])
      
      if (unit ~ /^k/) print int(num / 1024)
      else if (unit ~ /^m/ || unit == "") print num
      else if (unit ~ /^g/) print num * 1024  
      else if (unit ~ /^t/) print num * 1024 * 1024
      else print num
    } else {
      print \$0
    }
  }')
fi

# Set context size if not specified
if [ -z "\${GELLI_CTX_SIZE:-}" ]; then
  if [ \$GELLI_MEMORY -lt 1024 ]; then
    export GELLI_CTX_SIZE=512
  elif [ \$GELLI_MEMORY -lt 2048 ]; then
    export GELLI_CTX_SIZE=1024
  elif [ \$GELLI_MEMORY -lt 4096 ]; then
    export GELLI_CTX_SIZE=2048
  elif [ \$GELLI_MEMORY -lt 8192 ]; then
    export GELLI_CTX_SIZE=4096
  elif [ \$GELLI_MEMORY -lt 16384 ]; then
    export GELLI_CTX_SIZE=8192
  elif [ \$GELLI_MEMORY -lt 32768 ]; then
    export GELLI_CTX_SIZE=16384
  else
    export GELLI_CTX_SIZE=0  # Use model's full context
  fi
fi

# Set batch size if not specified
if [ -z "\${GELLI_BATCH_SIZE:-}" ]; then
  if [ \$GELLI_MEMORY -lt 1024 ]; then
    export GELLI_BATCH_SIZE=128
  elif [ \$GELLI_MEMORY -lt 2048 ]; then
    export GELLI_BATCH_SIZE=256
  elif [ \$GELLI_MEMORY -lt 4096 ]; then
    export GELLI_BATCH_SIZE=512
  elif [ \$GELLI_MEMORY -lt 8192 ]; then
    export GELLI_BATCH_SIZE=1024
  else
    export GELLI_BATCH_SIZE=2048
  fi
fi

case "\${1:-}" in
update)
  VER=\${2:-$VER}

  case "\$VER" in
    v[0-9]*.[0-9]*) BRANCH=main ;;
    *)              BRANCH=\$VER ;;
  esac

  curl -fsSL "https://github.com/${REPO#*/}/raw/\$BRANCH/install.sh" | sh -s -- "\$VER"

  ;;
shell)
  exec docker run -it --entrypoint sh \\
    -m \${GELLI_MEMORY}m \\
    -v "\$PWD:/work" \\
    -v ~/.vimrc:/root/.vimrc \\
    -v gelli-models:/models \\
    -v gelli-loras:/loras \\
    -e GELLI_PORT \\
    -e GELLI_TEMP \\
    -e GELLI_MODEL \\
    -e GELLI_LORAS \\
    -e GELLI_MEMORY \\
    -e GELLI_CTX_SIZE \\
    -e GELLI_BATCH_SIZE \\
    -e GELLI_OUTPUT_SIZE \\
    -e GELLI_LLAMA_FLAGS \\
    -e GELLI_SYSTEM_PROMPT \\
    -e GELLI_CODER_PROMPT \\
    -e GELLI_CODER_MODEL \\
    -e GELLI_CODER_LORAS \\
    -e TERM \\
    "\$IMAGE"
  ;;
*)
  exec docker run --rm -i \\
    -m \${GELLI_MEMORY}m \\
    -v "\$PWD:/work" \\
    -v gelli-models:/models \\
    -v gelli-loras:/loras \\
    -e GELLI_PORT \\
    -e GELLI_TEMP \\
    -e GELLI_MODEL \\
    -e GELLI_LORAS \\
    -e GELLI_MEMORY \\
    -e GELLI_CTX_SIZE \\
    -e GELLI_BATCH_SIZE \\
    -e GELLI_OUTPUT_SIZE \\
    -e GELLI_LLAMA_FLAGS \\
    -e GELLI_SYSTEM_PROMPT \\
    -e GELLI_CODER_PROMPT \\
    -e GELLI_CODER_MODEL \\
    -e GELLI_CODER_LORAS \\
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
