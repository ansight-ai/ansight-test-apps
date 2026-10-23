#!/usr/bin/env bash
set -euo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ansight_cli="${ANSIGHT_CLI:-ansight}"
while read -r technology app_id; do
  "$ansight_cli" app register "$app_id" --codebase "${suite_root}/${technology}" "$@" --json
done <<'APPS'
ios ai.ansight.testapps.pencil
maui ai.ansight.testapps.pencil.maui
flutter ai.ansight.pencil.flutter
react-native ai.ansight.pencil.reactnative
capacitor ai.ansight.pencil.capacitor
APPS
