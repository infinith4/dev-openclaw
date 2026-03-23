# NotebookLM 音声解説生成ツール

<!-- plan-meta
task-id: L001
labels: auto:implement, priority:high
-->

## 概要

Google NotebookLM を使って、画像や PDF から音声解説（Audio Overview）を自動生成するための Python CLI ツールを作成する。NotebookLM は公式 REST API を提供していないため、Playwright でブラウザ操作を自動化する。

## 要件

### 機能要件

- 画像（PNG/JPG）や PDF を任意の数だけ NotebookLM のノートブックにアップロードする
- NotebookLM の Audio Overview 機能で音声データを生成する
- 生成された音声データ（WAV/MP3）をローカルにダウンロードする
- CLI からワンコマンドで実行できる

### 技術要件

- Python 3.12 + Playwright（ブラウザ自動化）
- Google アカウント認証は事前にブラウザプロファイルで済ませる前提
- `backendapp/notebooklm/` 配下に配置
- CLI エントリポイント: `python -m backendapp.notebooklm.cli`

### 入出力

- 入力: アップロード対象ファイルパス（複数指定可）
- 出力: ダウンロードした音声ファイルパス
- オプション: ノートブック名、出力ディレクトリ

## 画面操作フロー（Playwright 自動化対象）

1. https://notebooklm.google.com/ にアクセス
2. 新規ノートブック作成
3. ソース追加 → ファイルアップロード（PDF/画像）
4. Audio Overview パネルを開く
5. 「Generate」ボタンクリック → 生成完了まで待機
6. 音声ファイルをダウンロード

## ディレクトリ構成

```
backendapp/notebooklm/
  __init__.py
  cli.py          # CLI エントリポイント
  browser.py      # Playwright ブラウザ操作
  uploader.py     # ファイルアップロード処理
  audio.py        # Audio Overview 生成・ダウンロード
```

## 受入条件

- [ ] `python -m backendapp.notebooklm.cli --help` でヘルプが表示される
- [ ] PDF 1 ファイルをアップロードして音声生成・ダウンロードできる
- [ ] 複数ファイル（PDF + 画像）を一括アップロードできる
- [ ] エラー時に適切なメッセージが表示される
- [ ] ruff check / ruff format が通る
