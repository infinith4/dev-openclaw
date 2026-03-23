#!/usr/bin/env bash
set -euo pipefail

# --- PATH setup (immediate + persistent) ---
export PATH="$PATH:$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.dotnet/tools:$HOME/bin"
grep -q '\.npm-global/bin' "$HOME/.bashrc" 2>/dev/null || \
  echo 'export PATH="$PATH:$HOME/.npm-global/bin:$HOME/.local/bin:$HOME/.dotnet/tools:$HOME/bin"' >>"$HOME/.bashrc"

mkdir -p "$HOME/bin" "$HOME/.npm-global"

# --- npm global tools ---
npm config set prefix "$HOME/.npm-global"
npm install -g eslint prettier @openai/codex @anthropic-ai/claude-code

# --- GitHub CLI ---
if ! command -v gh &>/dev/null; then
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt-get update -qq && sudo apt-get install -y -qq gh
fi

# --- Python tools ---
pip install --user ruff black

# --- Install backend dependencies ---
pip install --user -r /workspaces/dev-openclaw/backendapp/requirements.txt

# --- Install frontend dependencies ---
cd /workspaces/dev-openclaw/frontend && npm install
