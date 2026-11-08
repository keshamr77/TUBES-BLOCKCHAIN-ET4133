#!/usr/bin/env bash
# Usage: ./start.sh        start all 4 validators
#        ./start.sh 3 4    start only nodes 3 and 4
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
mkdir -p "$RUN_DIR" "$LOG_DIR"

BOOT_PUB=$(sed 's/^0x//' "$NET_DIR/Node-1/key.pub")
BOOTNODE="enode://$BOOT_PUB@127.0.0.1:$(p2p_port 1)"

for n in $(parse_nodes "$@"); do
  if pid=$(node_pid "$n"); then echo "node$n already running (pid $pid)"; continue; fi
  for port in $(rpc_port "$n") $(p2p_port "$n"); do
    if ss -ltnH "sport = :$port" | grep -q .; then
      echo "port $port for node$n is in use by another process; edit ports.env to pick other ports" >&2
      exit 1
    fi
  done
  args=(
    --data-path="$NET_DIR/Node-$n/data"
    --node-private-key-file="$NET_DIR/Node-$n/key"
    --genesis-file="$NET_DIR/genesis.json"
    --profile=ENTERPRISE
    --p2p-host=127.0.0.1 --p2p-port="$(p2p_port "$n")"
    --rpc-http-enabled --rpc-http-host=127.0.0.1 --rpc-http-port="$(rpc_port "$n")"
    --rpc-http-api=ETH,NET,QBFT,WEB3
    --host-allowlist=localhost,127.0.0.1 --rpc-http-cors-origins=all
  )
  [ "$n" != 1 ] && args+=(--bootnodes="$BOOTNODE")
  mkdir -p "$NET_DIR/Node-$n/data"
  setsid nohup "$BESU_BIN" "${args[@]}" >>"$LOG_DIR/node$n.log" 2>&1 < /dev/null &
  echo $! > "$(pid_file "$n")"
  echo "node$n started (pid $!, rpc http://127.0.0.1:$(rpc_port "$n"), log logs/node$n.log)"
done
