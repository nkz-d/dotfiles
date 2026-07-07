# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is the **chezmoi source directory** (`~/.local/share/chezmoi`, `destDir = ~`) — the single source of truth for nekoze's dotfiles on macOS (`aarch64-darwin`). chezmoi renders/copies files from here into the home directory. The Nix layer (home-manager + nix-darwin) lives under `dot_config/home-manager/` (→ `~/.config/home-manager/`) and is itself deployed by chezmoi. Shell, CLI tools, GUI apps, and system settings have all been migrated here off the legacy `~/.dotfiles` repo.

Three layers, three jobs:

- **chezmoi** — deploys files from this repo into `~`. Run `chezmoi apply` after editing source here.
- **home-manager** (standalone, `homeConfigurations."macos"`) — installs CLI packages and manages shell/program config (zsh, starship, mise, …). Run `home-manager switch` after editing `common.nix`/`secrets.nix`.
- **nix-darwin** (`darwinConfigurations."macos"`) — manages macOS system settings and Homebrew (casks/mas/taps) declaratively. Run `sudo darwin-rebuild switch` after editing `darwin.nix`.

Nix files (under `dot_config/home-manager/`):

- `flake.nix` — inputs (nixpkgs, home-manager, nix-darwin, sops-nix) + the `homeConfigurations`/`darwinConfigurations` outputs. Identity from `private` (the generated `private.nix`); shared overlays in `sharedOverlays` (incl. a `mise` `doCheck=false` fix). `homeUser` is the shared home-manager module. Also `apps` (pinned `bootstrap-home`/`bootstrap-darwin` first-run runners — never `nix run home-manager/master` or `nix run nix-darwin`, which pull unpinned masters) and a `formatter` output (nixfmt) so `nix fmt` works here.
- `common.nix` — the home-manager module: `home.packages` (CLI from nixpkgs) + shell stack (`programs.zsh`/starship/atuin/zoxide/carapace/sheldon/mise/direnv/fzf) + PATH/env/aliases.
- `darwin.nix` — nix-darwin system module: boilerplate (`nix.enable=false` for Determinate) + the `homebrew` block.
- `secrets.nix` — sops-nix declarations (see Secrets below).

## Critical workflow rule

Never edit the deployed copies under `~/.config/...` directly — the next `chezmoi apply` overwrites them. Always edit the source in this repo (or use `chezmoi edit <target>`). The shell starts in `dot_config/`, so editing `dot_config/home-manager/*.nix` here _is_ editing the chezmoi source of `~/.config/home-manager/*.nix`.

## Source naming conventions (chezmoi)

chezmoi mangles source filenames into target paths under `~`:

- `dot_config/` → `~/.config/` (the `dot_` prefix becomes a leading `.`)
- `.chezmoi*` files are chezmoi's own config and are never deployed
- an `encrypted_` prefix or `.age` suffix marks age-encrypted source files

To see exactly what maps where: `chezmoi managed` and `chezmoi target-path <src>`.

## Common commands

chezmoi (run from anywhere):

```
chezmoi diff             # preview what apply would change in ~
chezmoi apply -v         # deploy source → home
chezmoi apply -n -v      # dry run
chezmoi edit <target>    # edit the source of a deployed file
chezmoi add <path>       # start managing an existing dotfile
chezmoi add --encrypt <path>   # add a file, encrypting it with age
chezmoi managed          # list everything chezmoi controls
```

Nix — home (`common.nix`/`secrets.nix`) and system (`darwin.nix`):

```
# home: CLI packages + shell/program config
home-manager switch -b backup --flake ~/.config/home-manager#macos

# system: macOS settings + Homebrew (casks/mas/taps)
sudo darwin-rebuild switch --flake ~/.config/home-manager#macos

nix flake update     # bump inputs; GitHub 403 on sops-nix? prefix NIX_CONFIG="access-tokens = github.com=$(gh auth token)"
nix flake check
nix fmt              # nixfmt formatter output (run from ~/.config/home-manager)
```

First-time activations (before `home-manager`/`darwin-rebuild` are on PATH) — pinned apps from this flake:

```
nix run ~/.config/home-manager#bootstrap-home     # home-manager 初回（-b backup 内蔵）
nix run ~/.config/home-manager#bootstrap-darwin   # darwin-rebuild 初回（sudo は内部で昇格）
```

## Secrets — two systems

This repo uses **two independent age-based encryption systems**. Don't conflate them.

**1. chezmoi age** — encrypts whole files that chezmoi deploys into `~`. `.chezmoi.toml.tmpl` sets the identity at `~/.config/age/key.txt` (recipient `age1pjeah6g…`). That key is **never** committed — `.chezmoiignore` guards `.config/age/**`. The identity is restored from 1Password by `run_before_decrypt-age-key.sh` (Secure Note `chezmoi-age-key` in the Private vault, read via the `op` CLI that home-manager installs as `_1password-cli`); the script runs before file apply and skips quietly if the key already exists or `op` isn't available. Encrypt files with `chezmoi add --encrypt` or an `encrypted_*.age` source name. Decrypts at `chezmoi apply`. Currently there are **no** encrypted-file sources yet, so this system is dormant until the first `chezmoi add --encrypt`.

**2. sops-nix** — encrypts _values_ (env vars) the home-manager layer needs, keeping plaintext out of the world-readable nix store. Decrypts at `home-manager switch` activation. The decryption identity is the SSH ed25519 key `~/.ssh/id_github` via `ssh-to-age` (`secrets.nix` → `sops.age.sshKeyPaths`); the public recipient lives in `dot_sops.yaml` (→ `~/.config/home-manager/.sops.yaml`), ciphertext in `secrets/*.json` (committed). Names declared in `secrets.nix` must match keys in `secrets/global.json`. Full workflow: **see `dot_config/home-manager/SECRETS.md`**.

`secrets/personal.json` is an empty layer-2 (per-repo direnv) placeholder — not wired yet.

## chezmoi init prompts

`.chezmoi.toml.tmpl` prompts on `chezmoi init` and stores the answers in chezmoi data, usable as `{{ .github_username }}` etc. in any `*.tmpl` source file:

- `github_username` (default `nekoze1210`)
- `claude_default_mode` (default `auto`)
- `git_name` (default = `github_username`)
- `git_email` (default = GitHub noreply)

`git_name`/`git_email` (plus the machine's `.chezmoi.username` / `.chezmoi.homeDir`) are rendered by `private.nix.tmpl` into `~/.config/home-manager/private.nix`, which `flake.nix` imports to set `home.username`, `home.homeDirectory`, and `programs.git`. The real email therefore lives only in `~/.config/chezmoi/chezmoi.toml`, never in the committed repo. Note: OS username is `daikinagaoka` but `$HOME` is `/Users/nekoze` — they differ, so home-manager takes `home.homeDirectory` from `private.homeDirectory` directly, and `darwin.nix` uses `/Users/<username>` as the standard with a fallback to `private.homeDirectory` when they differ.

## Current state / gotchas

- Both `homeConfigurations."macos"` and `darwinConfigurations."macos"` are live and validated with `nix build`. Shell + CLI + git + casks/mas have been migrated off `~/.dotfiles` (which now only holds `.vimrc`).
- `~/.ssh/config` is managed here (`private_dot_ssh/private_config`) — needed at bootstrap so a fresh machine can talk to GitHub over SSH. The **keys themselves are never committed** (`.chezmoiignore` guards `.ssh/id_*` etc.); `~/.ssh/id_github` must be restored out-of-band (1Password / old machine) and doubles as the sops-nix decryption identity, so `home-manager switch` fails without it.
- **Determinate Nix is the Nix install**, so `darwin.nix` sets `nix.enable = false` and `programs.zsh.enable = false` (don't let nix-darwin fight over `/etc/nix/nix.conf` or `/etc/zshrc`). Consequence: `/run/current-system/sw/bin` (where `darwin-rebuild` lives) is put on PATH by `common.nix`'s `programs.zsh.initContent`, not by nix-darwin.
- **home-manager is standalone, not a nix-darwin module** (no `useUserPackages`), so home packages live in `~/.nix-profile/bin`; `common.nix` prepends that ahead of `/opt/homebrew/bin` so nix tools beat brew.
- **OS username `daikinagaoka` ≠ `$HOME` `/Users/nekoze`** — never derive home from the username (`private.nix.tmpl` takes them from `.chezmoi.username` / `.chezmoi.homeDir` separately).
- `homebrew.onActivation.cleanup = "none"` — nix-darwin won't uninstall brew/casks not listed. Switch to `"uninstall"` to prune migrated formulae.
- Dropped from the Brewfile→nix migration (unused / not in nixpkgs / broken): `golang-migrate` (nixpkgs `migrate` is broken), `makeicns`, `ccusage`, `ki`. `mise` needs the `doCheck=false` overlay (a test fails on darwin).

