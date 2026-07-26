#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
pattern='URLSession|NWConnection|Process\(|NSTask|popen\(|system\(|socket\('

if rg -n "$pattern" "$repo_dir/Metrilens"; then
  print -u2 "Forbidden runtime API found"
  exit 1
fi

print "Static single-process/network constraints passed"
