# dotfiles

macOS (`aarch64-darwin`) dotfiles, managed in three layers:

| Layer                                                     | Owns                                                                                                                           | Source                                         |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------- |
| **chezmoi**                                               | Files deployed into `~` (`.zshrc`, `.config/*`, Karabiner, etc.) + machine identity                                            | this repo's root (`dot_*` sources)             |
| **home-manager** (standalone, `homeConfigurations.macos`) | CLI packages from nixpkgs + the shell stack (zsh / starship / atuin / zoxide / carapace / sheldon / mise / direnv / fzf) + git | `dot_config/home-manager/{common,secrets}.nix` |
| **nix-darwin** (`darwinConfigurations.macos`)             | macOS system defaults, Touch-ID sudo, and Homebrew (casks / mas / taps) declaratively                                          | `dot_config/home-manager/darwin.nix`           |

Design notes:

- **Determinate Nix** is the Nix install, so `darwin.nix` sets `nix.enable = false` (and `programs.zsh.enable = false`) to avoid fighting it.
- home-manager is **standalone**, not a nix-darwin module — home packages live in `~/.nix-profile/bin` and that dir is put first on `PATH`, so nix tools win over Homebrew.
- `chezmoi` itself is **curl-installed** to `~/.local/bin` (not via brew/nix), by design.
- `homebrew.onActivation.cleanup = "uninstall"` — only casks/mas/taps listed in `darwin.nix` survive; everything else is removed.
- Secrets use **two** age-based systems — see [`dot_config/home-manager/SECRETS.md`](dot_config/home-manager/SECRETS.md).

## Installation

```bash
# 1. Xcode Command Line Tools
xcode-select --install

# 2. Generate SSH Key
ssh-keygen -t ed25519 -N "" -C "$(hostname -s)" -f ~/.ssh/id_ed25519

# 3. Bootstrap chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"
chezmoi init --apply nkz-d/dotfiles.git

# 4. Install Nix (Determinate Systems installer recommended).
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

# 5. Bootstrap home-manager
nix run ~/.config/home-manager#bootstrap-home

# 6. Bootstrap nix-darwin
nix run ~/.config/home-manager#bootstrap-darwin

# 7. Login 1Password-CLI and Re-apply chezmoi to decrypt age
op signin && chezmoi apply -v

# 8. Add to GitHub for authentication and signing
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(scutil --get ComputerName)" --type authentication
gh ssh-key add ~/.ssh/id_ed25519.pub --title "$(scutil --get ComputerName)-signing" --type signing
# Verify SSH connection
ssh -T git@github.com
```

## Daily workflow

| Change                                          | Edit                                               | Apply (from anywhere)                                             |
| ----------------------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------- |
| A dotfile (`~/.zshrc` indirectly, Karabiner, …) | `dot_*` source in this repo                        | `chezmoi apply -v`                                                |
| CLI package / shell / `programs.*` / git        | `dot_config/home-manager/common.nix`               | `home-manager switch --flake ~/.config/home-manager#macos`        |
| A secret value                                  | `sops dot_config/home-manager/secrets/global.json` | `home-manager switch --flake ~/.config/home-manager#macos`        |
| macOS setting / Homebrew cask·mas·tap           | `dot_config/home-manager/darwin.nix`               | `sudo darwin-rebuild switch --flake ~/.config/home-manager#macos` |

See [`CLAUDE.md`](CLAUDE.md) for the full architecture/working notes and [`dot_config/home-manager/SECRETS.md`](dot_config/home-manager/SECRETS.md) for the secrets workflow.

## Acknowledgements

Inspired by [mizchi/chezmoi-dotfiles](https://github.com/mizchi/chezmoi-dotfiles).
