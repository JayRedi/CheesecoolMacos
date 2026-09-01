#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/.build/Phase4BSettings"
source_file="$project_root/Tools/Phase4BSettings/main.swift"
binary="$build_root/Phase4BSettings"

mkdir -p "$build_root"
xcrun swiftc -parse-as-library "$source_file" -o "$binary"
exec "$binary" "$@"
