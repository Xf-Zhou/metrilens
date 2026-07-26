#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

repo_dir=${0:A:h:h}
derived_data="$repo_dir/.build/DerivedData"
app_path="$derived_data/Build/Products/Release/Metrilens.app"
executable="$app_path/Contents/MacOS/Metrilens"

xcodebuild \
  -project "$repo_dir/Metrilens.xcodeproj" \
  -scheme Metrilens \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_IDENTITY=- \
  build

codesign --verify --deep --strict --verbose=2 "$app_path"

"$executable" &
app_pid=$!
cleanup() {
  if kill -0 "$app_pid" 2>/dev/null; then
    kill -TERM "$app_pid"
    wait "$app_pid" || true
  fi
}
trap cleanup EXIT INT TERM
sleep 1
kill -0 "$app_pid"

size_kib=$(du -sk "$app_path" | awk '{print $1}')
if (( size_kib > 10240 )); then
  print -u2 "Release App exceeds 10 MiB: ${size_kib} KiB"
  exit 1
fi

print "Release App: $app_path"
print "Size: ${size_kib} KiB"
