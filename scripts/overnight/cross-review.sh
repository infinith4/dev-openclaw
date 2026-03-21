#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overnight/common.sh
source "${SCRIPT_DIR}/common.sh"

: "${REVIEW_PATH:?REVIEW_PATH is required}"
: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"

output_path="${ARTIFACT_DIR}/pr-review-${ISSUE_NUMBER}.md"

jq -r '
  "## Overnight Review\n\n" +
  "- ok: " + (.ok | tostring) + "\n" +
  "- status: " + .status + "\n" +
  "- plan_alignment: " + .plan_alignment + "\n\n" +
  (if (.findings | length) == 0
   then "No findings.\n"
   else "### Findings\n" + (.findings | map("- " + .) | join("\n")) + "\n"
   end)
' "${REVIEW_PATH}" > "${output_path}"

write_output "cross_review_path" "${output_path}"
