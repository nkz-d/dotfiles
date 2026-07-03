#!/bin/sh
# chezmoi の age 復号鍵 (~/.config/age/key.txt) を、無ければ 1Password から復元する。
# - chezmoi apply の「ファイル展開前」フェーズで毎回走る（鍵があれば即 exit で安価）。
# - 新マシンで op 未導入/未サインインでも apply を壊さない（静かに skip）。
#
# 前提: 1Password の Private vault に Secure Note "chezmoi-age-key" を作り、
#       本文に key.txt の中身（AGE-SECRET-KEY-... を含む全文）を貼っておくこと。
#       参照: op://dotfiles/chezmoi-age-key/notesPlain
set -eu

key="${HOME}/.config/age/key.txt"
[ -f "${key}" ] && exit 0

if ! command -v op >/dev/null 2>&1; then
  echo "chezmoi: op (1Password CLI) 未導入 — age 鍵の復元を skip（op 導入後に再 apply）" >&2
  exit 0
fi

mkdir -p "$(dirname "${key}")"
if op read "op://dotfiles/chezmoi-age-key/notesPlain" >"${key}" 2>/dev/null; then
  chmod 600 "${key}"
  echo "chezmoi: age 鍵を ${key} に復元しました" >&2
else
  rm -f "${key}"
  echo "chezmoi: 1Password から age 鍵を読めず skip（op signin 済みか確認）" >&2
fi
