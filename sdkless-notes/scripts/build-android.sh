#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
if [[ -x /usr/libexec/java_home ]]; then
  export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 17)}"
fi
cd "$root/android"
./gradlew --no-daemon :app:assembleDebug :app:assembleDebugAndroidTest "$@"
printf '\nDebug APK: %s\n' "$root/android/app/build/outputs/apk/debug/app-debug.apk"
