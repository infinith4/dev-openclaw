# Overnight Automation Bootstrap

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document must be maintained in accordance with `.agent/PLANS.md`.

## Purpose / Big Picture

After this change, the repository contains a working overnight automation scaffold: GitHub Actions workflows, issue templates, and shell scripts that can fetch labeled issues, create a plan with Claude Code or a Codex fallback, run Codex implementation, run Claude review, and emit a morning report. The system is designed for a self-hosted runner with pre-authenticated CLI tools and explicit command guardrails. A human can verify the scaffold by running the shell syntax checks and by triggering the workflows in dry-run mode.

## Progress

- [x] (2026-03-15 02:30Z) Reviewed `.agent/PLANS.md`, existing GitHub workflow conventions, and the overnight plan in `docs/plan/openclaw_plan.md`.
- [x] (2026-03-15 02:44Z) Added the overnight shell scripts, command gate, and approved-command example configuration.
- [x] (2026-03-15 02:55Z) Added the GitHub Actions workflows and issue templates for overnight plan, implement, review, and report flows.
- [x] (2026-03-15 03:48Z) Validated shell syntax, dry-run artifact generation, report aggregation, and command-gate approval logging.

## Surprises & Discoveries

- Observation: `codex exec` supports `-a/--ask-for-approval` with `untrusted`, which is the closest built-in mode to the requested guardrail.
  Evidence: `codex exec --help` lists `-a, --ask-for-approval <APPROVAL_POLICY>` and documents `untrusted`.
- Observation: `claude` and `gh` are not available in the current devcontainer, so live end-to-end execution cannot be verified locally.
  Evidence: `command -v claude` and `command -v gh` returned no path during exploration.
- Observation: The first `command-gate.sh` prefix matcher was incorrect because the jq filter lost the current object while evaluating `startswith`.
  Evidence: Running `scripts/overnight/command-gate.sh git commit -m test` initially produced `jq: Cannot index string with string "command"`; updating the filter to capture the entry object fixed it and now returns exit code `100`.

## Decision Log

- Decision: Implement the per-issue flow inside `.github/workflows/overnight-implement.yml` even though separate plan/review workflows also exist.
  Rationale: The orchestrator needs one reusable unit per issue to keep artifact passing and branch handling simple.
  Date/Author: 2026-03-15 / Codex
- Decision: Use `scripts/overnight/command-gate.sh` plus Codex `-a untrusted` for command safety.
  Rationale: The CLI can enforce a baseline approval policy, while the wrapper lets the prompts narrow the allowed commands to `ls` and `cat` plus a human-maintained allowlist.
  Date/Author: 2026-03-15 / Codex
- Decision: Treat Claude plan failures caused by missing CLI or rate/subscription limits as retryable fallback conditions.
  Rationale: The user explicitly asked for Codex plan fallback in those cases.
  Date/Author: 2026-03-15 / Codex

## Outcomes & Retrospective

The repository now has a coherent overnight automation scaffold, and the local dry-run checks covered shell syntax, placeholder plan generation, report generation, issue fetching in dry-run mode, and approval logging for blocked commands. It still depends on runner-side prerequisites for live use: self-hosted execution, authenticated `claude` and `codex` CLIs, and an approved-commands file appropriate for the environment.

## Context and Orientation

The new automation lives under `scripts/overnight/` and `.github/workflows/`. The shell scripts own the reusable logic: issue fetch, plan dispatch, implementation dispatch, review dispatch, safety checks, report generation, notifications, and command approval. The workflows orchestrate those scripts on a self-hosted runner. The issue templates under `.github/ISSUE_TEMPLATE/` define the GitHub entry points for overnight tasks. `docs/plan/openclaw_plan.md` is the product plan that this implementation follows.

In this repository, an “ExecPlan” is a self-contained implementation plan defined by `.agent/PLANS.md`. The overnight planner writes one ExecPlan per issue into `.overnight-artifacts/<issue>/plans/plan-<issue>.md` during workflow execution. The “command gate” is the shell wrapper at `scripts/overnight/command-gate.sh` that only allows `ls` and `cat` without approval, while other commands must match the human-maintained allowlist JSON.

## Plan of Work

First, create shared shell helpers in `scripts/overnight/common.sh` so every script resolves the repository root, artifact directories, and GitHub Actions outputs the same way. Then implement the command gate and the shell entrypoints for fetching issues, dispatching Claude and Codex planning, dispatching Codex implementation, dispatching Claude review, rendering review markdown, performing safety checks, generating a report, and sending notifications.

Second, add the reusable GitHub workflows. `overnight-orchestrator.yml` fetches the queue and fans out per issue. `overnight-implement.yml` handles branch creation, plan fallback, implementation, review, commit, push, PR creation, and artifact upload. `overnight-plan.yml`, `overnight-review.yml`, and `overnight-report.yml` provide focused reusable and manual entry points.

Third, add the GitHub issue templates and the approved-command example file so operators have both the task intake forms and the expected command-approval shape.

## Concrete Steps

From the repository root, run the following commands once the files are present:

    bash -n scripts/overnight/*.sh

Inspect the generated workflow files manually:

    cat .github/workflows/overnight-orchestrator.yml
    cat .github/workflows/overnight-implement.yml

On a configured self-hosted runner, verify the prerequisites:

    codex exec --help
    claude -p "ping" --help
    gh auth status

Then trigger the orchestration manually in dry-run mode from GitHub Actions and inspect the uploaded artifacts named `overnight-*` and `overnight-report`.

## Validation and Acceptance

Validation is successful when `bash -n scripts/overnight/*.sh` exits without syntax errors, the workflow files exist in `.github/workflows/`, and the issue templates exist in `.github/ISSUE_TEMPLATE/`. In a configured GitHub Actions environment, a dry-run `workflow_dispatch` of `Overnight Orchestrator` should produce per-issue artifacts that include a plan markdown file, plan metadata JSON, review JSON, PR review markdown, and a run summary JSON. The report workflow should combine those summaries into `overnight-report.md`.

## Idempotence and Recovery

The scripts are additive and can be re-run safely because they write under `.overnight-artifacts/` by issue number. Re-running a dry-run workflow overwrites the prior artifacts for that issue number. If a live run fails after branch creation, the safe recovery path is to delete the temporary branch and re-run the workflow. If a command is blocked by the command gate, the recovery path is to add an explicit allowlist entry on the runner and re-run the job.

## Artifacts and Notes

Important generated files:

    scripts/overnight/common.sh
    scripts/overnight/command-gate.sh
    .github/workflows/overnight-implement.yml
    .github/workflows/overnight-report.yml
    scripts/overnight/config/approved-commands.example.json

The current implementation assumes `gh` is available on the self-hosted runner even though it is not present in the local devcontainer used for authoring.

## Interfaces and Dependencies

The shell scripts depend on `bash`, `git`, `jq`, and, for live runs, `gh`, `codex`, and `claude`. `scripts/overnight/common.sh` exports shared path conventions and output helpers. `scripts/overnight/command-gate.sh` accepts a command followed by arguments and exits with code `100` when approval is required. `scripts/overnight/dispatch-claude-plan.sh` exits with code `42` when Codex should take over planning because Claude is unavailable or rate limited. `scripts/overnight/dispatch-codex.sh` requires `PLAN_PATH` and writes its final message to `implement-summary-<issue>.md`. `scripts/overnight/dispatch-claude-review.sh` writes a JSON review payload compatible with `scripts/overnight/cross-review.sh`.

Revision note: Added the first implementation scaffold for the overnight automation plan, including the Claude planner fallback and the command-approval guardrail requested after the initial plan document was written. Updated after validation to record the fixed jq matcher in the command gate and the successful dry-run checks.
