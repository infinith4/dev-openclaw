# 自律夜間稼働環境 - Claude Code Planner × Codex Implementer

## Context
現在のdev-openclawリポジトリは13のAIエージェント、ExecPlanフレームワーク、Claude Code/Codex/Copilotの設定が整備されているが、**人間不在での自律稼働の仕組みがない**。夜間にGitHub Issueをタスクキューとして、Claude Codeが実行計画を作成し、Codexがその計画に沿って実装・テストを行い、翌朝PRとレポートが揃っている環境を構築する。

---

## アーキテクチャ

```
Cron (23:00 JST 任意に設定可能) → GitHub Actions Orchestrator
  → Issue取得 (auto:* ラベル)
  → Issue毎に:
    1. ブランチ作成 (overnight/{issue番号}-{slug})
    2. Claude Code で ExecPlan / 実装タスクリスト生成
    3. Codex で実装
    4. テスト実行
    5. Claude Code でレビュー/計画との差分確認
    6. PR作成
  → 朝レポート生成 (GitHub Issue + Slack通知)
```

### 役割分担

| AI | 固定役割 | 主要アウトプット |
|----|---------|----------------|
| Claude Code | プランニング、タスク分解、受入観点整理、実装後レビュー | `ExecPlan`、実装指示、レビューコメント |
| Codex | コード変更、テスト追加、ローカル検証、修正反復 | コミット候補差分、テスト結果、修正内容 |

---

## 作成するファイル

### GitHub Actions ワークフロー
| ファイル | 役割 |
|---------|------|
| `.github/workflows/overnight-orchestrator.yml` | メインcronワークフロー (00:00 JST = 15:00 UTC) |
| `.github/workflows/overnight-plan.yml` | 再利用可能: Claude Code で計画生成 |
| `.github/workflows/overnight-implement.yml` | 再利用可能: 実装ジョブ |
| `.github/workflows/overnight-review.yml` | 再利用可能: クロスレビュージョブ |
| `.github/workflows/overnight-report.yml` | 再利用可能: 朝レポート生成 |

### スクリプト
| ファイル | 役割 |
|---------|------|
| `scripts/overnight/fetch-issues.sh` | GitHub Issues取得 (auto:*ラベル、priority順) |
| `scripts/overnight/dispatch-claude-plan.sh` | Claude Code で ExecPlan / 実装タスク生成 |
| `scripts/overnight/dispatch-codex.sh` | Codex CLI で実装・テスト実行 |
| `scripts/overnight/dispatch-claude-review.sh` | Claude Code でレビューと計画準拠チェック |
| `scripts/overnight/cross-review.sh` | Claudeレビュー結果をPR本文向けに整形 |
| `scripts/overnight/command-gate.sh` | コマンド実行承認ゲート (allowlist 検査) |
| `scripts/overnight/safety-check.sh` | 安全性チェック (pre/post) |
| `scripts/overnight/generate-report.sh` | 朝サマリー生成 |
| `scripts/overnight/notify.sh` | Slack/Discord通知 |

### Issue テンプレート
| ファイル | 用途 |
|---------|------|
| `.github/ISSUE_TEMPLATE/auto-implement.yml` | 自動実装タスク |
| `.github/ISSUE_TEMPLATE/auto-review.yml` | 自動レビュータスク |
| `.github/ISSUE_TEMPLATE/auto-test.yml` | 自動テスト作成タスク |
| `.github/ISSUE_TEMPLATE/auto-design.yml` | 自動設計タスク |

---

## ラベル体系

| ラベル | ディスパッチ先 | 説明 |
|-------|------------|------|
| `auto:implement` | Claude計画 → Codex実装 → Claudeレビュー | 機能実装 |
| `auto:test` | Claude計画 → Codex実装 → Claudeレビュー | テスト作成 |
| `auto:review` | Claude計画 → Codex修正 → Claudeレビュー | 既存コードレビュー対応 |
| `auto:design` | Claude計画/設計 → Codex反映 → Claudeレビュー | 設計書作成/更新 |
| `auto:refactor` | Claude計画 → Codex実装 → Claudeレビュー | リファクタリング |
| `priority:high/low` | - | 処理順序制御 |
| `lang:typescript/python/csharp/java` | - | 言語ヒント |
| `overnight:in-progress/done/failed` | - | ステータス管理 |

---

## Claude Code でプラン生成

```bash
claude -p "$PLANNING_PROMPT" \
  --yes \
  --allowedTools "Read,Write,Edit,Glob,Grep,Bash(git *),Bash(npm *),Bash(pytest *),Bash(ruff *)" \
  --max-turns 50 \
  --output-format json \
  2>&1 | tee "$LOG_DIR/claude-${ISSUE_NUMBER}.log"
```

- 出力は `docs/execplans/overnight-{issue番号}.md` または `artifacts/overnight/plan-{issue番号}.md` に保存
- Claude Code はコード変更を行わず、Issue整理、前提確認、実装手順、受入条件、検証コマンドを定義する
- 複雑な変更は `.agent/PLANS.md` に従って ExecPlan 形式を必須にする

## Codex CLI で実装

```bash
codex exec \
  --sandbox workspace-write \
  "$IMPLEMENT_PROMPT" \
  2>&1 | tee "$LOG_DIR/codex-${ISSUE_NUMBER}.log"
```

- `IMPLEMENT_PROMPT` には Claude Code が生成した ExecPlan をそのまま埋め込む
- Codex は実装、単体テスト、必要なドキュメント更新、ローカル検証まで担当する
- すべてのコマンド実行は `command-gate.sh` 経由で承認済みコマンドのみ自動実行される
- 実装完了後、差分とテスト結果を Claude Code に戻してレビューさせる

---

## レビュー

1. Codex 実装完了後、`git diff main...HEAD` で差分取得
2. Claude Code が plan vs actual を比較し、未達・逸脱・追加リスクを判定
3. レビュー結果を JSON 出力 (`ok: true/false`, `plan_alignment`, `findings`)
4. `ok: false` の場合、Codex が修正 (最大3回)
5. 結果をPR本文に追記

必要であれば `.claude/skills/codex-review/SKILL.md` の出力形式を流用するが、レビュー主体は Claude Code とする

---

## 安全ガードレール

### 基本方針

**ファイル操作は devcontainer 内なら許可、コマンド実行は厳格承認制**とする。

### 実行ポリシー (deny-by-default)

すべてのコマンド実行はデフォルト拒否とし、以下の判定ルールで制御する:

| 判定 | 対象 | 説明 |
|------|------|------|
| **無承認許可** | `ls`, `cat` | allowlist 不要で常に実行可能 |
| **自動許可** | devcontainer 内ファイル CRUD | ワークスペース配下の create/read/update/delete |
| **条件付き許可** | allowlist 登録済みコマンド | 事前承認された prefix 一致コマンド |
| **拒否/保留** | 上記以外すべて | 未承認コマンドは実行せず承認要求イベントとして記録 |

- 未承認コマンドが必要になった時点でジョブを waiting-for-approval 相当で停止し、Issue/PR/通知に承認依頼を残す
- dry-run でも同じ承認判定を通す

### ファイルアクセス制御

- devcontainer 内のワークスペース配下ファイルに対する create/read/update/delete は許可
- 許可対象は repo 配下と devcontainer 内の作業用ディレクトリに限定
- ホスト側マウントや secrets 領域は除外
- 削除も許可するが、以下の保護対象パスへの操作は拒否:
  - `.git/` ディレクトリ
  - `*.key`, `credentials.*`, `.env*` など credential/secret 系パス

### コマンドゲート (`scripts/overnight/command-gate.sh`)

全スクリプトは `command-gate.sh` ヘルパーを経由してコマンドを実行する:

1. ジョブ開始時に allowlist (`approved-commands.json` or `.yaml`) を読み込み
2. 各スクリプトはコマンド実行前に必ず command-gate で検査
3. 未承認コマンドは実行せず、承認要求として記録・停止

### 承認済みコマンド管理

承認済みコマンドはリポジトリ外の runner ローカル設定、または専用 allowlist ファイルで管理する。

**フォーマット:**

| フィールド | 説明 |
|-----------|------|
| `command` | コマンド名 |
| `prefix` | 許可する引数 prefix |
| `description` | 用途説明 |
| `approved_by` | 承認者 |
| `approved_at` | 承認日時 |

**想定される承認済みコマンド例:**
- `git status`, `git diff`, `git log`
- `npm test`, `npm run lint`, `npm run build`
- `pytest`, `ruff check`
- `dotnet test`, `dotnet build`
- `mvn test`, `mvn compile`

### AI 別の実行モード

- Claude Code / Codex ともに、plan・implement・review の各スクリプトは同じコマンドゲートを通す
- `codex exec --approval-mode full-auto` は**廃止**し、承認ゲート連携前提のモードに切り替える
- Claude plan fallback を含め、どの AI が動いても同じ承認ルールを適用する

### Pre-execution チェック
- ブランチが `main`/`master` でないことを確認
- `.env`, `*.key`, `credentials.*` がステージされていないことを確認
- ワーキングディレクトリがクリーンであることを確認

### Post-execution チェック
- 変更ファイル数上限: 20ファイル
- 変更行数上限: 1000行
- 機密ファイルパターンスキャン (`.codex/config.toml` の `sensitive_patterns` 準拠)
- バイナリファイル、node_modules等の除外確認
- ハードコードされたシークレットのregexスキャン

### ワークフローレベル
- `timeout-minutes: 30` per issue
- `concurrency` で並列実行防止
- `OVERNIGHT_ENABLED` シークレットでキルスイッチ
- `OVERNIGHT_COST_CAP_USD` でコスト上限
- mainブランチ保護ルール必須

---

## CLI認証方式

この構成では `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` をワークフローに渡さない。代わりに、**CLIが事前にログイン済みの self-hosted runner** を前提とする。

### 前提

- runner 上で `claude` コマンドが単体で実行可能
- runner 上で `codex` コマンドが単体で実行可能
- Claude Code / Codex ともに対話ログインまたはローカル資格情報ストアで認証済み
- 認証情報は runner のユーザー領域に保持し、GitHub Actions secrets には保存しない

### 起動前チェック

```bash
claude --help >/dev/null
codex --help >/dev/null
```

必要なら別途 runner 初期化手順として、対話ログインを一度だけ手動実施する。

---

## 必要なシークレット

| シークレット | 用途 |
|------------|------|
| `NOTIFICATION_WEBHOOK_URL` | Slack/Discord通知 (任意) |
| `OVERNIGHT_ENABLED` | キルスイッチ ("true"で有効) |
| `OVERNIGHT_COST_CAP_USD` | コスト上限 (例: "10.00") |

AI実行に必要な認証は secrets ではなく runner 側の CLI ログイン状態で管理する。

---

## 実装順序

1. **Phase 1**: `scripts/overnight/` シェルスクリプト群 + Issueテンプレート
2. **Phase 2**: `overnight-plan.yml` + Claude ExecPlan 生成
3. **Phase 3**: `overnight-orchestrator.yml` + `overnight-implement.yml`
4. **Phase 4**: `overnight-review.yml` (Claudeレビュー)
5. **Phase 5**: `overnight-report.yml` + 通知
6. **Phase 6**: ハードニング (コスト追跡、エラーリカバリ、dry-runテスト)

---

## 検証方法

1. `workflow_dispatch` で手動トリガーし、`dry_run: true` でテスト
2. `auto:implement` ラベル付きの簡単なIssue (例: "READMEにプロジェクト説明を追加") で実行
3. PR作成・クロスレビュー・レポート生成の全フローを確認
4. `OVERNIGHT_COST_CAP_USD=0.01` でコスト制限テスト
5. 本番稼働: 3-5件のIssueで一晩テスト

---

## 既存資産の再利用

| 既存ファイル | 再利用方法 |
|------------|----------|
| `.claude/skills/codex-review/SKILL.md` | ClaudeレビューのJSON出力形式・指摘粒度の参考として採用 |
| `.claude/settings.json` | `--allowedTools` のベースライン |
| `.codex/config.toml` | `approval_policy: "never"` 設定済み |
| `.codex/agents/*.md` | プロンプト構築時のエージェント定義 |
| `AGENTS.md` | 13エージェントの役割定義をプロンプトに注入 |
| `.agent/PLANS.md` | ExecPlan形式でタスク管理 |
