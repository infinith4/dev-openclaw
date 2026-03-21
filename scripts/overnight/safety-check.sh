#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overnight/common.sh
source "${SCRIPT_DIR}/common.sh"

phase="${1:-}"
if [[ -z "${phase}" ]]; then
  log "usage: $0 <pre|post>"
  exit 64
fi

current_branch="$(git rev-parse --abbrev-ref HEAD)"

case "${phase}" in
  pre)
    if [[ "${current_branch}" == "main" || "${current_branch}" == "master" ]]; then
      log "refusing to run on protected branch ${current_branch}"
      exit 1
    fi

    staged_sensitive="$(git diff --cached --name-only | grep -E '(^|/)\.env($|\.)|\.key$|\.pem$|credentials\.|secrets\.' || true)"
    if [[ -n "${staged_sensitive}" ]]; then
      log "sensitive files are staged:"
      printf '%s\n' "${staged_sensitive}" >&2
      exit 1
    fi
    ;;
  post)
    base_ref="${BASE_REF:-origin/${DEFAULT_BASE_BRANCH}}"
    if ! git rev-parse --verify "${base_ref}" >/dev/null 2>&1; then
      base_ref="HEAD~1"
    fi

    changed_files_count="$(git diff --name-only "${base_ref}...HEAD" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [[ "${changed_files_count}" -gt 20 ]]; then
      log "changed file count ${changed_files_count} exceeds limit 20"
      exit 1
    fi

    changed_lines_count="$(
      git diff --numstat "${base_ref}...HEAD" \
        | awk '{sum += $1 + $2} END {print sum + 0}'
    )"
    if [[ "${changed_lines_count}" -gt 1000 ]]; then
      log "changed line count ${changed_lines_count} exceeds limit 1000"
      exit 1
    fi

    flagged_names="$(git diff --name-only "${base_ref}...HEAD" | grep -E '(^|/)\.env($|\.)|\.key$|\.pem$|credentials\.|secrets\.|node_modules/|\.git/' || true)"
    if [[ -n "${flagged_names}" ]]; then
      log "forbidden path patterns detected in diff:"
      printf '%s\n' "${flagged_names}" >&2
      exit 1
    fi
    ;;
  *)
    log "unknown phase: ${phase}"
    exit 64
    ;;
esac
