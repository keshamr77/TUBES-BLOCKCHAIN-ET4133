#!/usr/bin/env bash
# Shows each node's process state, block number and peer count.
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

rpc() { curl -s -m 2 -H 'Content-Type: application/json' \
  --data "{\"jsonrpc\":\"2.0\",\"method\":\"$2\",\"params\":${3:-[]},\"id\":1}" "http://127.0.0.1:$1" | jq -r '.result // empty'; }

for n in "${NODES[@]}"; do
  port=$(rpc_port "$n")
  if pid=$(node_pid "$n"); then
    blk=$(rpc "$port" eth_blockNumber); peers=$(rpc "$port" net_peerCount)
    printf 'node%s  pid=%-7s rpc=%s  block=%s  peers=%s\n' "$n" "$pid" "$port" \
      "$([ -n "$blk" ] && echo $((blk)) || echo '?')" "$([ -n "$peers" ] && echo $((peers)) || echo '?')"
  else
    printf 'node%s  stopped\n' "$n"
  fi
done
