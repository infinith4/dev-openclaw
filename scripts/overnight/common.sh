#!/usr/bin/env bash
set -euo pipefail

OVERFLOW_GUARD="${OVERFLOW_GUARD:-20}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-${REPO_ROOT}}"
ARTIFACT_DIR="${ARTIFACT_DIR:-${REPO_ROOT}/.overnight-artifacts}"
LOG_DIR="${LOG_DIR:-${ARTIFACT_DIR}/logs}"
PLAN_DIR="${PLAN_DIR:-${ARTIFACT_DIR}/plans}"
REPORT_DIR="${REPORT_DIR:-${ARTIFACT_DIR}/reports}"
APPROVED_COMMANDS_FILE="${APPROVED_COMMANDS_FILE:-${SCRIPT_DIR}/config/approved-commands.example.json}"
DEFAULT_BASE_BRANCH="${DEFAULT_BASE_BRANCH:-main}"

mkdir -p "${ARTIFACT_DIR}" "${LOG_DIR}" "${PLAN_DIR}" "${REPORT_DIR}"

refresh_artifact_paths() {
  LOG_DIR="${ARTIFACT_DIR}/logs"
  PLAN_DIR="${ARTIFACT_DIR}/plans"
  REPORT_DIR="${ARTIFACT_DIR}/reports"
  mkdir -p "${ARTIFACT_DIR}" "${LOG_DIR}" "${PLAN_DIR}" "${REPORT_DIR}"
}

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '[%s] %s\n' "$(timestamp)" "$*" >&2
}

write_output() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "${key}" "${value}" >> "${GITHUB_OUTPUT}"
  fi
}

write_env() {
  local key="$1"
  local value="$2"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    printf '%s=%s\n' "${key}" "${value}" >> "${GITHUB_ENV}"
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    log "required command is missing: ${command_name}"
    return 127
  fi
}

slugify() {
  local input="${1:-}"
  printf '%s' "${input}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g' \
    | cut -c1-40
}

issue_slug() {
  slugify "${ISSUE_TITLE:-issue}"
}

ensure_workspace_path() {
  local target_path
  target_path="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1")"
  local workspace_path
  workspace_path="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${WORKSPACE_ROOT}")"
  [[ "${target_path}" == "${workspace_path}"* ]]
}

json_file_set() {
  local file_path="$1"
  local filter="$2"
  local tmp_path
  tmp_path="$(mktemp)"
  jq "${filter}" "${file_path}" > "${tmp_path}"
  mv "${tmp_path}" "${file_path}"
}

default_issue_payload() {
  jq -n \
    --arg number "${ISSUE_NUMBER:-0}" \
    --arg title "${ISSUE_TITLE:-Dry run overnight task}" \
    --arg body "${ISSUE_BODY:-Dry run execution without GitHub issue body.}" \
    --argjson labels "${ISSUE_LABELS_JSON:-[\"auto:implement\",\"priority:low\"]}" \
    '[{
      number: ($number | tonumber),
      title: $title,
      body: $body,
      labels: $labels
    }]'
}

# Parse a local plan file and export ISSUE_NUMBER, ISSUE_TITLE, ISSUE_BODY, ISSUE_LABELS_JSON.
#
# Plan file format:
#   - First H1 heading (# ...) is used as ISSUE_TITLE
#   - HTML comment block <!-- plan-meta ... --> contains:
#       task-id: <id>        (used as ISSUE_NUMBER, e.g. L001)
#       labels: <csv>        (comma-separated, e.g. auto:implement, priority:high)
#   - The entire file content is used as ISSUE_BODY
parse_plan_file() {
  local plan_file="$1"

  if [[ ! -f "${plan_file}" ]]; then
    log "plan file not found: ${plan_file}"
    return 1
  fi

  local content
  content="$(cat "${plan_file}")"

  # Extract title from first H1
  local title
  title="$(grep -m1 '^# ' "${plan_file}" | sed 's/^# //')"
  if [[ -z "${title}" ]]; then
    title="$(basename "${plan_file}" .md)"
  fi

  # Extract plan-meta block
  local meta_block=""
  if grep -q '<!-- plan-meta' "${plan_file}"; then
    meta_block="$(sed -n '/<!-- plan-meta/,/-->/p' "${plan_file}")"
  fi

  # Extract task-id
  local task_id=""
  if [[ -n "${meta_block}" ]]; then
    task_id="$(printf '%s\n' "${meta_block}" | grep -oP 'task-id:\s*\K\S+' || true)"
  fi
  if [[ -z "${task_id}" ]]; then
    # Derive from filename: docs/plan/my-task.md -> my-task
    task_id="L-$(slugify "$(basename "${plan_file}" .md)")"
  fi

  # Extract labels
  local labels_csv=""
  if [[ -n "${meta_block}" ]]; then
    labels_csv="$(printf '%s\n' "${meta_block}" | grep -oP 'labels:\s*\K.*' || true)"
  fi
  local labels_json
  if [[ -n "${labels_csv}" ]]; then
    # Convert "auto:implement, priority:high" -> ["auto:implement","priority:high"]
    labels_json="$(printf '%s' "${labels_csv}" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | jq -R . | jq -sc .)"
  else
    labels_json='["auto:implement"]'
  fi

  ISSUE_NUMBER="${task_id}"
  ISSUE_TITLE="${title}"
  ISSUE_BODY="${content}"
  ISSUE_LABELS_JSON="${labels_json}"
  export ISSUE_NUMBER ISSUE_TITLE ISSUE_BODY ISSUE_LABELS_JSON
}
