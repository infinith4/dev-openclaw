#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/overnight/common.sh
source "${SCRIPT_DIR}/common.sh"

if [[ $# -eq 0 ]]; then
  log "usage: $0 <command> [args...]"
  exit 64
fi

command_name="$1"
shift || true

case "${command_name}" in
  ls|cat)
    exec "${command_name}" "$@"
    ;;
esac

if [[ ! -f "${APPROVED_COMMANDS_FILE}" ]]; then
  log "approved commands file not found: ${APPROVED_COMMANDS_FILE}"
  exit 100
fi

full_command="${command_name}"
if [[ $# -gt 0 ]]; then
  full_command="${full_command} $*"
fi

match_count="$(
  jq -r --arg command "${full_command}" '
    [
      .commands[]
      | . as $entry
      | select(
          ($entry.match == "exact" and $entry.command == $command) or
          ($entry.match == "prefix" and ($command | startswith($entry.command)))
        )
    ] | length
  ' "${APPROVED_COMMANDS_FILE}"
)"

if [[ "${match_count}" -gt 0 ]]; then
  exec "${command_name}" "$@"
fi

mkdir -p "${ARTIFACT_DIR}"
printf '%s\t%s\n' "$(timestamp)" "${full_command}" >> "${ARTIFACT_DIR}/approval-requests.log"
log "approval required for command: ${full_command}"
exit 100
