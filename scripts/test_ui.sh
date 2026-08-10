#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}

xcodebuild \
  -project "$repo_dir/Metrilens.xcodeproj" \
  -scheme MetrilensUITests \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$repo_dir/.build/DerivedData" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_IDENTITY=- \
  test
