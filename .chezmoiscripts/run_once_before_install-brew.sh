#!/usr/bin/env sh
# Bootstrap: install Homebrew into /opt/homebrew if missing, so nix-darwin's
# homebrew module has brew present before the first `darwin-rebuild switch`.
# chezmoi run_once_before hook (runs once per machine, before file apply).
# 注: /opt/homebrew は作成に root が要るため、真っさらな Mac では公式 installer が
#     sudo を一度だけ要求する（既に brew があれば skip）。
set -eu

if ! command -v brew >/dev/null 2>&1 && [ ! -x /opt/homebrew/bin/brew ]; then
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
fi

# 非公式 tap の trust。Homebrew は trust の無い third-party tap の formula/cask を
# ロードしない（darwin-rebuild の brew bundle が "untrusted tap" で落ちる）。
# 未 tap の名前でも通り、~/.homebrew/trust.json に記録される・冪等。
# ここのリストは darwin.nix の homebrew.taps と対で保守すること。
BREW="$(command -v brew || echo /opt/homebrew/bin/brew)"
"$BREW" trust --tap anthropics/tap microsoft/apm \
  || echo "[chezmoi] brew trust をskip（古い brew には無いサブコマンド。darwin-rebuild が untrusted tap で落ちたら 'brew trust --tap <tap>' を手動実行）" >&2
