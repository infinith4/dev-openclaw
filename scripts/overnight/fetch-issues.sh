#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overnight/common.sh
source "${SCRIPT_DIR}/common.sh"

issues_file="${ARTIFACT_DIR}/issues.json"

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  default_issue_payload > "${issues_file}"
else
  require_command gh
  require_command jq
  : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set for live issue fetches}"

  gh api "repos/${GITHUB_REPOSITORY}/issues?state=open&per_page=100" \
    | jq -c '
        [
          .[]
          | select(has("pull_request") | not)
          | {
              number,
              title,
              body: (.body // ""),
              labels: [.labels[].name]
            }
          | select(any(.labels[]; startswith("auto:")))
        ]
        | sort_by(
            (if any(.labels[]; . == "priority:high") then 0 else 1 end),
            .number
          )
      ' > "${issues_file}"
fi

issues_json="$(cat "${issues_file}")"
write_output "issues" "${issues_json}"
write_output "issues_file" "${issues_file}"
log "issue payload written to ${issues_file}"
