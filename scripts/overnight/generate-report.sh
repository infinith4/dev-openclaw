#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overnight/common.sh
source "${SCRIPT_DIR}/common.sh"

report_path="${REPORT_DIR}/overnight-report.md"
summary_files="$(find "${ARTIFACT_DIR}" -name 'run-summary.json' -type f | sort || true)"

{
  printf '# Overnight Run Report\n\n'
  printf 'Generated at %s UTC.\n\n' "$(timestamp)"

  if [[ -z "${summary_files}" ]]; then
    printf 'No run summaries were found.\n'
  else
    while IFS= read -r summary_file; do
      [[ -z "${summary_file}" ]] && continue
      jq -r '
        "## Issue #" + (.issue_number | tostring) + "\n\n" +
        "- planner: " + .planner + "\n" +
        "- fallback_used: " + (.fallback_used | tostring) + "\n" +
        "- branch: " + .branch + "\n" +
        "- status: " + .status + "\n" +
        "- review_status: " + .review_status + "\n"
      ' "${summary_file}"
      printf '\n'
    done <<< "${summary_files}"
  fi
} > "${report_path}"

write_output "report_path" "${report_path}"
