#!/bin/zsh
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  print -u2 "usage: monitor_runtime.sh PID [DURATION_SECONDS]"
  exit 2
fi

target_pid=$1
duration=${2:-600}
deadline=$(( EPOCHSECONDS + duration ))

while (( EPOCHSECONDS < deadline )); do
  if ! kill -0 "$target_pid" 2>/dev/null; then
    print -u2 "Metrilens process exited during runtime monitor"
    exit 1
  fi
  if open_files=$(lsof -nP -a -p "$target_pid" 2>/dev/null); then
    :
  else
    lsof_status=$?
    print -u2 "lsof runtime monitor failed with exit code $lsof_status"
    exit 2
  fi
  if [[ "$open_files" == *[[:space:]]IPv[46][[:space:]]* ]]; then
    print -u2 "Metrilens opened a network socket"
    print -r -- "$open_files"
    exit 1
  fi
  sleep 0.1
done
