#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/.build/Phase5APackage"
dist_dir="$project_root/dist"
stage_root="$(mktemp -d "${TMPDIR:-/tmp}/CheeseCool-Package.XXXXXX")"
trap 'rm -rf "$stage_root"' EXIT

mkdir -p "$dist_dir"
xcodebuild -project "$project_root/CheeseCool.xcodeproj" -scheme CheeseCool -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "$build_root" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "$project_root/CheeseCool.xcodeproj" -scheme 'CheeseCool Uninstaller' -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "$build_root" CODE_SIGNING_ALLOWED=NO build

main_app="$build_root/Build/Products/Release/CheeseCool.app"
uninstaller_app="$build_root/Build/Products/Release/CheeseCool Uninstaller.app"
release_app="$dist_dir/CheeseCool Release.app"
dmg="$dist_dir/CheeseCool.dmg"

rm -rf "$release_app" "$dmg" "$dmg.sha256"
ditto "$main_app" "$release_app"
mkdir -p "$release_app/Contents/Helpers"
ditto "$uninstaller_app" "$release_app/Contents/Helpers/CheeseCool Uninstaller.app"
plutil -extract CFBundleIdentifier raw "$release_app/Contents/Info.plist" | grep -qx 'org.cheesecool.CheeseCool'
plutil -extract CFBundleIdentifier raw "$release_app/Contents/Helpers/CheeseCool Uninstaller.app/Contents/Info.plist" | grep -qx 'org.cheesecool.CheeseCoolUninstaller'
lipo -archs "$release_app/Contents/MacOS/CheeseCool" | grep -qx 'arm64'
test -f "$release_app/Contents/Resources/AppIcon.icns"
test ! -e "$release_app/Contents/Resources/Python.framework"

ditto "$release_app" "$stage_root/CheeseCool.app"
ln -s /Applications "$stage_root/Applications"
hdiutil create -volname 'CheeseCool LOCAL' -srcfolder "$stage_root" -format UDZO -ov "$dmg"
shasum -a 256 "$dmg" > "$dmg.sha256"
print "LOCAL / DEVELOPMENT PACKAGE: $dmg"
