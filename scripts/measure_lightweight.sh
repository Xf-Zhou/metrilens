#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
if (( $# != 1 )); then
  print -u2 "usage: measure_lightweight.sh standard|low-power|finalize"
  exit 2
fi

case "$1" in
  standard)
    "$repo_dir/scripts/static_constraints.sh"
    "$repo_dir/scripts/build_local_release.sh"
    "$repo_dir/scripts/measure_launch.py"
    exec "$repo_dir/scripts/measure_lightweight.py" standard
    ;;
  low-power)
    "$repo_dir/scripts/static_constraints.sh"
    exec "$repo_dir/scripts/measure_lightweight.py" low-power
    ;;
  finalize)
    exec "$repo_dir/scripts/measure_lightweight.py" finalize
    ;;
  *)
    print -u2 "usage: measure_lightweight.sh standard|low-power|finalize"
    exit 2
    ;;
esac
