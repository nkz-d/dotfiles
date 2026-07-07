# 層1: 個人グローバル secret（sops-nix で管理）。
# 値は secrets/global.json（age 暗号文・commit 済み・公開してOK）にのみ存在し、
# このファイルは「参照宣言」だけ。値は一切ここに書かない。
#
# 復号鍵: ~/.ssh/id_ed25519（ed25519, パスフレーズなし）を ssh-to-age 経由で
# 公開 recipient は .sops.yaml（dot_sops.yaml）に置いてある。
{ config, ... }:
{
  sops = {
    # 絶対パスをハードコードしない: home が /Users/nekoze でないマシン
    # （username≠home の逆パターン含む）でも復号鍵を見つけられるように。
    age.sshKeyPaths = [ "${config.home.homeDirectory}/.ssh/id_ed25519" ];

    defaultSopsFile = ./secrets/global.json;
    defaultSopsFormat = "json";

    # 各 secret は home-manager activation 時に復号され、nix store の外に
    # 0400 ファイルとして置かれる（path は config.sops.secrets.<name>.path）。
    # ここで宣言した名前は secrets/global.json のキーと一致している必要がある。
    # 値の export は common.nix の programs.zsh.initContent 側で行う
    secrets = {
      EXAMPLE_TOKEN = { };
    };
  };
}
