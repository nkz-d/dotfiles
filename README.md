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
# 0. Xcode Command Line Tools — a fresh /usr/bin/git is a stub that pops the
#    CLT install dialog on first use; get it out of the way before anything
#    clones. (Skip if `git --version` already works.)
xcode-select --install

# 1. RESTORE the SSH identity ~/.ssh/id_github (+ .pub) from 1Password or the
#    previous Mac. It is the sops-nix decryption identity (via ssh-to-age), the
#    git signing key, and the ONLY sops recipient — a freshly generated key
#    cannot decrypt secrets/*.json, and adding one as a recipient
#    (`sops updatekeys`, see SECRETS.md) needs a machine that still holds the
#    current key. So "generate a new key" is only an option while the old Mac
#    is alive. (~/.ssh/config is chezmoi-managed and arrives in step 3 — no
#    need to hand-write it; the key must be passphrase-less so sops-nix can
#    decrypt non-interactively at activation.)
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# …place id_github / id_github.pub in ~/.ssh, then:
chmod 600 ~/.ssh/id_github

# 2. chezmoi (curl-installed to ~/.local/bin).
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

# 3. Clone + deploy. Prompts for github_username / claude_default_mode /
#    git_name / git_email and renders ~/.config/home-manager/private.nix.
#    - Homebrew is auto-installed here (nix-darwin's homebrew module needs it
#      present); it asks for sudo once, so the account must be an Administrator.
#    - The run ENDS WITH AN ERROR from the espanso after-scripts ("espanso not
#      installed yet … will retry next apply"). Expected on a fresh Mac: every
#      file is already deployed at that point, and step 7's re-apply clears it
#      once step 6 has installed espanso.
chezmoi init --apply nekoze1210/chezmoi-dotfiles

# 4. Determinate Nix (flakes enabled by default). Open a new shell afterwards.
curl -fsSL https://install.determinate.systems/nix | sh -s -- install

# 5. home-manager (first activation — home-manager not on PATH yet).
#    Installs CLI + shell stack + `op`; sops-nix decrypts secrets with
#    ~/.ssh/id_github from step 1 ("no key could decrypt" here means that key
#    is missing or not the recipient). Open a new terminal afterwards.
nix run home-manager/master -- switch -b backup --flake ~/.config/home-manager#macos

# 6. Sign in to the App Store via the GUI FIRST (mas cannot sign in from the
#    CLI; if it fails anyway, sign in and re-run — it's idempotent. Xcode alone
#    is ~12GB). Then nix-darwin, via the flake.lock-pinned path (first
#    activation — darwin-rebuild not on PATH yet). macOS system activation
#    needs root: this first run asks for a password, then sudo becomes Touch ID.
cd ~/.config/home-manager
nix build .#darwinConfigurations.macos.system
sudo ./result/sw/bin/darwin-rebuild switch --flake .#macos

# 7. Re-apply — espanso now exists, so its package install + service
#    registration succeed.
chezmoi apply -v

# 8. GUI rituals that can't be automated:
#    - System Settings → Privacy & Security: allow espanso (Accessibility) and
#      Karabiner (driver extension + Input Monitoring).
#    - 1Password.app: sign in (needs the Secret Key from the Emergency Kit or
#      another signed-in device), enable Settings → Developer → "Integrate with
#      1Password CLI". Then restore the chezmoi-age key (only matters once
#      encrypted_* sources exist — run_before_decrypt-age-key.sh restores
#      ~/.config/age/key.txt from the `chezmoi-age-key` note):
op signin && chezmoi apply -v
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

`nix run home-manager/master …` and the `nix build … && sudo ./result/sw/bin/darwin-rebuild` dance are only the **first-run** ways to invoke home-manager / nix-darwin before they are on `PATH`. After the first switch, use `home-manager switch` / `darwin-rebuild switch` directly (the commands in the table).

## Gotchas

- **nix-darwin's `switch` requires root** — `sudo darwin-rebuild switch` is mandatory for the system layer; there is no sudo-free path. Touch ID makes it a fingerprint. The home-manager layer (most daily edits) needs **no sudo**.
- **`~/.ssh/id_github`** (ed25519, no passphrase) is the sops-nix decryption identity and the only sops recipient — without it, `home-manager switch` fails at activation. It is never in this repo: `~/.ssh/config` **is** managed (`private_dot_ssh/`), but keys are restored out-of-band (1Password) and `.chezmoiignore` guards them against an accidental `chezmoi add`. Back the key up before wiping/returning the old machine, or `secrets/*.json` becomes permanently undecryptable.
- **A `chezmoi apply` on a machine without espanso exits 1 by design** (the espanso after-scripts fail loudly so chezmoi retries them next apply) — files are still deployed; run `sudo darwin-rebuild switch` then re-apply.
- **OS username ≠ home dir** on the primary machine (`daikinagaoka` vs `/Users/nekoze`); identity comes from the chezmoi-generated `private.nix`, never derived from the username.
- **brew cleanup is destructive** (`cleanup = "uninstall"`): a `darwin-rebuild switch` removes any brew formula/cask/tap not declared in `darwin.nix`.
- Editing tools that rewrite their own config (Karabiner UI, kiro-cli) will drift from the chezmoi/home-manager source — re-capture with `chezmoi re-add <path>` (or fold into the nix config) after such edits.

See [`CLAUDE.md`](CLAUDE.md) for the full architecture/working notes and [`dot_config/home-manager/SECRETS.md`](dot_config/home-manager/SECRETS.md) for the secrets workflow.

## Acknowledgements

Inspired by [mizchi/chezmoi-dotfiles](https://github.com/mizchi/chezmoi-dotfiles).
