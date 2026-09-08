#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
source_path="$repo_root/scripts/play-to-audio-device.swift"
binary_path="$repo_root/artifacts/tools/play-to-audio-device"
if [[ ! -x "$binary_path" || "$source_path" -nt "$binary_path" ]]; then
  mkdir -p "$(dirname "$binary_path")"
  xcrun swiftc -O "$source_path" -o "$binary_path"
fi
exec "$binary_path" "$@"
