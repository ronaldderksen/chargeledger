#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

CONFIG_PATH="play/play-config.json"

dart play/scripts/update_play.dart --config "$CONFIG_PATH" "$@"
