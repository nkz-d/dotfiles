# Layer 1: personal global secrets, managed with sops-nix.
# Values exist only in secrets/global.json (age ciphertext, committed, safe to
# publish). This file holds declarations only — never a value.
#
# Decryption identity: a dedicated age key at ~/.config/sops/age/keys.txt,
# shared across machines and restored from 1Password (Secure Note
# `sops-age-key` in the `dotfiles` vault) by
# .chezmoiscripts/run_before_restore-age-keys.sh. It is deliberately NOT the
# SSH key: that key authenticates to GitHub and signs commits, and sops-nix
# must read its key non-interactively, so sharing one key would force the SSH
# key to stay passphrase-less and make a single file leak fatal for all three
# roles. The public recipient lives in .sops.yaml (source: dot_sops.yaml).
{ config, ... }:
{
  sops = {
    # No hard-coded absolute path: machines whose home is not /Users/<username>
    # must still find the key.
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

    defaultSopsFile = ./secrets/global.json;
    defaultSopsFormat = "json";

    # Each secret is decrypted at home-manager activation and placed outside
    # the nix store as a 0400 file (config.sops.secrets.<name>.path). Names
    # declared here must match keys in secrets/global.json. The export into
    # the shell happens in common.nix (programs.zsh.initContent).
    secrets = {
      EXAMPLE_TOKEN = { };
    };
  };
}
