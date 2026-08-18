#!/bin/zsh
set -euo pipefail
unsetopt BG_NICE

repo_dir=${0:A:h:h}
version=${1:-}
shift $(( $# > 0 ? 1 : 0 ))

source_dir=
run_smoke=0
while (( $# > 0 )); do
  case "$1" in
    --from-dir)
      if (( $# < 2 )); then
        print -u2 "--from-dir requires a directory"
        exit 2
      fi
      source_dir=$2
      shift 2
      ;;
    --smoke)
      run_smoke=1
      shift
      ;;
    *)
      print -u2 "Unknown option: $1"
      exit 2
      ;;
  esac
done

if [[ -z "$version" ]]; then
  print -u2 "Usage: ./scripts/accept_release.sh X.Y.Z [--from-dir DIR] [--smoke]"
  exit 2
fi

python3 "$repo_dir/scripts/release_tools.py" check-version "$version"

acceptance_root=$(mktemp -d "${TMPDIR:-/tmp}/metrilens-acceptance.XXXXXX")
cleanup() {
  rm -rf "$acceptance_root"
}
trap cleanup EXIT INT TERM

if [[ -n "$source_dir" ]]; then
  download_dir=${source_dir:A}
else
  download_dir="$acceptance_root/downloads"
  mkdir -p "$download_dir"
fi

asset_name="Metrilens-v$version-macos-arm64.zip"
archive="$download_dir/$asset_name"
checksum="$archive.sha256"

if [[ -z "$source_dir" ]]; then
  gh release download "v$version" \
    --repo zxftssr/metrilens \
    --pattern "$asset_name" \
    --pattern "$asset_name.sha256" \
    --dir "$download_dir"
fi

python3 "$repo_dir/scripts/release_tools.py" verify-checksum \
  "$archive" "$checksum"
python3 "$repo_dir/scripts/release_tools.py" verify-archive \
  "$archive" "$version"

acceptance_dir="$acceptance_root/extracted"
mkdir -p "$acceptance_dir"
ditto -x -k "$archive" "$acceptance_dir"
app_path="$acceptance_dir/Metrilens.app"
python3 "$repo_dir/scripts/release_tools.py" check-bundle \
  "$app_path" "$version"
codesign --verify --deep --strict --verbose=2 "$app_path"

size_kib=$(du -sk "$app_path" | awk '{print $1}')
if (( size_kib > 10240 )); then
  print -u2 "Downloaded App exceeds 10 MiB: ${size_kib} KiB"
  exit 1
fi

if xattr -p com.apple.quarantine "$archive" >/dev/null 2>&1; then
  quarantine_status=present
else
  quarantine_status=absent
fi

if (( run_smoke )); then
  xattr -dr com.apple.quarantine "$app_path"
  executable="$app_path/Contents/MacOS/Metrilens"
  "$executable" >/dev/null 2>&1 &
  app_pid=$!
  cleanup_app() {
    if kill -0 "$app_pid" 2>/dev/null; then
      kill -TERM "$app_pid"
      wait "$app_pid" || true
    fi
  }
  trap 'cleanup_app; cleanup' EXIT INT TERM
  sleep 3
  if ! kill -0 "$app_pid" 2>/dev/null; then
    print -u2 "Downloaded App exited during smoke test"
    exit 1
  fi
  cleanup_app
  trap cleanup EXIT INT TERM
fi

print "Release acceptance passed"
print "Archive SHA-256: $(awk 'NR == 1 { print $1 }' "$checksum")"
print "App size: ${size_kib} KiB"
print "Download quarantine: $quarantine_status"
