#!/usr/bin/env sh

error() {
  echo "Error: $@" >&2

  exit 1
}

safety() {
  local dir=$(echo "$PWD/./${1#$PWD}" | awk -F/ '
    {
      n = split($0, a, "/")
      out = ""

      for(i=1;i<=n;i++){
        if(a[i]=="."||a[i]=="") continue
        else if(a[i]=="..") sub("/[^/]+$", "", out)
        else out=out"/"a[i]
      }

      print out ? out : "/"
    }
  ')

  echo ".${dir#$PWD}"
}

aliasparse() {
  alias "$1" 2> /dev/null | cut -d\' -f2
}

yamlparse() {
  sed '1,/^---$/d' "$1" | yq '(.. | select(tag == "!!str")) |= envsubst' -o=json -
}

jsonparse() {
  json=$(cat)

  for key in $(echo "$json" | jq -r 'keys[]'); do
    value=$(echo "$json" | jq -r ".\"$key\" // empty")

    case "$key" in
      tools|agents|loras) [ -n "$value" ] && eval "$key=\$(echo \"\$value\" | jq -r '.[]')";;
      dir|file) [ -n "$value" ] && eval "$key=\$(safety \"\$value\")";;
      *) eval "$key=\"\$value\""
    esac
  done
}

tools() {
  for tool in "$@"; do
    eval "tool-$tool" 2>/dev/null | jq -Rsc 'fromjson? | select(.) | {"type":"function","function":.}'
  done | jq -sc '.'
}

agents() {
  for agent in "$@"; do
    eval "agent-$agent" 2>/dev/null | jq -Rsc 'fromjson? | select(.) | {
      type: "function",
      function: {
        name: (.name + "_agent"),
        description: .description,
        parameters: {
          type: "object",
          properties: {
            instruct: {
              type: "string",
              description: "Include instructions for this agent"
            },
            context: {
              type: "string",
              description: "Include context for this agent"
            }
          },
          required: ["instruct"]
        }
      }
    }'

  done || true | jq -sc '.'
}

tooling() {
  if [ -t 0 ]; then
   yamlparse $1

   exit
  fi

  jsonparse
}

dispatch() {
  tooling "$1"

  echo "${context:-$instruct}" | eval "$BIN-dispatch" "$1" "$instruct"
}

prefix() {
  for file in "$SYS/$1"/*; do
    [ -f "$file" ] || continue

    alias "$2-$(basename "$file")"="$file"
  done

  for file in "$USR/$1"/*; do
    [ -f "$file" ] || continue

    alias "$2-$(basename "$file")"="$file"
  done
}

#swapconf() {
#  local model lora names
#
#  {
#
#    echo "models:"
#
#    for model in /models/*; do
#      [ -d "$model" ] || continue
#      [ -e "$model/base.gguf" ] || continue
#
#      model="${model##*/}"
#      names="$model"
#
#      for lora in /models/$model/*.gguf 2>/dev/null; do
#          [ -e "$lora" ] || continue
#
#          lora="${lora##*/}"
#          lora="${lora%.gguf}"
#
#          [ "$lora"  = "base" ] || continue
#
#          names="$names $lora"
#      done
#
#      echo "  $model:"
#      echo "    cmd: GELLI_PORT=\${PORT} gelli serve $names"
#      echo "    ttl: ${GELLI_TTL:-60}"
#    done
#  } > "$BIN/swap.yaml"
#}

cleanup() {
  cd /work

  [ -n "$SERVER_PID" ] && {
    kill -TERM "$SERVER_PID" 2>/dev/null || true
    timeout 5 wait "$SERVER_PID" 2>/dev/null || true
    kill -KILL "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  }

  [ -d "$BRANCH_DIR" ] && git worktree remove --force "$BRANCH_DIR" 2>/dev/null || true
}
trap cleanup EXIT SIGTERM SIGINT

branch() {
  [ -d ".git" ] || return

  BRANCH="$1"
  export BRANCH_DIR="/tmp/$BRANCH"

  git config --global --add safe.directory "$PWD" &> /dev/null || true
  git worktree prune &> /dev/null || true
  git worktree add --force "$BRANCH_DIR" &> /dev/null || true
  cd "$BRANCH_DIR"

  # Try to switch, create if doesn't exist
  git switch "$BRANCH" &> /dev/null || git switch -c "$BRANCH" &> /dev/null
}

models() {
  [ -z "$@" ] && return

  eval "$BIN-models resolve \"\$@\""
}

loras() {
  [ -z "$@" ] && return

  eval "$BIN-loras resolve \"\$@\""
}

BRANCH=

[ -z "$ENV" ] && export ENV="$(realpath "$0" 2>/dev/null || echo "$ENV")"
[ -z "$SYS" ] && export SYS="${ENV%/common.sh}"
[ -z "$BIN" ] && export BIN="${SYS##*/}"
[ -z "$USR" ] && export USR="$PWD/.$BIN"

export PS1="\n\[\e[1;91m\]	\$PWD \[\e[38;5;52m\]\$\[\e[0m\] \[\e]12;#999900\007\]\[\e]12;#999900\007\]\[\e[3 q\]"

prefix bin "$BIN"
prefix tools tool
prefix agents agent

#echo common "$0" "$@"
