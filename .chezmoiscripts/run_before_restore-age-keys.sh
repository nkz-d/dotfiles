#!/usr/bin/env sh
# Restore the age identities this repo needs from 1Password, if missing:
#   ~/.config/age/key.txt        chezmoi file encryption (encrypted_*.age sources)
#   ~/.config/sops/age/keys.txt  sops-nix (secrets/global.json) + sops CLI
# - Runs before file apply on every `chezmoi apply`; cheap when both exist.
# - Never breaks apply on a fresh machine: if `op` is missing or not signed in
#   it skips quietly, and the next apply retries.
#
# Setup: in the 1Password `dotfiles` vault, one Secure Note per key whose body
# is the whole key file (including the AGE-SECRET-KEY-... line):
#   op://dotfiles/chezmoi-age-key/notesPlain
#   op://dotfiles/sops-age-key/notesPlain
set -eu
umask 077 # key files and their directories must never be group/world readable, even briefly

restore() {
  key="$1"
  ref="$2"
  if [ -f "${key}" ]; then
    return 0
  fi
  if ! command -v op >/dev/null 2>&1; then
    echo "chezmoi: op (1Password CLI) not installed — skipping ${key} (re-apply after installing op)" >&2
    return 0
  fi
  mkdir -p "$(dirname "${key}")"
  if op read "${ref}" >"${key}" 2>/dev/null; then
    chmod 600 "${key}"
    echo "chezmoi: restored ${key} from 1Password" >&2
  else
    rm -f "${key}"
    echo "chezmoi: could not read ${ref} — skipping ${key} (is op signed in?)" >&2
  fi
}

restore "${HOME}/.config/age/key.txt" "op://dotfiles/chezmoi-age-key/notesPlain"
restore "${HOME}/.config/sops/age/keys.txt" "op://dotfiles/sops-age-key/notesPlain"
