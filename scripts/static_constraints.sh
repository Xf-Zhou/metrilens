#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
pattern='URLSession|NWConnection|Process\(|NSTask|popen\(|system\(|socket\('

find_forbidden_api() {
  if (( $+commands[rg] )); then
    rg -n "$pattern" "$repo_dir/Metrilens"
  else
    /usr/bin/grep -R -n -E --include='*.swift' "$pattern" "$repo_dir/Metrilens"
  fi
}

if find_forbidden_api; then
  print -u2 "Forbidden runtime API found"
  exit 1
fi

print "Static single-process/network constraints passed"
