#!/usr/bin/env bash
# Wipes chain data (Node-N/data) so the network restarts from genesis.
# Validator keys (Node-N/key) and genesis.json are kept.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

for n in "${NODES[@]}"; do
  if pid=$(node_pid "$n"); then echo "node$n is still running (pid $pid); run ./stop.sh first" >&2; exit 1; fi
done

case "$NET_DIR" in */saksi-contracts/besu-network) ;; *) echo "unexpected network dir: $NET_DIR" >&2; exit 1 ;; esac

for n in "${NODES[@]}"; do
  d="$NET_DIR/Node-$n/data"
  if [ -d "$d" ]; then rm -rf -- "$d"; echo "removed Node-$n/data"; fi
done
