# NotebookLM 音声解説生成ツール

Google NotebookLM の Audio Overview 機能を Playwright で自動化し、PDF や画像から音声解説を生成・ダウンロードする CLI ツール。

## セットアップ

### 依存インストール

```bash
pip install -r backendapp/requirements.txt
playwright install chromium
```

### Google ログイン（初回のみ）

初回は `--headless` なしでブラウザを起動し、Google アカウントにログインする。ログイン状態はブラウザプロファイルに保存され、以降は再認証不要。

```bash
python -m backendapp.notebooklm --slow-mo 500 dummy.pdf
```

ブラウザが開いたら Google にログインし、NotebookLM のページが表示されることを確認したら `Ctrl+C` で終了する。

プロファイルはデフォルトで `~/.notebooklm-profile/` に保存される。別の場所を使いたい場合は `--profile-dir` を指定する。

## 使い方

### 基本

```bash
python -m backendapp.notebooklm file.pdf
```

### 複数ファイル

```bash
python -m backendapp.notebooklm report.pdf slide.png photo.jpg
```

### オプション指定

```bash
python -m backendapp.notebooklm \
  --notebook "プロジェクト資料の解説" \
  -o ./audio_output \
  --slow-mo 500 \
  -v \
  doc1.pdf doc2.pdf
```

### ヘルプ

```bash
python -m backendapp.notebooklm --help
```

## オプション一覧

| オプション | デフォルト | 説明 |
|-----------|----------|------|
| `files` (位置引数) | 必須 | アップロードする PDF / 画像ファイル（複数可） |
| `--notebook` | `Overnight Audio` | NotebookLM に作成するノートブック名 |
| `-o`, `--output-dir` | `./output` | 音声ファイルの保存先ディレクトリ |
| `--profile-dir` | `~/.notebooklm-profile` | Chromium ブラウザプロファイルのパス |
| `--headless` | off | ヘッドレスモード（Google ログイン済みの場合のみ使用可） |
| `--slow-mo` | `300` | Playwright 操作の遅延（ms）。安定性に問題がある場合は増やす |
| `-v`, `--verbose` | off | DEBUG レベルのログ出力 |

## 対応ファイル形式

- PDF (`.pdf`)
- PNG (`.png`)
- JPEG (`.jpg`, `.jpeg`)
- GIF (`.gif`)
- WebP (`.webp`)

## 処理フロー

```
1. Chromium 起動（保存済みプロファイルで Google 認証済み）
2. https://notebooklm.google.com/ にアクセス
3. 新規ノートブック作成
4. ソース追加 → ファイルアップロード
5. Audio Overview パネルを開く
6. 「Generate」クリック → 生成完了まで待機（最大 10 分）
7. 音声ファイルをダウンロード → output-dir に保存
```

## トラブルシューティング

### ログインが切れた

プロファイルを削除して再ログインする。

```bash
rm -rf ~/.notebooklm-profile
python -m backendapp.notebooklm --slow-mo 500 dummy.pdf
```

### セレクタが見つからない（NotebookLM の UI 変更）

NotebookLM の UI が更新されると Playwright のセレクタが動かなくなる場合がある。以下のファイルを確認・修正する:

- `backendapp/notebooklm/uploader.py` — ノートブック作成・ファイルアップロードのセレクタ
- `backendapp/notebooklm/audio.py` — Audio Overview パネル・生成ボタンのセレクタ

`-v` オプションで DEBUG ログを有効にすると、どのステップで止まっているか確認できる。

### 音声生成に時間がかかる

ソースファイルのサイズや数によっては生成に数分かかる。タイムアウトは `audio.py` の `GENERATION_TIMEOUT_MS`（デフォルト 10 分）で調整可能。

## ディレクトリ構成

```
backendapp/notebooklm/
  __init__.py       # パッケージ宣言
  __main__.py       # python -m エントリポイント
  cli.py            # argparse CLI
  browser.py        # Playwright ブラウザセッション管理
  uploader.py       # ノートブック作成・ファイルアップロード
  audio.py          # Audio Overview 生成・ダウンロード
```
