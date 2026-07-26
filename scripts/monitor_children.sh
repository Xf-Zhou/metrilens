#!/bin/zsh
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  print -u2 "usage: monitor_children.sh PID [DURATION_SECONDS]"
  exit 2
fi

target_pid=$1
duration=${2:-600}
deadline=$(( EPOCHSECONDS + duration ))

while (( EPOCHSECONDS < deadline )); do
  if ! kill -0 "$target_pid" 2>/dev/null; then
    print -u2 "Metrilens process exited during child monitor"
    exit 1
  fi
  if child_pids=$(pgrep -P "$target_pid" 2>/dev/null); then
    print -u2 "Metrilens launched child process: $child_pids"
    exit 1
  else
    pgrep_status=$?
    if (( pgrep_status != 1 )); then
      print -u2 "pgrep child monitor failed with exit code $pgrep_status"
      exit 2
    fi
  fi
  sleep 0.1
done
