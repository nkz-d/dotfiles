#!/usr/bin/env sh
# Installs espanso match packages via espanso's own package manager, instead of
# hand-maintaining large trigger lists in this repo. chezmoi run_once_before
# hook (runs once per machine/per script-content-change, before file apply and
# before run_onchange_after_espanso-service.sh).
#
# "one file, one owning layer": this script owns package installation only;
# match/packages/ itself is espanso-managed runtime state, not touched
# directly by chezmoi (see .chezmoiignore).
#
# Packages installed here:
#   - all-emojis (https://hub.espanso.org/all-emojis/): Slack/Discord-style
#     `:name:` emoji shortcodes (~1900 triggers), sourced from GitHub's gemoji
#     data (github/gemoji), distributed via the official espanso/hub index.
#
# To bump the pinned version: change --version below and add --force (chezmoi
# re-runs this script automatically since its content/hash changes). To add
# another package, copy the guard+install block with a new directory check.
set -eu

if ! command -v espanso >/dev/null 2>&1; then
  echo "[chezmoi] espanso not installed yet (run 'sudo darwin-rebuild switch' first) — will retry next apply" >&2
  exit 1
fi

if [ ! -d "$HOME/Library/Application Support/espanso/match/packages/all-emojis" ]; then
  echo "[chezmoi] Installing espanso package: all-emojis ..." >&2
  espanso package install all-emojis --version 0.1.0
fi
