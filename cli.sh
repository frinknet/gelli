#!/bin/sh
set -e

REPO="ghcr.io/frinknet/gelli"
IMAGE="${REPO##*/}"
VERSION="latest"
GITROOT=$(git rev-parse --show-toplevel 2>/dev/null)
FLAGS="$GELLI_DOCKER_FLAGS"
CPU=

cd "${GITROOT:-.}"

# Set memory
if [ -z "${GELLI_MEMORY:-}" ]; then
  # Auto-detect leave 20% for system
  export GELLI_MEMORY=$(awk '/MemAvailable/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo "4000")
  export GELLI_MEMORY=$((GELLI_MEMORY * 4 / 5))
else
  # Parse from .env value
  export GELLI_MEMORY=$(echo "$GELLI_MEMORY" | awk '
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
      print $0
    }
  }')
fi

# Set context size if not specified
if [ -z "${GELLI_CTX_SIZE:-}" ]; then
  if [ $GELLI_MEMORY -lt 1024 ]; then
    export GELLI_CTX_SIZE=512
  elif [ $GELLI_MEMORY -lt 2048 ]; then
    export GELLI_CTX_SIZE=1024
  elif [ $GELLI_MEMORY -lt 4096 ]; then
    export GELLI_CTX_SIZE=2048
  elif [ $GELLI_MEMORY -lt 8192 ]; then
    export GELLI_CTX_SIZE=4096
  elif [ $GELLI_MEMORY -lt 16384 ]; then
    export GELLI_CTX_SIZE=8192
  elif [ $GELLI_MEMORY -lt 32768 ]; then
    export GELLI_CTX_SIZE=16384
  else
    export GELLI_CTX_SIZE=0  # Use model's full context
  fi
fi

# Check if running in container with cgroup v1
if [ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us ] && [ -f /sys/fs/cgroup/cpu/cpu.cfs_period_us ]; then
  quota=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)
  period=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)

  [ "$quota" -gt 0 ] && CPUS=$((quota / period))
fi

# Check cgroup v2
if [ -f /sys/fs/cgroup/cpu.max ]; then
  read quota period < /sys/fs/cgroup/cpu.max

  [ "$quota" != "max" ] && CPUS=$((quota / period))
fi

# Fallback: use sched_getaffinity via nproc
[ -z "$CPUS" ] && CPUS=$(nproc 2>/dev/null || echo 1)

# Set thread count
if [ -z "${GELLI_THREADS:-}" ]; then
  if [ $GELLI_MEMORY -lt 1024 ]; then
    export GELLI_THREADS=1
  elif [ $GELLI_MEMORY -lt 2048 ]; then
    export GELLI_THREADS=$((CPUS / 2))
  else
    export GELLI_THREADS=$CPUS
  fi
fi

# Set parallel connections based on memory
if [ -z "${GELLI_PARALLEL:-}" ]; then
  if [ $GELLI_MEMORY -lt 2048 ]; then
    export GELLI_PARALLEL=4
  elif [ $GELLI_MEMORY -lt 4096 ]; then
    export GELLI_PARALLEL=8
  elif [ $GELLI_MEMORY -lt 8192 ]; then
    export GELLI_PARALLEL=16
  elif [ $GELLI_MEMORY -lt 16384 ]; then
    export GELLI_PARALLEL=32
  else
    export GELLI_PARALLEL=64
  fi
fi

# Pass GPU only if available
if [ -d /dev/dri ]; then
  FLAGS="$FLAGS --device=/dev/dri:/dev/dri"

  # Add host video/render groups if they exist (perm fixes)
  VID_GID=$(getent group video 2>/dev/null | cut -d: -f3)
  REN_GID=$(getent group render 2>/dev/null | cut -d: -f3)

  [ -n "$VID_GID" ] && FLAGS="$FLAGS --group-add $VID_GID"
  [ -n "$REN_GID" ] && FLAGS="$FLAGS --group-add $REN_GID"

  # Optional Mesa/Vulkan nudges
  [ -n "$MESA_VK_DEVICE_SELECT" ] && FLAGS="$FLAGS -e MESA_VK_DEVICE_SELECT=$MESA_VK_DEVICE_SELECT"
fi

# Allow for local configs to overide
[ -f ".env" ] && source .env

export GELLI_PORT="${GELLI_PORT:-7771}"
export GELLI_VOLUME="${GELLI_VOLUME:-gelli-models}"
export GELLI_DATABSE="${GELLI_DATABSE:-gelli-database}"
export GELLI_SERVICE="${GELLI_SERVICE:-gelli-service}"
export GELLI_NETWORK="${GELLI_NETWORK:-gelli-network}"

# Make sure the network exists
docker network create $GELLI_NETWORK 2>/dev/null || true

gelli_update() {
  VER="${1:-$VERSION}"

  case "$VER" in
    local*) echo "CANNOT UPDATE LOCAL BUILDS - use install.sh" && exit 1;;
    v[0-9]*.[0-9]*|latest) BRANCH=main ;;
    *)                     BRANCH=$VER ;;
  esac

  curl -fsSL "https://github.com/${REPO#*/}/raw/$BRANCH/install.sh" | exec sh -s -- "$VER"
}

gelli_status() {
  if ! docker ps --format "{{.Names}}" | grep -q "^$GELLI_SERVICE\$"; then
  	echo "$IMAGE stopped - $GELLI_SERVICE"

    return 1
  fi

  echo "$IMAGE running - $GELLI_SERVICE"
}

gelli_stop() {
  if ! docker ps --format "{{.Names}}" | grep -q "^$GELLI_SERVICE\$"; then
    echo "$IMAGE not running - $GELLI_SERVICE"

    return 0
  elif ! docker stop $GELLI_SERVICE > /dev/null 2>&1; then
  	echo "$IMAGE stop failed - $GELLI_SERVICE"

    return 1
  fi

  echo "$IMAGE stopped - $GELLI_SERVICE"
}

gelli_start() {
  if ! docker run --rm -d $FLAGS \
    --name $GELLI_SERVICE \
    --network $GELLI_NETWORK \
    -p "$GELLI_PORT:$GELLI_PORT" \
    -v $HOME/.vimrc:/etc/vim/vimrc \
    -v $GELLI_DATABSE:/data \
    -v $GELLI_VOLUME:/models \
    -e GELLI_MEMORY \
    "$IMAGE" start > /dev/null 2>&1; then
  	echo "$IMAGE start failed - $GELLI_SERVICE"

    return 1
  fi

  echo "$IMAGE started - $GELLI_SERVICE"

  return 0
}

gelli_restart() {
  if ! gelli_stop > /dev/null; then
    echo "$IMAGE stop failed - $GELLI_SERVICE"

    return 1
  elif ! gelli_start > /dev/null; then
    echo "$IMAGE restart failed - $GELLI_SERVICE"

    return 1
  fi

  echo "$IMAGE restarted - $GELLI_SERVICE"

  return 0
}

gelli_logs() {
  if ! gelli_status > /dev/null; then
  	echo "$IMAGE stopped - $GELLI_SERVICE"

    return 1
  elif ! docker logs -f $GELLI_SERVICE 2>/dev/null; then
  	echo "$IMAGE start failed - $GELLI_SERVICE"

    return 1
  fi

  echo "$IMAGE started - $GELLI_SERVICE"

  return 0
}

gelli_cli() {
  FLAGS="$FLAGS -i"
  NAME="$IMAGE$(pwd | sed 's/[^a-zA-Z0-9]/-/g' | tr 'A-Z' 'a-z')"

  [ -t 0 ] && FLAGS="${FLAGS}t"

  docker ps --format "{{.Names}}" | grep -q "^$GELLI_SERVICE\$" || GELLI_SERVICE=

  if [ -n "$(docker ps -q -f name=$NAME)" ]; then
    docker exec $FLAGS \
      -e GELLI_TTL \
      -e GELLI_PORT \
      -e GELLI_TEMP \
      -e GELLI_MODEL \
      -e GELLI_LORAS \
      -e GELLI_MEMORY \
      -e GELLI_API_URL \
      -e GELLI_API_KEY \
      -e GELLI_CTX_SIZE \
      -e GELLI_BATCH_SIZE \
      -e GELLI_OUTPUT_SIZE \
      -e GELLI_SYSTEM_PROMPT \
      -e GELLI_LLAMA_FLAGS \
      -e GELLI_MAX_CALLS \
      -e GELLI_SERVICE \
      -e GELLI_THREADS \
      -e UID=$(id -u) \
      -e GID=$(id -g) \
      -e TERM \
      $NAME $IMAGE "$@"
  else
    [ -z "$GELLI_SERVICE" ] && FLAGS="$FLAGS -m ${GELLI_MEMORY}m"

    docker run --rm $FLAGS \
      --name $NAME \
      --hostname $NAME \
      --network $GELLI_NETWORK \
      -v $HOME/.vimrc:/etc/vim/vimrc \
      -v $GELLI_VOLUME:/models \
      -v $PWD:/work \
      -e GELLI_TTL \
      -e GELLI_PORT \
      -e GELLI_TEMP \
      -e GELLI_MODEL \
      -e GELLI_LORAS \
      -e GELLI_MEMORY \
      -e GELLI_API_URL \
      -e GELLI_API_KEY \
      -e GELLI_CTX_SIZE \
      -e GELLI_BATCH_SIZE \
      -e GELLI_UBATCH_SIZE \
      -e GELLI_OUTPUT_SIZE \
      -e GELLI_SYSTEM_PROMPT \
      -e GELLI_LLAMA_FLAGS \
      -e GELLI_MAX_CALLS \
      -e GELLI_SERVICE \
      -e GELLI_THREADS \
      -e UID=$(id -u) \
      -e GID=$(id -g) \
      -e TERM \
      "$IMAGE" "$@"
  fi

  echo
}

case "${1:-}" in
update) gelli_update "$2";;
status) gelli_status;;
start) gelli_start;;
stop) gelli_stop;;
restart) gelli_restart;;
logs) gelli_logs;;
*) gelli_cli "$@";;
esac

exit $?
