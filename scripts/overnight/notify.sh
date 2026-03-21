#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overnight/common.sh
source "${SCRIPT_DIR}/common.sh"

: "${REPORT_PATH:?REPORT_PATH is required}"

if [[ -z "${NOTIFICATION_WEBHOOK_URL:-}" ]]; then
  log "notification webhook is not configured; skipping"
  exit 0
fi

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  log "dry-run mode enabled; notification skipped"
  exit 0
fi

payload="$(jq -Rn --arg text "$(cat "${REPORT_PATH}")" '{text: $text}')"
curl -X POST \
  -H "Content-Type: application/json" \
  -d "${payload}" \
  "${NOTIFICATION_WEBHOOK_URL}"
