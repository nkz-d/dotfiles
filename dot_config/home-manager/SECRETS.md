# Secrets (sops-nix)

Secret management for the home-manager layer of this repo. Secrets are encrypted
with **sops-nix** and decrypted at `home-manager switch` activation, so plaintext
never lands in the world-readable nix store.

> There are **two independent age-based systems** in this repo — don't conflate them:
> - **chezmoi age** (`~/.config/age/key.txt`, recipient `age1pjeah6g…`): encrypts whole
>   files that chezmoi deploys into `~` (`encrypted_*.age`). Decrypts at `chezmoi apply`.
> - **sops-nix age** (this doc): encrypts *values* (env vars) the nix layer needs.
>   Decrypts at home-manager activation. Uses a different identity (see below).

## What lives in this repo vs. what does not

Only non-secret material is committed:

- `.sops.yaml` (source: `dot_sops.yaml`) — the age **public** recipient. Safe to publish.
- `secrets/*.json` — sops **ciphertext**. Encrypted, safe to publish.
- `secrets.nix` — declarations and **paths** only, never values.

The **decryption key is never in the repo**: it is the SSH ed25519 private key
`~/.ssh/id_github`, used directly as an age identity via `ssh-to-age`
(`sops.age.sshKeyPaths` in `secrets.nix`). No dedicated age key is created.

> Note: `~/.ssh/config` is chezmoi-managed (`private_dot_ssh/`), but keys are
> never in any repo (`.chezmoiignore` guards `.ssh/id_*`), never in 1Password
> (which holds only the **chezmoi-age** key), and never copied between machines
> — each machine's own key is enrolled as a recipient (see "New machine").
> Losing **all** recipient keys makes `secrets/*.json` permanently
> undecryptable, so keep the enrolled set non-empty at all times.

## Layers

| Layer | File | Scope | Delivery |
|-------|------|-------|----------|
| 1 — global personal | `secrets/global.json` (`EXAMPLE_TOKEN`) | every shell | declared in `secrets.nix`; sops-nix decrypts at activation to `config.sops.secrets.<name>.path` (mode 0400, outside the nix store); `secrets.nix` writes `~/.config/sops-export.sh` which `export`s each `$(<path)` |
| 2 — project / per-repo | `secrets/personal.json` (empty) | one repo only | intended for per-repo direnv (`sops -d --extract` in `.envrc`) — **not wired yet** |

Decision rule for a new key: *do I want it in every shell unconditionally, or only
while working in one repo?* When in doubt, prefer layer 2 (narrower scope).

## Use a secret in your shell

`secrets.nix` generates `~/.config/sops-export.sh` (only the **path** is baked into
the nix store, never the value). Source it from your existing `~/.zshrc`:

```sh
[ -f ~/.config/sops-export.sh ] && source ~/.config/sops-export.sh
```

(Once `programs.zsh` is managed by home-manager, fold this into `initContent` and
drop the manual `source` line.)

## Add / edit a layer-1 secret

Edit the ciphertext **in the chezmoi source dir** (recipients are read from the
file's own metadata, so no `.sops.yaml` is needed for edits):

```sh
cd ~/.local/share/chezmoi/dot_config/home-manager
sops secrets/global.json          # opens decrypted in $EDITOR; save re-encrypts
# if adding a NEW name, also declare it in secrets.nix:
#   sops.secrets.NEW_NAME = { };
chezmoi apply -v
cd ~/.config/home-manager && home-manager switch --flake .#macos
```

The export loop in `secrets.nix` is generated from `config.sops.secrets`, so a new
name is picked up automatically once declared.

## New machine

The adopted model is **one key per machine**: each machine generates its own
`~/.ssh/id_github`, registers it with GitHub, and is enrolled as a sops
recipient. Private keys are never copied between machines, and a machine can
be revoked individually.

The catch: `sops updatekeys` re-encrypts using an *existing* recipient's
private key, so enrolling a new machine always needs a machine that still
holds a current key — **do the enrollment while the old machine is alive**.
If no such machine is left, the emergency fallback is copying a surviving key
directly; 1Password holds only the chezmoi-age key, not SSH keys, and losing
every recipient key means the ciphertext is gone for good.

```sh
# on the new machine
ssh-keygen -t ed25519 -f ~/.ssh/id_github -N "" -C "$(hostname -s)"
# register ~/.ssh/id_github.pub with GitHub, then:
ssh-to-age -i ~/.ssh/id_github.pub          # -> age1... public key

# ON A MACHINE THAT ALREADY HOLDS A CURRENT KEY (e.g. the old Mac):
# add that age1... to dot_sops.yaml `keys:`, then re-encrypt to all recipients:
sops --config ~/.config/home-manager/.sops.yaml updatekeys secrets/global.json
# commit + push, then on the new machine:
chezmoi update && home-manager switch --flake ~/.config/home-manager#macos
```

To revoke a lost machine: drop its recipient from `dot_sops.yaml`, run
`sops updatekeys`, commit. Rotate the secret values too if it may have been compromised.

## Gotchas

- `nix build` runs in a sandbox that hides `~/.ssh`, so it never reads the key —
  but that's fine: decryption happens at **activation** (`home-manager switch`),
  outside the sandbox. Build/eval succeed without the key.
- `nix flake lock` / `flake update` for `sops-nix` hits the GitHub API and may 403 on
  rate limit. Authenticate: `NIX_CONFIG="access-tokens = github.com=$(gh auth token)" nix flake lock`.
- sops-nix runs in the **standalone home-manager** layer (`homeConfigurations."macos"`).
  nix-darwin (`darwinConfigurations."macos"`) is a separate, system-only config that does
  **not** embed home-manager, so secrets stay entirely in the home-manager layer —
  `secrets.nix` is imported only by the shared `homeUser` module, never by the darwin module.
