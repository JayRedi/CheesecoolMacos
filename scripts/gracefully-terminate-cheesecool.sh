#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_root="$project_root/.build/GracefulAppTermination"
source_file="$project_root/Tools/GracefulAppTerminator/main.swift"
binary="$build_root/GracefulAppTerminator"

mkdir -p "$build_root"
xcrun swiftc -parse-as-library "$source_file" -framework AppKit -o "$binary"
exec "$binary" org.cheesecool.CheeseCool
