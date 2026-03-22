#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overnight/common.sh
source "${SCRIPT_DIR}/common.sh"

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${PLAN_PATH:?PLAN_PATH is required}"

review_path="${ARTIFACT_DIR}/review-${ISSUE_NUMBER}.json"
log_path="${LOG_DIR}/claude-review-${ISSUE_NUMBER}.log"

review_prompt=$(
  cat <<EOF
You are Claude Code performing an overnight implementation review for /workspaces/dev-openclaw.

Issue #${ISSUE_NUMBER}: ${ISSUE_TITLE:-}
Planner: ${PLANNER:-unknown}

Plan:
$(cat "${PLAN_PATH}")

Review requirements:
- Compare the current git diff against the plan.
- Identify deviations, regressions, missing tests, and security concerns.
- Return JSON with keys: ok, status, plan_alignment, findings.
- Only ls and cat may run without approval.
- Any other command must go through ${REPO_ROOT}/scripts/overnight/command-gate.sh.
EOF
)

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  jq -n \
    --arg status "success" \
    --arg plan_alignment "dry-run review; no diff was evaluated" \
    '{ok: true, status: $status, plan_alignment: $plan_alignment, findings: []}' \
    > "${review_path}"
  write_output "review_path" "${review_path}"
  exit 0
fi

if ! command -v claude >/dev/null 2>&1; then
  jq -n \
    --arg status "skipped" \
    --arg plan_alignment "claude command unavailable on runner" \
    '{ok: false, status: $status, plan_alignment: $plan_alignment, findings: ["Claude review skipped because the claude command is unavailable."]}' \
    > "${review_path}"
  exit 42
fi

set +e
claude -p "${review_prompt}" \
  --permission-mode auto \
  --allowedTools "Read,Glob,Grep,Bash(ls *),Bash(cat *),Bash(${REPO_ROOT}/scripts/overnight/command-gate.sh *)" \
  --max-turns 30 \
  > "${review_path}" 2> "${log_path}"
status=$?
set -e

if [[ ${status} -ne 0 ]]; then
  if grep -Eqi 'rate limit|usage limit|subscription|quota|too many requests' "${log_path}"; then
    jq -n \
      --arg status "skipped" \
      --arg plan_alignment "claude review skipped because the subscription limit was reached" \
      '{ok: false, status: $status, plan_alignment: $plan_alignment, findings: ["Claude review skipped after hitting a subscription or rate limit."]}' \
      > "${review_path}"
    exit 42
  fi
  exit "${status}"
fi

write_output "review_path" "${review_path}"
