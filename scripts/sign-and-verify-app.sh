#!/bin/zsh
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" || "$1" != *.app ]]; then
  print -u2 "usage: $0 <app-bundle>"
  exit 2
fi

bundle="$1"

# Sign nested code from the inside out. This intentionally does not use
# `codesign --deep --sign`; the outer bundle is signed only after every copy
# and embedded bundle modification is complete.
while IFS= read -r -d $'\0' nested; do
  codesign --force --sign - --timestamp=none "$nested"
done < <(find "$bundle/Contents" -depth -type d \( -name '*.app' -o -name '*.framework' -o -name '*.xpc' \) -print0)

while IFS= read -r -d $'\0' nestedFile; do
  codesign --force --sign - --timestamp=none "$nestedFile"
done < <(find "$bundle/Contents" -type f \( -name '*.dylib' -o -name '*.bundle' \) -print0)

codesign --force --sign - --timestamp=none "$bundle"
codesign --verify --deep --strict --verbose=4 "$bundle"
codesign -dv --verbose=4 "$bundle" 2>&1 || true
