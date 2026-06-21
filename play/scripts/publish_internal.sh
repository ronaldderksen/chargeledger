#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

CONFIG_PATH="play/play-config.json"

read_config() {
  python3 - "$CONFIG_PATH" "$1" "$2" <<'PY'
import json
import sys

path, key, default = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
print(data.get(key, default))
PY
}

TRACK="$(read_config track internal)"
CREDENTIALS="$(read_config credentials play/credentials/google-play-service-account.json)"
AAB_PATH="$(read_config aab build/app/outputs/bundle/release/app-release.aab)"

if [[ ! -f "$CREDENTIALS" ]]; then
  echo "Missing Google Play credentials at: $CREDENTIALS" >&2
  exit 1
fi

if [[ ! -f android/key.properties ]]; then
  cat >&2 <<'EOF'
Refusing to publish: android/key.properties is missing.

Release builds fall back to debug signing when this file is absent, and Google
Play will not accept debug-signed app bundles. Create android/key.properties
with storePassword, keyPassword, keyAlias and storeFile before publishing.
EOF
  exit 1
fi

echo "Fetching Dart/Flutter dependencies..."
flutter pub get

echo "Running analyzer..."
flutter analyze

echo "Building Android App Bundle..."
flutter build appbundle --release

if [[ ! -f "$AAB_PATH" ]]; then
  echo "Expected AAB was not created at: $AAB_PATH" >&2
  exit 1
fi

echo "Uploading to Google Play track: $TRACK"
play/scripts/update_play.sh
