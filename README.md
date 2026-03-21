# dev-openclaw

GitHub Issue をタスクキューとして、Claude Code と Codex で実装を回すためのリポジトリです。

推奨の使い方は devcontainer 内でのローカル実行です。`Claude Code で計画 → Codex で実装 → Claude Code でレビュー` を 1 Issue ごとに回せます。GitHub Actions / self-hosted runner 用の workflow も残していますが、補助的な運用形態として扱います。

## Overview

- Orchestrator: [.github/workflows/overnight-orchestrator.yml](/workspaces/dev-openclaw/.github/workflows/overnight-orchestrator.yml)
- Per-issue implementation flow: [.github/workflows/overnight-implement.yml](/workspaces/dev-openclaw/.github/workflows/overnight-implement.yml)
- Plan only workflow: [.github/workflows/overnight-plan.yml](/workspaces/dev-openclaw/.github/workflows/overnight-plan.yml)
- Review workflow: [.github/workflows/overnight-review.yml](/workspaces/dev-openclaw/.github/workflows/overnight-review.yml)
- Morning report workflow: [.github/workflows/overnight-report.yml](/workspaces/dev-openclaw/.github/workflows/overnight-report.yml)

主要スクリプトは [scripts/overnight](/workspaces/dev-openclaw/scripts/overnight) 配下にあります。

## Prerequisites

### Local (devcontainer)

必要条件:

- devcontainer 内で `claude` コマンドが使える
- devcontainer 内で `codex` コマンドが使える
- devcontainer 内で `gh` コマンドが使える
- Claude Code / Codex / GitHub CLI が CLI ログイン済み
- GitHub Issue を `gh issue view` で参照できる
- 承認済みコマンド allowlist を用意できる

#### セットアップ

devcontainer を Rebuild すれば [postCreate.sh](.devcontainer/postCreate.sh) が自動で全ツールをインストールします。手動でインストールする場合は以下を実行してください。

```bash
# npm global prefix を設定（devcontainer デフォルト）
npm config set prefix "$HOME/.npm-global"

# Codex CLI
npm install -g @openai/codex

# Claude Code
npm install -g @anthropic-ai/claude-code

# GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt-get update -qq && sudo apt-get install -y -qq gh

# PATH に追加（未設定の場合）
echo 'export PATH="$PATH:$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.dotnet/tools:$HOME/bin"' >> ~/.bashrc
source ~/.bashrc
```

#### CLI 認証

```bash
# GitHub CLI — ブラウザ認証
gh auth login

# Codex — OpenAI API キーを設定
export OPENAI_API_KEY="sk-..."
# 永続化する場合
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.bashrc

# Claude Code — Anthropic API キーを設定
export ANTHROPIC_API_KEY="sk-ant-..."
# 永続化する場合
echo 'export ANTHROPIC_API_KEY="sk-ant-..."' >> ~/.bashrc
```

#### 確認コマンド

```bash
codex --version          # codex-cli x.x.x
claude --version         # x.x.x (Claude Code)
gh auth status           # Logged in to github.com as ...
```

### GitHub Actions (optional)

self-hosted runner で workflow を回す場合だけ必要:

- runner 上で `claude` `codex` `gh` が使える
- `OVERNIGHT_ENABLED=true` を GitHub Actions secrets に設定済み
- 通知する場合だけ `NOTIFICATION_WEBHOOK_URL` を設定

## Safety Guardrails

コマンド実行は deny-by-default です。

- `ls` と `cat` だけは無承認で実行可能
- devcontainer 内のワークスペース配下ファイル CRUD は許可
- それ以外のコマンドは事前承認済み allowlist に入っているものだけ実行可能
- 未承認コマンドは [command-gate.sh](/workspaces/dev-openclaw/scripts/overnight/command-gate.sh) が停止させ、承認要求ログを出します

allowlist のサンプルは [approved-commands.example.json](/workspaces/dev-openclaw/scripts/overnight/config/approved-commands.example.json) です。実運用では devcontainer または runner 上に実ファイルを配置して `APPROVED_COMMANDS_FILE` で参照してください。

## How To Use

### 1. 承認済みコマンド allowlist を用意する

例:

```bash
cp scripts/overnight/config/approved-commands.example.json /path/to/approved-commands.json
```

必要に応じて `git diff`, `npm test`, `pytest`, `dotnet test`, `mvn test` などを追加してください。

### 2. タスクソースを用意する（Issue またはローカル plan ファイル）

#### 方法 A: GitHub Issue

以下のテンプレートを使います。

- [auto-implement.yml](.github/ISSUE_TEMPLATE/auto-implement.yml)
- [auto-review.yml](.github/ISSUE_TEMPLATE/auto-review.yml)
- [auto-test.yml](.github/ISSUE_TEMPLATE/auto-test.yml)
- [auto-design.yml](.github/ISSUE_TEMPLATE/auto-design.yml)

Issue には `auto:*` ラベルを付けます。優先度制御には `priority:high` / `priority:low` を使います。

#### 方法 B: ローカル plan ファイル

GitHub Issue を使わず、`docs/plan/` 配下の Markdown ファイルからタスクを実行できます。

テンプレート: [docs/plan/_template.md](docs/plan/_template.md)

```markdown
# READMEにプロジェクト説明を追加

<!-- plan-meta
task-id: L001
labels: auto:implement, priority:high
-->

## 概要

プロジェクトの概要説明をREADMEに追加する。

## 要件

- プロジェクトの目的を記載
- セットアップ手順を記載

## 受入条件

- [ ] README.md が更新されている
- [ ] ビルドが通る
```

**plan-meta フィールド:**

| フィールド | 必須 | 説明 |
|-----------|------|------|
| `task-id` | 任意 | タスク識別子（例: `L001`）。省略時はファイル名から生成 |
| `labels` | 任意 | カンマ区切りラベル。省略時は `auto:implement` |

### 3. devcontainer で dry-run を実行する

#### Issue モード

```bash
gh auth status

APPROVED_COMMANDS_FILE=/path/to/approved-commands.json \
scripts/overnight/run-local.sh --issue-number <ISSUE_NUMBER> --dry-run
```

#### ローカル plan ファイルモード

```bash
APPROVED_COMMANDS_FILE=/path/to/approved-commands.json \
scripts/overnight/run-local.sh --plan-file docs/plan/my-task.md --dry-run
```

`--plan-file` モードでは `gh` コマンドや GitHub 認証は不要です。

dry-run では:

- タスク取得（Issue または plan ファイル）
- `overnight/{task-id}-{slug}` ブランチ作成または再利用
- Plan 生成
- 実装フローの疑似実行
- Review artifact 生成
- PR 向け review markdown 生成

artifact は `.overnight-artifacts/` に出力されます。

### 4. devcontainer で本番実行する

#### Issue モード

```bash
APPROVED_COMMANDS_FILE=/path/to/approved-commands.json \
scripts/overnight/run-local.sh --issue-number <ISSUE_NUMBER>
```

#### ローカル plan ファイルモード

```bash
APPROVED_COMMANDS_FILE=/path/to/approved-commands.json \
scripts/overnight/run-local.sh --plan-file docs/plan/my-task.md
```

処理内容:

1. タスク取得（Issue: `gh issue view` / plan ファイル: ローカル読み込み）
2. `overnight/{task-id}-{slug}` ブランチを作成
3. Claude Code で plan を作成
4. Claude Code が制限で失敗したら Codex に plan をフォールバック
5. Codex が実装
6. Claude Code がレビュー
7. review markdown を生成

`git add`, `git commit`, `gh pr create` は自動実行しません。最後に表示されるコマンドを手動で実行してください。

別ブランチで未コミット変更がある場合は、誤って作業内容を持ち替えないよう実行を停止します。対象の `overnight/...` ブランチ上での再実行は可能です。

## Local Validation

ローカルで最低限確認できる項目:

```bash
bash -n scripts/overnight/*.sh
ARTIFACT_DIR=/tmp/overnight-fetch DRY_RUN=true ISSUE_NUMBER=1 ISSUE_TITLE='Dry Run' ISSUE_BODY='Test' ISSUE_LABELS_JSON='["auto:implement"]' scripts/overnight/fetch-issues.sh
APPROVED_COMMANDS_FILE=scripts/overnight/config/approved-commands.example.json scripts/overnight/command-gate.sh ls scripts/overnight
```

ローカル一気通貫の dry-run 例:

```bash
# Issue モード
APPROVED_COMMANDS_FILE=scripts/overnight/config/approved-commands.example.json \
scripts/overnight/run-local.sh --issue-number <ISSUE_NUMBER> --dry-run

# ローカル plan ファイルモード（gh 不要）
APPROVED_COMMANDS_FILE=scripts/overnight/config/approved-commands.example.json \
scripts/overnight/run-local.sh --plan-file docs/plan/my-task.md --dry-run
```

未承認コマンド拒否の確認例:

```bash
ARTIFACT_DIR=/tmp/overnight-gate APPROVED_COMMANDS_FILE=scripts/overnight/config/approved-commands.example.json scripts/overnight/command-gate.sh git commit -m test
```

この場合は `exit 100` で停止し、`approval-requests.log` に記録されます。

## GitHub Actions Usage

self-hosted runner で夜間実行したい場合は、既存 workflow を使えます。

- Orchestrator: [.github/workflows/overnight-orchestrator.yml](/workspaces/dev-openclaw/.github/workflows/overnight-orchestrator.yml)
- Per-issue implementation flow: [.github/workflows/overnight-implement.yml](/workspaces/dev-openclaw/.github/workflows/overnight-implement.yml)
- Plan only workflow: [.github/workflows/overnight-plan.yml](/workspaces/dev-openclaw/.github/workflows/overnight-plan.yml)
- Review workflow: [.github/workflows/overnight-review.yml](/workspaces/dev-openclaw/.github/workflows/overnight-review.yml)
- Morning report workflow: [.github/workflows/overnight-report.yml](/workspaces/dev-openclaw/.github/workflows/overnight-report.yml)

`workflow_dispatch` で `Overnight Orchestrator` を起動し、`dry_run: true` で動作確認、`dry_run: false` で本番実行します。

## Files

- Plan document: [docs/plan/openclaw_plan.md](/workspaces/dev-openclaw/docs/plan/openclaw_plan.md)
- ExecPlan: [docs/execplans/overnight-automation.md](/workspaces/dev-openclaw/docs/execplans/overnight-automation.md)
- Overnight scripts: [scripts/overnight](/workspaces/dev-openclaw/scripts/overnight)
- Workflows: [.github/workflows](/workspaces/dev-openclaw/.github/workflows)

## Notes

- Claude review は現状フォールバックしません。Claude が使えない場合は review skipped 扱いになります。
- ローカル実行でも CLI 認証状態と allowlist は必須です。
- `run-local.sh` は `main` / `master` ではなく `overnight/...` ブランチ上で安全チェックを走らせます。
- 既存の作業ツリーが dirty な状態で夜間実行しないでください。
