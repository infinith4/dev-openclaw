#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overnight/common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
  cat <<EOF
usage: $0 (--issue-number <number> | --plan-file <path>) [--dry-run] [--artifact-dir <path>] [--base-branch <name>]

  --issue-number <number>  GitHub Issue 番号からタスクを取得
  --plan-file <path>       ローカル plan ファイルからタスクを取得 (docs/plan/*.md)
EOF
}

ensure_clean_before_checkout() {
  local target_branch="$1"
  local current_branch
  current_branch="$(git rev-parse --abbrev-ref HEAD)"

  if [[ "${current_branch}" == "${target_branch}" ]]; then
    return 0
  fi

  # Stash trivial config changes (e.g. .claude/settings.json auto-updated by IDE)
  local dirty_files
  dirty_files="$(git diff --name-only; git diff --cached --name-only)"
  if [[ -z "${dirty_files}" ]]; then
    return 0
  fi

  # Auto-stash if only IDE/tool config files are dirty
  local non_config_dirty
  non_config_dirty="$(printf '%s\n' "${dirty_files}" | grep -v '^\.claude/' | grep -v '^\.vscode/' || true)"
  if [[ -z "${non_config_dirty}" ]]; then
    log "auto-stashing IDE config changes before branch switch"
    git stash push -q -m "overnight: auto-stash config before ${target_branch}"
    return 0
  fi

  log "working tree has uncommitted changes; commit or stash before switching to ${target_branch}"
  log "dirty files: ${dirty_files}"
  exit 1
}

resolve_base_ref() {
  local requested_base="$1"

  if git show-ref --verify --quiet "refs/heads/${requested_base}"; then
    printf '%s\n' "${requested_base}"
    return 0
  fi

  if git show-ref --verify --quiet "refs/remotes/origin/${requested_base}"; then
    printf '%s\n' "origin/${requested_base}"
    return 0
  fi

  log "base branch not found locally or on origin: ${requested_base}"
  exit 1
}

checkout_issue_branch() {
  local issue_branch="$1"
  local base_ref="$2"

  ensure_clean_before_checkout "${issue_branch}"

  if git show-ref --verify --quiet "refs/heads/${issue_branch}"; then
    git checkout "${issue_branch}"
    return 0
  fi

  git checkout "${base_ref}"
  git checkout -b "${issue_branch}"
}

write_skipped_review() {
  local review_path="$1"
  local reason="$2"

  jq -n \
    --arg status "skipped" \
    --arg plan_alignment "${reason}" \
    '{ok: false, status: $status, plan_alignment: $plan_alignment, findings: []}' \
    > "${review_path}"
}

issue_number=""
plan_file=""
dry_run="false"
base_branch="${DEFAULT_BASE_BRANCH}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue-number)
      issue_number="${2:-}"
      shift 2
      ;;
    --plan-file)
      plan_file="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    --artifact-dir)
      ARTIFACT_DIR="${2:-}"
      shift 2
      ;;
    --base-branch)
      base_branch="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "unknown argument: $1"
      usage
      exit 64
      ;;
  esac
done

if [[ -z "${issue_number}" && -z "${plan_file}" ]]; then
  log "either --issue-number or --plan-file is required"
  usage
  exit 64
fi

if [[ -n "${issue_number}" && -n "${plan_file}" ]]; then
  log "--issue-number and --plan-file are mutually exclusive"
  usage
  exit 64
fi

refresh_artifact_paths

require_command git
require_command jq

if [[ -n "${plan_file}" ]]; then
  # --- Local plan file mode ---
  log "loading task from local plan file: ${plan_file}"
  parse_plan_file "${plan_file}"
else
  # --- GitHub Issue mode ---
  require_command gh
  issue_json="$(gh issue view "${issue_number}" --json number,title,body,labels)"
  ISSUE_NUMBER="$(jq -r '.number' <<< "${issue_json}")"
  ISSUE_TITLE="$(jq -r '.title' <<< "${issue_json}")"
  ISSUE_BODY="$(jq -r '.body // ""' <<< "${issue_json}")"
  ISSUE_LABELS_JSON="$(jq -c '[.labels[].name]' <<< "${issue_json}")"
  export ISSUE_NUMBER ISSUE_TITLE ISSUE_BODY ISSUE_LABELS_JSON
fi

DRY_RUN="${dry_run}"
BASE_REF="${base_branch}"
export DRY_RUN ARTIFACT_DIR BASE_REF

issue_branch="overnight/${ISSUE_NUMBER}-$(issue_slug)"
base_ref="$(resolve_base_ref "${base_branch}")"

checkout_issue_branch "${issue_branch}" "${base_ref}"

scripts/overnight/safety-check.sh pre

claude_plan_status=0
scripts/overnight/dispatch-claude-plan.sh || claude_plan_status=$?
if [[ "${claude_plan_status}" -ne 0 && "${claude_plan_status}" -ne 42 ]]; then
  exit "${claude_plan_status}"
fi

if [[ "${claude_plan_status}" -eq 42 ]]; then
  scripts/overnight/dispatch-codex-plan.sh
fi

metadata_path="${PLAN_DIR}/plan-metadata-${ISSUE_NUMBER}.json"
PLAN_PATH="$(jq -r '.plan_path' "${metadata_path}")"
PLANNER="$(jq -r '.planner' "${metadata_path}")"
export PLAN_PATH PLANNER

scripts/overnight/dispatch-codex.sh

review_status=0
review_path="${ARTIFACT_DIR}/review-${ISSUE_NUMBER}.json"
scripts/overnight/dispatch-claude-review.sh || review_status=$?
if [[ "${review_status}" -ne 0 && ! -f "${review_path}" ]]; then
  write_skipped_review "${review_path}" "claude review failed with exit code ${review_status}"
fi

REVIEW_PATH="${review_path}"
export REVIEW_PATH
scripts/overnight/cross-review.sh
scripts/overnight/safety-check.sh post

pr_title="Overnight: #${ISSUE_NUMBER} ${ISSUE_TITLE}"
if [[ -n "${plan_file}" ]]; then
  commit_msg="overnight: implement task ${ISSUE_NUMBER} (${ISSUE_TITLE})"
else
  commit_msg="overnight: implement issue #${ISSUE_NUMBER}"
fi

cat <<EOF
Local overnight run completed.

Source: ${plan_file:-"GitHub Issue #${issue_number}"}
Branch: ${issue_branch}
Planner: ${PLANNER}
Plan: ${PLAN_PATH}
Implementation summary: ${ARTIFACT_DIR}/implement-summary-${ISSUE_NUMBER}.md
Review JSON: ${review_path}
Review Markdown: ${ARTIFACT_DIR}/pr-review-${ISSUE_NUMBER}.md

Next commands:
  git status
  git add -A
  git commit -m "${commit_msg}"
  gh pr create --base ${base_branch} --head ${issue_branch} --title "${pr_title}"
EOF
