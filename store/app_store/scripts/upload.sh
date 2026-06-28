#!/usr/bin/env bash
set -euo pipefail

APP_STORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  store/app_store/scripts/upload.sh --dry-run
  store/app_store/scripts/upload.sh
  store/app_store/scripts/upload.sh screenshots

Uploads App Store metadata from:
  store/shared/listing/en-US/full-description.txt

The default upload does not upload screenshots.

Uploads screenshots from:
  store/app_store/scripts/upload.sh screenshots
EOF
}

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

COMMAND="${1:-upload}"

case "$COMMAND" in
  --dry-run)
    cd "$APP_STORE_DIR"
    fastlane upload dry_run:true
    ;;
  upload)
    cd "$APP_STORE_DIR"
    fastlane upload
    ;;
  screenshots)
    cd "$APP_STORE_DIR"
    fastlane upload_screenshots
    ;;
  -h|--help)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
