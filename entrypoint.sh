#!/bin/env sh

# Configure OpenBLAS based on detected capabilities
CPUS=${CPUS:-1}

# Set OpenBLAS environment for optimal container performance
export OPENBLAS_NUM_THREADS=${GELLI_THREADS:-1}
export OMP_NUM_THREADS=1       # Disable OpenMP to avoid conflicts
export OPENBLAS_MAIN_FREE=1    # Disable CPU affinity in containers
export OPENBLAS_CORETYPE=AUTO  # Let OpenBLAS detect CPU type

# setup proper user
{
  getent passwd "$UID" || adduser -u "$UID" -g "$GID" -h "/work/.$BIN" -D "$BIN"
  getent group "$GID" || addgroup -g "$GID" "$BIN"
  [ -d "/work/.$BIN" ] && echo ".*" > /work/.$BIN/.gitignore
} > /dev/null 2>&1

[ -f ".env" ] && source .env || true
[ -z "$CMD" ] && CMD="$(alias "agent-$1" 2>/dev/null | cut -d\' -f2)" || true
[ -n "$CMD" ] && shift && set -- dispatch "$CMD" $@ && unset CMD || true
[ -z "$CMD" ] && CMD="$(alias "$BIN-$1" 2>/dev/null | cut -d\' -f2)" || true
[ -z "$CMD" ] && CMD="$(alias "$BIN-help" 2>/dev/null | cut -d\' -f2)" || true

shift || true

exec $CMD "$@"
exit 1

if [ "$(id -u)" -eq 0 ]; then
  exec su "$(getent passwd "$UID" | cut -d: -f1)" -c $CMD "$@"
else
  exec $CMD "$@"
fi
