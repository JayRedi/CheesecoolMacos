#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/.build/HardwareValidation"
product_root="$build_root/Build/Products/Debug"
harness_source="$project_root/Tools/HardwareValidationHarness/main.swift"
harness_binary="$build_root/HardwareValidationHarness"

xcodebuild -project "$project_root/CheeseCool.xcodeproj" \
  -scheme CheeseCoolCore \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$build_root" \
  CODE_SIGNING_ALLOWED=NO build

xcrun swiftc -parse-as-library "$harness_source" \
  -F "$product_root" \
  -framework CheeseCoolCore \
  -Xlinker -rpath -Xlinker "$product_root" \
  -o "$harness_binary"

exec "$harness_binary" "$@"
