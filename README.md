# dotfiles

nekoze's macOS (`aarch64-darwin`) dotfiles, managed in three layers:

| Layer | Owns | Source |
|-------|------|--------|
| **chezmoi** | Files deployed into `~` (`.zshrc`, `.config/*`, Karabiner, etc.) + machine identity | this repo's root (`dot_*` sources) |
| **home-manager** (standalone, `homeConfigurations.macos`) | CLI packages from nixpkgs + the shell stack (zsh / starship / atuin / zoxide / carapace / sheldon / mise / direnv / fzf) + git | `dot_config/home-manager/{common,secrets}.nix` |
| **nix-darwin** (`darwinConfigurations.macos`) | macOS system defaults, Touch-ID sudo, and Homebrew (casks / mas / taps) declaratively | `dot_config/home-manager/darwin.nix` |

Design notes:
- **Determinate Nix** is the Nix install, so `darwin.nix` sets `nix.enable = false` (and `programs.zsh.enable = false`) to avoid fighting it.
- home-manager is **standalone**, not a nix-darwin module — home packages live in `~/.nix-profile/bin` and that dir is put first on `PATH`, so nix tools win over Homebrew.
- `chezmoi` itself is **curl-installed** to `~/.local/bin` (not via brew/nix), by design.
- `homebrew.onActivation.cleanup = "uninstall"` — only casks/mas/taps listed in `darwin.nix` survive; everything else is removed.
- Secrets use **two** age-based systems — see [`dot_config/home-manager/SECRETS.md`](dot_config/home-manager/SECRETS.md).

## First-run install (new Mac)

```bash
# 0. Determinate Nix (flakes enabled by default). Open a new shell afterwards.
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

# 1. Homebrew — nix-darwin's homebrew module manages casks/mas but does NOT
#    install brew itself, so it must exist first.
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"

# 2. Restore the SSH ed25519 key to ~/.ssh/id_github.
#    It is BOTH the sops-nix decryption identity (via ssh-to-age) and the git
#    signing key, so home-manager activation in step 5 needs it present.
#    (Restore the *same* key out-of-band; or generate a new one and add its
#    recipient to dot_sops.yaml + `sops updatekeys` — see SECRETS.md.)
chmod 600 ~/.ssh/id_github

# 3. chezmoi (curl-installed to ~/.local/bin).
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# 4. Clone + deploy. Prompts for github_username / claude_default_mode /
#    git_name / git_email, renders ~/.config/home-manager/private.nix, and
#    lays down ~/.config/home-manager/* and the rest of the dotfiles.
chezmoi init --apply nekoze1210/chezmoi-dotfiles

# 5. home-manager (first activation — darwin-rebuild/home-manager not on PATH yet).
#    Installs CLI + shell stack + `op`, and sops-nix decrypts secrets using
#    ~/.ssh/id_github. Open a new terminal afterwards.
nix run github:nix-community/home-manager -- switch -b backup --flake ~/.config/home-manager#macos

# 6. nix-darwin (first activation / bootstrap — darwin-rebuild not on PATH yet).
#    Installs casks/mas/taps, macOS defaults, and Touch-ID-for-sudo.
#    This first run asks for your password; sudo becomes Touch ID afterwards.
cd ~/.config/home-manager
nix build .#darwinConfigurations.macos.system
sudo ./result/sw/bin/darwin-rebuild switch --flake .#macos

# 7. (optional) chezmoi-age key — only needed once you encrypt files with
#    `chezmoi add --encrypt`. Sign in to 1Password CLI (enable the app's
#    "Integrate with 1Password CLI"), then re-apply: run_before_decrypt-age-key.sh
#    restores ~/.config/age/key.txt from the `chezmoi-age-key` note.
op signin
chezmoi apply -v
```

The login shell is Apple's `/bin/zsh` (the macOS default — no `chsh` needed on a fresh Mac).

## Daily workflow

| Change | Edit | Apply (from anywhere) |
|--------|------|-----------------------|
| A dotfile (`~/.zshrc` indirectly, Karabiner, …) | `dot_*` source in this repo | `chezmoi apply -v` |
| CLI package / shell / `programs.*` / git | `dot_config/home-manager/common.nix` | `home-manager switch --flake ~/.config/home-manager#macos` (no sudo) |
| macOS setting / Homebrew cask·mas·tap | `dot_config/home-manager/darwin.nix` | `sudo darwin-rebuild switch --flake ~/.config/home-manager#macos` (Touch ID) |
| A secret value | `sops dot_config/home-manager/secrets/global.json` | the home-manager command above |
| Bump flake inputs | — | `nix flake update` (in `dot_config/home-manager`; on a GitHub 403 prefix `NIX_CONFIG="access-tokens = github.com=$(gh auth token)"`) |
| Format nix files | — | `nix fmt` (in `dot_config/home-manager`) |

`nix run …` is only the **first-run** way to invoke home-manager / nix-darwin before they are on `PATH`. After the first switch, use `home-manager switch` / `darwin-rebuild switch` directly (the commands in the table).

## Gotchas

- **nix-darwin's `switch` requires root** — `sudo darwin-rebuild switch` is mandatory for the system layer; there is no sudo-free path. Touch ID makes it a fingerprint. The home-manager layer (most daily edits) needs **no sudo**.
- **`~/.ssh/id_github`** (ed25519, no passphrase) is the sops-nix decryption identity — without it, `home-manager switch` can't decrypt secrets. `secrets.nix` references it by absolute path.
- **OS username ≠ home dir** on the primary machine (`daikinagaoka` vs `/Users/nekoze`); identity comes from the chezmoi-generated `private.nix`, never derived from the username.
- **brew cleanup is destructive** (`cleanup = "uninstall"`): a `darwin-rebuild switch` removes any brew formula/cask/tap not declared in `darwin.nix`.
- Editing tools that rewrite their own config (Karabiner UI, kiro-cli) will drift from the chezmoi/home-manager source — re-capture with `chezmoi re-add <path>` (or fold into the nix config) after such edits.

See [`CLAUDE.md`](CLAUDE.md) for the full architecture/working notes and [`dot_config/home-manager/SECRETS.md`](dot_config/home-manager/SECRETS.md) for the secrets workflow.
