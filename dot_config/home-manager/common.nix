{ pkgs, lib, config, ... }:

{
  home.stateVersion = "26.05"; # 変更しないこと（home-manager のリリース互換）
  programs.home-manager.enable = true;

  # Brewfile 由来の CLI を brew → nixpkgs へ移行したもの（バイナリのみ）。
  # 設定込みで管理するもの（starship/direnv/fzf/mise/sheldon 等）は下の programs.* 側。
  # 除外（未使用のため管理対象外。nix にも brew にも入れない）:
  #   golang-migrate(migrate=broken) / makeicns / ccusage / ki(別物・qtwebengine broken)
  home.packages = with pkgs; [
    # secrets ツール
    sops
    age
    ssh-to-age
    _1password-cli # op: chezmoi age 鍵を 1Password から復元する run スクリプトが使う

    # cloud / k8s / infra
    awscli2
    aws-sam-cli
    azure-cli
    eksctl
    kubectl

    # dev CLI
    act
    gh
    golangci-lint
    pre-commit
    protobuf
    gemini-cli

    # editor / viewers（バイナリのみ・設定は既存流用）
    neovim
    bat
    eza
    tig
    tree
    jq
    tokei
    yamllint
    httpstat
    k6

    # media / misc
    ffmpeg
    libwebp # = brew の webp（cwebp/dwebp）
    graphviz
    plantuml
    qrencode
    cdrtools
    dvdauthor
    gnupg
    gawk
    wget
    inetutils # telnet 同梱
    blueutil
    cocoapods
    watchman
    llvm # 重い（~GB）。使っていなければ外してOK
  ];

  # ============================ shell stack (mizchi 流) ============================
  # 環境変数
  home.sessionVariables = {
    LANG = "ja_JP.UTF-8";
    KCODE = "u";
    CARAPACE_BRIDGES = "zsh,fish,bash,inshellisense";
    DIRENV_LOG_FORMAT = "";
    _ZO_DOCTOR = "0"; # zoxide の初期化順 doctor 警告を抑制（mizchi 同様）
    PNPM_HOME = "${config.home.homeDirectory}/Library/pnpm";
    BUN_INSTALL = "${config.home.homeDirectory}/.bun";
  };

  # 各種 runtime / tool の bin を PATH に追加（hm-session-vars 経由で前方に積まれる）
  home.sessionPath = [
    "$HOME/Library/pnpm"
    "$HOME/.deno/bin"
    "$HOME/.bun/bin"
    "$HOME/.foundry/bin"
    "$HOME/Library/Android/sdk/platform-tools"
    "$HOME/.lmstudio/bin"
    "$HOME/.antigravity/antigravity/bin"
    "$HOME/.local/bin"
    "$HOME/go/bin"
  ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = false; # sheldon の zsh-autosuggestions に任せる
    syntaxHighlighting.enable = false; # sheldon の fast-syntax-highlighting に任せる
    enableCompletion = true;

    shellAliases = {
      # eza
      ls = "eza --icons -ahiluU --time-style=long-iso";
      ll = "eza --icons -l --git --time-style=long-iso";
      la = "eza --icons -ahiluU --git --time-style=long-iso";
      # dir
      lab = "cd ~/Laboratory";
      # docker
      dc = "docker compose";
      de = "docker compose exec";
      # gcp / firebase
      gab = "gcloud app browse";
      gpl = "gcloud projects list";
      fblogin = "firebase login";
      fblogout = "firebase logout";
      fbpl = "firebase projects:list";
      # git（フル形のものは shell alias、git サブコマンド省略形は programs.git.settings.alias）
      g = "git";
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gd = "git diff";
      gco = "git checkout";
      gp = "git pull";
      gcm = "gitmoji -c";
      sw = "git switch";
    };

    history = {
      path = "$HOME/.zsh_history";
      size = 100000;
      save = 100000;
      ignoreDups = true;
      ignoreAllDups = true;
      share = true;
    };

    # .zprofile 相当（login shell）。brew shellenv / orbstack / kiro。
    profileExtra = ''
      [[ -f "''${HOME}/Library/Application Support/kiro-cli/shell/zprofile.pre.zsh" ]] && builtin source "''${HOME}/Library/Application Support/kiro-cli/shell/zprofile.pre.zsh"
      eval "$(/opt/homebrew/bin/brew shellenv)"
      source ~/.orbstack/shell/init.zsh 2>/dev/null || :
      [[ -f "''${HOME}/Library/Application Support/kiro-cli/shell/zprofile.post.zsh" ]] && builtin source "''${HOME}/Library/Application Support/kiro-cli/shell/zprofile.post.zsh"
    '';

    # programs.* で表現できない手書き分だけ
    initContent = ''
      export GPG_TTY=$TTY
      setopt auto_cd
      setopt auto_pushd
      setopt nobeep

      # nix profile と nix-darwin の system bin を PATH 最前へ（.zprofile の brew より優先）。
      # /run/current-system/sw/bin に darwin-rebuild 等が居る（nix.enable=false で /etc/zshrc を
      # 触らせていないので、ここで明示的に通す）。
      path=("$HOME/.nix-profile/bin" "/run/current-system/sw/bin" $path)
      typeset -U path

      # Kiro CLI (zshrc pre)
      [[ -f "''${HOME}/Library/Application Support/kiro-cli/shell/zshrc.pre.zsh" ]] && builtin source "''${HOME}/Library/Application Support/kiro-cli/shell/zshrc.pre.zsh"
      [[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"

      # gcloud SDK
      if [ -d "$HOME/google-cloud-sdk" ]; then
        source "$HOME/google-cloud-sdk/path.zsh.inc"
        source "$HOME/google-cloud-sdk/completion.zsh.inc"
      fi

      # bun completions
      [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

      # sheldon（plugins は programs.sheldon で宣言）
      eval "$(sheldon source)"

      # 層1 secret: sops-nix が復号した 0400 ファイルから export（値は nix store に焼かれない）
      ${lib.concatMapStringsSep "\n      " (
        name: ''[[ -r "${config.sops.secrets.${name}.path}" ]] && export ${name}="$(<"${config.sops.secrets.${name}.path}")"''
      ) (builtins.attrNames config.sops.secrets)}

      # Kiro CLI (zshrc post)
      [[ -f "''${HOME}/Library/Application Support/kiro-cli/shell/zshrc.post.zsh" ]] && builtin source "''${HOME}/Library/Application Support/kiro-cli/shell/zshrc.post.zsh"
    '';
  };

  # git 設定（旧 ~/.dotfiles/.gitconfig から移植。user.name/email は flake.nix の homeUser）。
  programs.git.settings = {
    alias = {
      co = "checkout";
      chk = "checkout";
      cdev = "checkout -b develop origin/develop";
      grh = "reset HEAD";
    };
    init.defaultBranch = "main";
    push.autoSetupRemote = true;
    # SSH 鍵でコミット署名（name/email は homeUser 側）
    commit.gpgsign = true;
    gpg.format = "ssh";
    user.signingKey = "~/.ssh/id_github.pub";
    # https の GitHub を ssh に書き換え
    url."git@github.com:".insteadOf = "https://github.com/";
  };

  # プロンプト（mizchi の設定: git_status を絵文字化）
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    # テーマは ./starship.toml（旧 ~/.dotfiles/.config/starship.toml を復元したもの）を
    # そのまま読み込む。home-manager がこれを ~/.config/starship.toml へ生成する
    # ＝ settings をインラインで書くのと等価だが、nerd-font glyph 込みの大きなテーマは
    # TOML のまま持つほうが編集しやすく写し間違いも防げる。変更後は home-manager switch。
    settings = builtins.fromTOML (builtins.readFile ./starship.toml);
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
    config.global.log_format = "";
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # 履歴検索（Ctrl-R を atuin が置換。↑キーは奪わない）
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    flags = [ "--disable-up-arrow" ];
  };

  # cd を zoxide が乗っ取り（frecency ジャンプ）
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = [ "--cmd" "cd" ];
  };

  # 補完強化
  programs.carapace = {
    enable = true;
    enableZshIntegration = true;
  };

  # runtime 管理（versions は既存の ~/.config/mise/config.toml をそのまま使う＝globalConfig 未指定）
  programs.mise = {
    enable = true;
    enableZshIntegration = true;
  };

  # zsh プラグイン（autosuggestions / syntax-highlighting / ni）
  programs.sheldon = {
    enable = true;
    settings = {
      shell = "zsh";
      plugins = {
        zsh-autosuggestions.github = "zsh-users/zsh-autosuggestions";
        fast-syntax-highlighting.github = "zdharma-continuum/fast-syntax-highlighting";
        ni.github = "azu/ni.zsh";
      };
    };
  };
}
