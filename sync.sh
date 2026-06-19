#!/usr/bin/env bash
set -euo pipefail

remote_host="strato4"
target="$remote_host:/local/synced/chargeledger/"

rsync -av --delete --delete-excluded \
  --filter 'P /info.yaml' \
  --filter 'P /.dart_tool/***' \
  --filter 'P /build/***' \
  --include '/pubspec.yaml' \
  --include '/pubspec.lock' \
  --include '/bin/' \
  --include '/bin/***' \
  --include '/lib/' \
  --include '/lib/***' \
  --include '/web/' \
  --include '/web/***' \
  --exclude '*' \
  ./ "$target"

ssh "$remote_host" "kubectl rollout restart deployment chargeledger"
