#!/usr/bin/env sh
# Bootstrap: install Homebrew into /opt/homebrew if missing, so nix-darwin's
# homebrew module has brew present before the first `darwin-rebuild switch`.
# chezmoi run_once_before hook (runs once per machine, before file apply).
# 注: /opt/homebrew は作成に root が要るため、真っさらな Mac では公式 installer が
#     sudo を一度だけ要求する（既に brew があれば skip）。
# 注: 非公式 tap の trust は darwin.nix (homebrew.taps の trusted = true) が
#     宣言的に担うので、ここでは扱わない。
set -eu

if command -v brew >/dev/null 2>&1 || [ -x /opt/homebrew/bin/brew ]; then
  exit 0
fi

# NONINTERACTIVE の installer は `sudo -n` で権限チェックするため、sudo の
# タイムスタンプが無い真っさらなマシンでは必ず落ちる。先にここで対話的に
# sudo を取っておく（sudo は /dev/tty から読むので chezmoi 経由でも聞ける）。
if ! /usr/bin/sudo -n -v 2>/dev/null; then
  echo "[chezmoi] Homebrew の導入に管理者パスワードが必要です（sudo）" >&2
  if ! /usr/bin/sudo -v; then
    echo "[chezmoi] sudo 権限が取れません — $(id -un) が管理者アカウントか確認してください" >&2
    exit 1
  fi
fi

echo "[chezmoi] Installing Homebrew into /opt/homebrew ..." >&2
NONINTERACTIVE=1 /bin/bash -c \
  "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
