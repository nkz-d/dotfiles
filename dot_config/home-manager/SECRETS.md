# Secrets (sops-nix)

Secret management for the home-manager layer of this repo. Secrets are encrypted with **sops-nix** and decrypted at `home-manager switch` activation, so plaintext never lands in the world-readable nix store.

## What lives in this repo vs. what does not

Only non-secret material is committed:

- `.sops.yaml` (source: `dot_sops.yaml`) — the age **public** recipient. Safe to publish.
- `secrets/*.json` — sops **ciphertext**. Encrypted, safe to publish.
- `secrets.nix` — declarations and **paths** only, never values.

The **decryption key is never in the repo**: it is a dedicated age identity at `~/.config/sops/age/keys.txt` (`sops.age.keyFile` in `secrets.nix`; the sops CLI finds the same file through `SOPS_AGE_KEY_FILE`, set in `common.nix`). One key is shared by all machines and restored from 1Password (Secure Note `sops-age-key` in the `dotfiles` vault) by `.chezmoiscripts/run_before_restore-age-keys.sh` on every `chezmoi apply`, exactly like the chezmoi age key.

It is deliberately **not** the SSH key. `~/.ssh/id_ed25519` authenticates to GitHub and signs commits; sops-nix has to read its key non-interactively at activation. Sharing one key would force the SSH key to stay passphrase-less and make a single file leak fatal for all three roles at once (and, because the ciphertext history is public, for every value ever committed). Keep a passphrase on the SSH key.

## Layers

| Layer                  | File                                    | Scope         | Delivery                                                                                                                                                                                                            |
| ---------------------- | --------------------------------------- | ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1 — global personal    | `secrets/global.json` (`EXAMPLE_TOKEN`) | every shell   | declared in `secrets.nix`; sops-nix decrypts at activation to `config.sops.secrets.<name>.path` (mode 0400, outside the nix store); `common.nix` (`programs.zsh.initContent`) `export`s each `$(<path)` into every interactive shell |
| 2 — project / per-repo | `secrets/personal.json` (empty)         | one repo only | intended for per-repo direnv (`sops -d --extract` in `.envrc`) — **not wired yet**                                                                                                                                  |

Decision rule for a new key: _do I want it in every shell unconditionally, or only
while working in one repo?_ When in doubt, prefer layer 2 (narrower scope).

## Use a secret in your shell

Nothing to do: `common.nix` (`programs.zsh.initContent`) loops over
`config.sops.secrets` and `export`s each one from its decrypted path (only the
**path** is baked into the nix store, never the value). A new name declared in
`secrets.nix` is exported automatically after `home-manager switch`.

## Add / edit a layer-1 secret

Edit the ciphertext **in the chezmoi source dir** (recipients are read from the
file's own metadata, so no `.sops.yaml` is needed for edits):

```sh
cd $(chezmoi source-path)/dot_config/home-manager
sops secrets/global.json          # opens decrypted in $EDITOR; save re-encrypts
# if adding a NEW name, also declare it in secrets.nix:
#   sops.secrets.NEW_NAME = { };
chezmoi apply -v
cd ~/.config/home-manager && home-manager switch --flake .#macos
```

The export loop in `common.nix` is generated from `config.sops.secrets`, so a new
name is picked up automatically once declared.

## New machine

The model is **one shared sops key, kept in 1Password**. A new machine
generates nothing and nothing is re-encrypted: sign in to the 1Password CLI
and run `chezmoi apply` — `run_before_restore-age-keys.sh` writes
`~/.config/sops/age/keys.txt` (mode 0600) from the `sops-age-key` Secure Note,
and the next `home-manager switch` decrypts. See README step 6 for where this
sits in the bootstrap order: do it **before** the first `home-manager switch`.
Without the key sops-nix does not abort the switch; it just produces no secret
files, so the variables are silently absent from every shell until the key
exists and `home-manager switch` is run again. Check with
`ls ~/.config/sops-nix/secrets/`.

## Rotate the key (lost or possibly leaked machine)

`sops updatekeys` is **not** enough: it only re-wraps the existing data key, so
anyone who can decrypt an old version from the public git history can also
open the new file. Use `rotate`, which generates a fresh data key:

```sh
umask 077 && age-keygen -o ~/.config/sops/age/keys.txt.new   # prints the new age1... recipient
cd $(chezmoi source-path)/dot_config/home-manager
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  sops rotate -i --add-age <new age1...> --rm-age <old age1...> secrets/global.json
mv ~/.config/sops/age/keys.txt.new ~/.config/sops/age/keys.txt
# then: put the new recipient in dot_sops.yaml `keys:`, replace the body of the
# 1Password `sops-age-key` note with the new keys.txt, commit + push.
```

Old ciphertext stays in the public history and the old key can still open it,
so **rotate the secret values themselves** too whenever the key may have leaked.

## Gotchas

- `nix build` runs in a sandbox that hides `~/.config/sops`, so it never reads the key —
  but that's fine: decryption happens at **activation** (`home-manager switch`),
  outside the sandbox. Build/eval succeed without the key; activation does not.
- `nix flake lock` / `flake update` for `sops-nix` hits the GitHub API and may 403 on
  rate limit. Authenticate: `NIX_CONFIG="access-tokens = github.com=$(gh auth token)" nix flake lock`.
- sops-nix runs in the **standalone home-manager** layer (`homeConfigurations."macos"`).
  nix-darwin (`darwinConfigurations."macos"`) is a separate, system-only config that does
  **not** embed home-manager, so secrets stay entirely in the home-manager layer —
  `secrets.nix` is imported only by the shared `homeUser` module, never by the darwin module.
