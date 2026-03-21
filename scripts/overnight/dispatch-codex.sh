#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overnight/common.sh
source "${SCRIPT_DIR}/common.sh"

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${PLAN_PATH:?PLAN_PATH is required}"

summary_path="${ARTIFACT_DIR}/implement-summary-${ISSUE_NUMBER}.md"

implement_prompt=$(
  cat <<EOF
You are Codex operating as the overnight implementer for /workspaces/dev-openclaw.

Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE:-}
Labels JSON: ${ISSUE_LABELS_JSON:-[]}

Implementation plan:
$(cat "${PLAN_PATH}")

Execution rules:
- Modify repository files as needed.
- File CRUD inside the devcontainer workspace is allowed.
- Only ls and cat may be run without approval.
- Any other shell command must be executed through ${REPO_ROOT}/scripts/overnight/command-gate.sh.
- If a command is blocked, stop and explain what approval is required.
- Add or update tests when behavior changes.
- Summarize the implementation and verification work in the final message.
EOF
)

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  cat > "${summary_path}" <<EOF
# Codex Dry Run Summary

- Planner: ${PLANNER:-unknown}
- Issue: #${ISSUE_NUMBER}
- Result: dry-run completed without repository mutations
EOF
else
  require_command codex
  codex exec \
    -C "${REPO_ROOT}" \
    -s workspace-write \
    -a untrusted \
    -o "${summary_path}" \
    "${implement_prompt}"
fi

write_output "summary_path" "${summary_path}"
