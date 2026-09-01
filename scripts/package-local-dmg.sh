#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/.build/Phase5APackage"
dist_dir="$project_root/dist"
stage_root="$(mktemp -d "${TMPDIR:-/tmp}/CheeseCool-Package.XXXXXX")"
mount_root="$(mktemp -d "${TMPDIR:-/tmp}/CheeseCool-DMG-Mount.XXXXXX")"
install_root="$(mktemp -d "${TMPDIR:-/tmp}/CheeseCool-Install-Audit.XXXXXX")"
mounted_device=""
cleanup() {
  if [[ -n "$mounted_device" ]]; then
    hdiutil detach "$mounted_device" >/dev/null || true
  fi
  rm -rf "$stage_root" "$mount_root" "$install_root"
}
trap cleanup EXIT

mkdir -p "$dist_dir"
xcodebuild -project "$project_root/CheeseCool.xcodeproj" -scheme CheeseCool -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "$build_root" CODE_SIGNING_ALLOWED=NO build
xcodebuild -project "$project_root/CheeseCool.xcodeproj" -scheme 'CheeseCool Uninstaller' -configuration Release -destination 'platform=macOS,arch=arm64' -derivedDataPath "$build_root" CODE_SIGNING_ALLOWED=NO build

main_app="$build_root/Build/Products/Release/CheeseCool.app"
uninstaller_app="$build_root/Build/Products/Release/CheeseCool Uninstaller.app"
release_app="$dist_dir/CheeseCool Release.app"
dmg="$dist_dir/CheeseCool.dmg"
sign_helper="$project_root/scripts/sign-and-verify-app.sh"

rm -rf "$release_app" "$dmg" "$dmg.sha256"
ditto "$main_app" "$release_app"
mkdir -p "$release_app/Contents/Helpers"
ditto "$uninstaller_app" "$release_app/Contents/Helpers/CheeseCool Uninstaller.app"
plutil -extract CFBundleIdentifier raw "$release_app/Contents/Info.plist" | grep -qx 'org.cheesecool.CheeseCool'
plutil -extract CFBundleIdentifier raw "$release_app/Contents/Helpers/CheeseCool Uninstaller.app/Contents/Info.plist" | grep -qx 'org.cheesecool.CheeseCoolUninstaller'
lipo -archs "$release_app/Contents/MacOS/CheeseCool" | grep -qx 'arm64'
test -f "$release_app/Contents/Resources/AppIcon.icns"
test ! -e "$release_app/Contents/Resources/Python.framework"

print "Signing final CheeseCool Uninstaller.app (ad-hoc, inside-out)"
"$sign_helper" "$release_app/Contents/Helpers/CheeseCool Uninstaller.app"
print "Signing final CheeseCool.app (ad-hoc, inside-out)"
"$sign_helper" "$release_app"
print "Final bundle signature gates passed"

ditto "$release_app" "$stage_root/CheeseCool.app"
ln -s /Applications "$stage_root/Applications"

print "Verifying DMG staging bundles"
codesign --verify --deep --strict --verbose=4 "$stage_root/CheeseCool.app"
codesign --verify --deep --strict --verbose=4 "$stage_root/CheeseCool.app/Contents/Helpers/CheeseCool Uninstaller.app"

hdiutil create -volname 'CheeseCool LOCAL' -srcfolder "$stage_root" -format UDZO -ov "$dmg"
shasum -a 256 "$dmg" > "$dmg.sha256"

print "Verifying mounted DMG bundles"
mount_output="$(hdiutil attach -readonly -nobrowse -mountpoint "$mount_root" "$dmg")"
print "$mount_output"
mounted_device="$(print -r -- "$mount_output" | awk '/^\/dev\// {print $1; exit}')"
test -n "$mounted_device"
codesign --verify --deep --strict --verbose=4 "$mount_root/CheeseCool.app"
codesign -dv --verbose=4 "$mount_root/CheeseCool.app" 2>&1 || true
codesign --verify --deep --strict --verbose=4 "$mount_root/CheeseCool.app/Contents/Helpers/CheeseCool Uninstaller.app"
codesign -dv --verbose=4 "$mount_root/CheeseCool.app/Contents/Helpers/CheeseCool Uninstaller.app" 2>&1 || true
! find "$mount_root" -iname '*HardwareValidationHarness*' -print | grep .

print "Verifying installation-equivalent copied app"
ditto "$mount_root/CheeseCool.app" "$install_root/CheeseCool.app"
codesign --verify --deep --strict --verbose=4 "$install_root/CheeseCool.app"

print "LOCAL / DEVELOPMENT PACKAGE (AD-HOC SIGNED, NOT NOTARIZED): $dmg"
print "DMG SHA-256: $(awk '{print $1}' "$dmg.sha256")"
