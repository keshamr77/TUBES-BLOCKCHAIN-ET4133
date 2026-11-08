#!/usr/bin/env bash
# Usage: ./stop.sh        stop all validators started by start.sh
#        ./stop.sh 2      stop only node 2
# Stops processes by the PID recorded in run/, never by name.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

for n in $(parse_nodes "$@"); do
  if ! pid=$(node_pid "$n"); then echo "node$n not running"; rm -f "$(pid_file "$n")"; continue; fi
  kill "$pid"
  for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  if kill -0 "$pid" 2>/dev/null; then
    echo "node$n (pid $pid) did not exit after 30s, sending SIGKILL"
    kill -9 "$pid"
  fi
  rm -f "$(pid_file "$n")"
  echo "node$n stopped (pid $pid)"
done
