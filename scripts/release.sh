#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
version=${1:-}
mode=${2:-}

if [[ -z "$version" ||
      ("$mode" != "" &&
       "$mode" != "--publish" &&
       "$mode" != "--publish-from-actions") ]]; then
  print -u2 "Usage: ./scripts/release.sh X.Y.Z [--publish]"
  exit 2
fi

tag="v$version"
if [[ "$mode" == "--publish-from-actions" ]]; then
  if [[ "${GITHUB_ACTIONS:-}" != "true" ||
        "${RELEASE_TAG:-}" != "$tag" ||
        "$(git -C "$repo_dir" rev-parse HEAD)" !=
          "$(git -C "$repo_dir" rev-list -n 1 "$tag")" ]]; then
    print -u2 -- "--publish-from-actions must run in GitHub Actions at tag $tag"
    exit 1
  fi
fi

python3 "$repo_dir/scripts/release_tools.py" check-source "$repo_dir" "$version"
"$repo_dir/scripts/static_constraints.sh"
(
  cd "$repo_dir/scripts"
  python3 -m unittest \
    test_measure_lightweight.py \
    test_release_tools.py \
    test_localization_catalog.py
)

xcodebuild \
  -project "$repo_dir/Metrilens.xcodeproj" \
  -scheme Metrilens \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$repo_dir/.build/DerivedData" \
  CODE_SIGNING_ALLOWED=NO \
  test

"$repo_dir/scripts/test_localizations.sh"
"$repo_dir/scripts/test_ui.sh"

"$repo_dir/scripts/build_local_release.sh"

app_path="$repo_dir/.build/DerivedData/Build/Products/Release/Metrilens.app"
release_dir="$repo_dir/.build/releases/v$version"
archive="$release_dir/Metrilens-v$version-macos-arm64.zip"
checksum="$archive.sha256"
mkdir -p "$release_dir"
python3 "$repo_dir/scripts/release_tools.py" package \
  "$app_path" "$version" "$archive" "$checksum"

print "Release package: $archive"
print "Checksum: $checksum"

if [[ "$mode" == "" ]]; then
  exit 0
fi

exec "$repo_dir/scripts/publish_release.sh" \
  "$repo_dir" "$version" "$archive" "$checksum" "$mode"
