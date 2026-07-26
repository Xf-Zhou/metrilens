#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}

for language in zh-Hans en; do
  xcodebuild \
    -project "$repo_dir/Metrilens.xcodeproj" \
    -scheme Metrilens \
    -configuration Debug \
    -destination 'platform=macOS,arch=arm64' \
    -derivedDataPath "$repo_dir/.build/DerivedData" \
    -testLanguage "$language" \
    -only-testing:MetrilensTests/ProductQualityTests \
    CODE_SIGNING_ALLOWED=NO \
    test
done
