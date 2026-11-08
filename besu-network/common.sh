# Shared settings for start.sh / stop.sh / reset.sh / status.sh (sourced, not executed).
NET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export JAVA_HOME="$HOME/.local/opt/jdk-25"
BESU_BIN="$HOME/.local/opt/besu-26.11.0/bin/besu"
# WSL RAM is below 16 GB, so cap each node's heap at 1 GB.
export BESU_OPTS="-Xmx1g"

NODES=(1 2 3 4)
RPC_BASE=8545     # node N listens on RPC_BASE+N-1 (127.0.0.1 only)
P2P_BASE=30303    # node N listens on P2P_BASE+N-1
[ -f "$NET_DIR/ports.env" ] && . "$NET_DIR/ports.env"

RUN_DIR="$NET_DIR/run"
LOG_DIR="$NET_DIR/logs"

rpc_port() { echo $((RPC_BASE + $1 - 1)); }
p2p_port() { echo $((P2P_BASE + $1 - 1)); }
pid_file() { echo "$RUN_DIR/node$1.pid"; }

# Prints the PID only if it is still a Besu process using this node's data dir.
node_pid() {
  local f pid
  f=$(pid_file "$1")
  [ -f "$f" ] || return 1
  pid=$(cat "$f")
  if [ -n "$pid" ] && tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- "--data-path=$NET_DIR/Node-$1/data"; then
    echo "$pid"
  else
    return 1
  fi
}

parse_nodes() {
  if [ $# -eq 0 ]; then echo "${NODES[@]}"; return; fi
  for n in "$@"; do
    case "$n" in 1|2|3|4) echo "$n" ;; *) echo "invalid node: $n (use 1-4)" >&2; exit 1 ;; esac
  done
}
