#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
command -v xcodegen >/dev/null || { echo "Install XcodeGen first (brew install xcodegen)." >&2; exit 1; }
xcodegen generate --spec "$root/ios/project.yml" --project "$root/ios"
xcodebuild -project "$root/ios/SDKLessNotes.xcodeproj" -scheme SDKLessNotes \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$root/build/ios" CODE_SIGNING_ALLOWED=NO \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES build "$@"
printf '\nSimulator app: %s\n' "$root/build/ios/Build/Products/Debug-iphonesimulator/SDKLessNotes.app"
