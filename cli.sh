#!/bin/sh
set -e

REPO="ghcr.io/frinknet/gelli"
IMAGE="${REPO##*/}"
VERSION="latest"
GITROOT=$(git rev-parse --show-toplevel 2>/dev/null)
FLAGS="$GELLI_DOCKER_FLAGS"
CPU=

GELLI_PORT="${GELLI_PORT:-7771}"
GELLI_VOLUME="${GELLI_VOLUME:-gelli-models}"
GELLI_SERVICE="${GELLI_SERVICE:-gelli-service}"
GELLI_NETWORK="${GELLI_NETWORK:-gelli-network}"

[ -f ".env" ] && source .env

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

# Set batch size if not specified
if [ -z "${GELLI_BATCH_SIZE:-}" ]; then
  if [ $GELLI_MEMORY -lt 1024 ]; then
    export GELLI_BATCH_SIZE=128
  elif [ $GELLI_MEMORY -lt 2048 ]; then
    export GELLI_BATCH_SIZE=256
  elif [ $GELLI_MEMORY -lt 4096 ]; then
    export GELLI_BATCH_SIZE=512
  elif [ $GELLI_MEMORY -lt 8192 ]; then
    export GELLI_BATCH_SIZE=1024
  else
    export GELLI_BATCH_SIZE=2048
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

# Set BLAS if needed with consideration of memory thrashing
if [ -z "${GELLI_THREADS:-}" ]; then
  if [ $GELLI_MEMORY -lt 1024 ]; then
    GELLI_THREADS=1
  elif [ $GELLI_MEMORY -lt 2048 ]; then
    GELLI_THREADS=$((CPUS > 2 ? 2 : CPUS))
  else
    GELLI_THREADS=$((CPUS > 4 ? 4 : CPUS))
  fi
fi

# Set parallel connections based on memory
if [ -z "${GELLI_PARALLEL:-}" ]; then
  if [ $GELLI_MEMORY -lt 2048 ]; then
    GELLI_PARALLEL=2
  elif [ $GELLI_MEMORY -lt 4096 ]; then
    GELLI_PARALLEL=4
  elif [ $GELLI_MEMORY -lt 8192 ]; then
    GELLI_PARALLEL=16
  elif [ $GELLI_MEMORY -lt 16384 ]; then
    GELLI_PARALLEL=32
  else
    GELLI_PARALLEL=64
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

docker network create gelli-network 2>/dev/null || true

# update or run
case "${1:-}" in
update)
  VER=${2:-$VERSION}

  case "$VER" in
    v[0-9]*.[0-9]*|latest) BRANCH=main ;;
    *) BRANCH=$VER ;;
  esac

  curl -fsSL "https://github.com/${REPO#*/}/raw/$BRANCH/install.sh" | exec sh -s -- "$VER"

  ;;
start)
  if docker ps --format "{{.Names}}" | grep -q "^$GELLI_SERVICE\$"; then
    echo "$IMAGE running - $GELLI_SERVICE"
  else
    docker run -d $FLAGS \
      --name $GELLI_SERVICE \
      --network $GELLI_NETWORK \
      -v $GELLI_VOLUME:/models \
      -e GELLI_MEMORY \
      "$IMAGE" start

    echo "$IMAGE started - $GELLI_SERVICE"
  fi
  ;;
stop)
  docker stop $GELLI_SERVICE 2>/dev/null || true
  docker rm $GELLI_SERVICE 2>/dev/null || true
  echo "$IMAGE stopped - $GELLI_SERVICE"
  ;;
status)
  if docker ps --format "{{.Names}}" | grep -q "^$GELLI_SERVICE\$"; then
    echo "$IMAGE running - $GELLI_SERVICE"
    exit 0
  else
    echo "$IMAGE stopped - $GELLI_SERVICE"
    exit 1
  fi
  ;;
*)
  FLAGS="$FLAGS -i"

  [ -t 0 ] && FLAGS="${FLAGS}t"


  if docker ps --format "{{.Names}}" | grep -q "^$GELLI_SERVICE\$"; then
    FLAGS="$FLAGS -e GELLI_SERVICE"
  else
    FLAGS="$FLAGS -m ${GELLI_MEMORY}m"
  fi

  # run container
  exec docker run --rm $FLAGS \
    --network $GELLI_NETWORK \
    -v $GELLI_VOLUME:/models \
    -v $PWD:/work \
    -v ~/.vimrc:/etc/vim/vimrc \
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
    -e GELLI_THREADS \
    -e UID=$(id -u) \
    -e GID=$(id -g) \
    -e TERM \
    "$IMAGE" "$@"
  ;;
esac
