#!/usr/bin/env sh
# Bootstrap: install Homebrew into /opt/homebrew if missing, so nix-darwin's
# homebrew module has brew present before the first `darwin-rebuild switch`.
# chezmoi run_once_before hook (runs once per machine, before file apply).
# 注: /opt/homebrew は作成に root が要るため、真っさらな Mac では公式 installer が
#     sudo を一度だけ要求する（既に brew があれば skip）。
set -eu

if command -v brew >/dev/null 2>&1 || [ -x /opt/homebrew/bin/brew ]; then
  exit 0
fi

echo "[chezmoi] Installing Homebrew into /opt/homebrew ..." >&2
NONINTERACTIVE=1 /bin/bash -c \
  "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
