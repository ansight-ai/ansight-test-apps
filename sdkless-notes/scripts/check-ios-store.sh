#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/build/checks/module-cache"
xcrun swiftc -module-cache-path "$root/build/checks/module-cache" \
  "$root/ios/SDKLessNotes/NotesStore.swift" "$root/checks/main.swift" \
  -lsqlite3 -o "$root/build/checks/notes-store-check"
"$root/build/checks/notes-store-check"
