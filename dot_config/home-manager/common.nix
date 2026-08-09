{
  pkgs,
  lib,
  config,
  ...
}:

{
  home.stateVersion = "26.05";
  programs.home-manager.enable = true;

  home.packages = with pkgs; [
    # secrets ツール
    sops
    age
    ssh-to-age
    _1password-cli # op: chezmoi age 鍵を 1Password から復元する run スクリプトが使う

    # cloud / k8s / infra
    awscli2
    azure-cli
    eksctl
    kubectl

    # dev CLI
    gh
    golangci-lint
    lefthook
    maestro
    pre-commit
    protobuf
    gemini-cli
    ghq
    hyperfine

    # JVM（Android SDK の sdkmanager / gradle が要求する。macOS 標準の
    # /usr/bin/java はスタブで実体を持たない）
    temurin-bin-21

    # editor / viewers
    neovim
    bat
    eza
    ripgrep
    fd
    ast-grep
    dust
    tig
    tree
    jq
    tokei
    yamllint
    k6

    # media / misc
    ffmpeg
    libwebp
    plantuml
    qrencode
    cdrtools
    gnupg
    gawk
    wget
    inetutils
    blueutil
    cocoapods
    watchman
  ];

  home.sessionVariables = {
    LANG = "ja_JP.UTF-8";
    KCODE = "u";
    CARAPACE_BRIDGES = "zsh,fish,bash,inshellisense";
    DIRENV_LOG_FORMAT = "";
    _ZO_DOCTOR = "0";
    PNPM_HOME = "$HOME/Library/pnpm";
    BUN_INSTALL = "$HOME/.bun";
    # sops CLI 用（CLI 組み込みの SSH 対応は agessh 流儀で ssh-to-age recipient を開けない）
    SOPS_AGE_KEY_CMD = "ssh-to-age -private-key -i ${config.home.homeDirectory}/.ssh/id_ed25519";
    HOMEBREW_FORBIDDEN_FORMULAE = "node python python3 pip npm pnpm yarn claude";
    # Android SDK は Android Studio が管理する ~/Library/Android/sdk に一本化する
    # （brew cask の cmdline-tools 既定 root ではなくこちらを使わせる）。
    # ANDROID_SDK_ROOT は非推奨だが gradle plugin / maestro 等が今も見るので両方置く。
    ANDROID_HOME = "$HOME/Library/Android/sdk";
    ANDROID_SDK_ROOT = "$HOME/Library/Android/sdk";
    JAVA_HOME = "${pkgs.temurin-bin-21.home}";
  };

  home.sessionPath = [
    "$HOME/.nix-profile/bin"
    "/run/current-system/sw/bin"
    "$HOME/.local/bin"
    "$HOME/Library/pnpm"
    "$HOME/.deno/bin"
    "$HOME/.bun/bin"
    "$HOME/.foundry/bin"
    "$HOME/Library/Android/sdk/platform-tools"
    "$HOME/Library/Android/sdk/emulator"
    "$HOME/Library/Android/sdk/cmdline-tools/latest/bin"
    "$HOME/.lmstudio/bin"
    "$HOME/.antigravity/antigravity/bin"
    "$HOME/go/bin"
  ];

  programs.zsh = {
    enable = true;
    autosuggestion.enable = false;
    syntaxHighlighting.enable = false;
    enableCompletion = true;

    shellAliases = {
      ls = "eza --icons -ahiluU --time-style=long-iso";
      ll = "eza --icons -l --git --time-style=long-iso";
      la = "eza --icons -ahiluU --git --time-style=long-iso";
      grep = "rg";
      find = "fd";
      du = "dust";
      dc = "docker compose";
      de = "docker compose exec";
      gab = "gcloud app browse";
      gpl = "gcloud projects list";
      fblogin = "firebase login";
      fblogout = "firebase logout";
      fbpl = "firebase projects:list";
      g = "git";
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gd = "git diff";
      gco = "git checkout";
      gp = "git pull";
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

    profileExtra = ''
      if [[ $(uname -m) == 'arm64' ]] && [[ $(uname -s) == 'Darwin' ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      fi
      source ~/.orbstack/shell/init.zsh 2>/dev/null || :
    '';

    initContent = lib.mkMerge [
      (lib.mkOrder 1000 ''
        setopt auto_cd
        setopt auto_pushd
        setopt nobeep

        # .zprofile の brew shellenv が login shell ごとに brew を PATH 先頭へ前置し直すため、
        # ここで毎シェル nix を先頭へ戻す（ネスト login shell の path_helper 対策も兼ねる）
        path=("$HOME/.nix-profile/bin" "/run/current-system/sw/bin" $path)
        typeset -U path

        # bun completions
        [ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

        # zoxide（cd を乗っ取り、frecency ジャンプ）。非対話シェルで init すると Claude Code が動かなくなる現象があるため対話シェルのみで init する。
        if [[ $- == *i* ]]; then
          eval "$(zoxide init zsh --cmd cd)"
        fi

        ghq() {
          if [ $# -eq 0 ]; then
            local repo_path
            repo_path=$(command ghq list | fzf --height 40% --reverse)
            if [[ -n "$repo_path" ]]; then
              cd "$(command ghq root)/$repo_path"
            fi
          else
            command ghq "$@"
          fi
        }

        ghq-fzf_change_directory() {
          local src=$(command ghq list | fzf --preview "eza -l -g -a --icons $(command ghq root)/{} | tail -n+4 | awk '{print \$6\"/\"\$8\" \"\$9 \" \" \$10}'")
          if [ -n "$src" ]; then
            BUFFER="cd $(command ghq root)/$src"
            zle accept-line
          fi
          zle -R -c
        }
        zle -N ghq-fzf_change_directory
        bindkey '^f' ghq-fzf_change_directory

        # 層1 secret: sops-nix が復号した 0400 ファイルから export（値は nix store に焼かれない）
        ${lib.concatMapStringsSep "\n      " (
          name:
          ''[[ -r "${config.sops.secrets.${name}.path}" ]] && export ${name}="$(<"${
            config.sops.secrets.${name}.path
          }")"''
        ) (builtins.attrNames config.sops.secrets)}
      '')

      # zsh-autosuggestions の async モードを無効化する。async は候補取得を fork し、
      # 子プロセスが「PID を1行目、候補本体を2行目以降」の順でパイプへ書き、親が read で
      # PID 行を捨てる実装（zsh-autosuggestions.zsh の `echo $sysparams[pid]` と直後の read）。
      # 前のリクエストのキャンセル（fd クローズ + kill -TERM）と競合すると読み捨てに失敗し、
      # PID の数字がそのまま候補として提示され、Ctrl+E / → で確定すると行に数字が入る。
      # 同期モードには fork もパイプも無いのでこの経路ごと消える。atuin strategy は毎
      # キーストロークで `atuin search` を起動する（実測 ~15ms）ぶん競合しやすいが、
      # ここでは同期化のコストよりバグを消す方を取る。
      # プラグインは source 時に無条件で async を有効化するので、sheldon より後に置く。
      (lib.mkAfter ''
        unset ZSH_AUTOSUGGEST_USE_ASYNC
      '')
    ];
  };

  # git 設定（旧 ~/.dotfiles/.gitconfig から移植。user.name/email は flake.nix の homeUser）。
  programs.git = {
    enable = true;
    ignores = [
      "**/.claude/settings.local.json"
      ".local/**"
      "mise.toml"
      ".mise.toml"
      "mise.local.toml"
      ".mise.local.toml"
      "apm_modules/"
      ".frontend-review/"
    ];
    settings = {
      alias = {
        co = "checkout";
        chk = "checkout";
        cdev = "checkout -b develop origin/develop";
        grh = "reset HEAD";
      };
      init.defaultBranch = "main";
      branch.sort = "-committerdate";
      tag.sort = "version:refname";
      commit.gpgsign = true;
      gpg.format = "ssh";
      user.signingKey = "~/.ssh/id_ed25519.pub";
      url."git@github.com:".insteadOf = "https://github.com/";
      commit.verbose = true;
      push = {
        default = "simple";
        autoSetupRemote = true;
        followTags = true;
      };
      fetch = {
        prune = true;
        pruneTags = true;
        all = true;
      };
      pull.rebase = true;
      help.autocorrect = "prompt";
    };
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
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
    # Ctrl-R は atuin が持つので fzf の履歴ウィジェットは外す（Ctrl-T / Alt-C は残る）
    historyWidget.command = "";
  };

  # 履歴検索（Ctrl-R を atuin が置換。↑キーは奪わない）
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    flags = [ "--disable-up-arrow" ];
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = false;
  };

  # 補完強化
  programs.carapace = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.mise = {
    enable = true;
    enableZshIntegration = true;
    globalConfig = {
      tools = {
        python = "3.12";
        node = "24";
        go = "latest";
        pnpm = "latest";
        bun = "latest";
        uv = "latest";
      };
    };
  };

  # agent multiplexer。settings → ~/.config/herdr/config.toml（https://herdr.dev/docs/configuration/）
  programs.herdr = {
    enable = true;
    settings = {
      ui.toast.clipboard.enabled = false;
      ui.prompt_new_tab_name = false;
      keys = {
        prefix = "ctrl+b";
        cycle_pane_previous = [
          "prefix+shift+tab"
          "prefix+o"
        ];
        previous_workspace = [
          "prefix+up"
          "prefix+u"
        ];
        next_workspace = [
          "prefix+down"
          "prefix+i"
        ];
        next_agent = "prefix+a";
        previous_agent = "prefix+shift+a";
      };
    };
  };

  # herdr の Claude Code integration を herdr 自身に install させる。hook スクリプト
  # （~/.claude/hooks/herdr-agent-state.sh）は herdr がバージョン管理するので chezmoi では
  # 持たず（.chezmoiignore で除外）、settings.json の SessionStart エントリだけ committed。
  # store パス直指定なので PATH 非依存、冪等（settings は正規形一致で no-op、スクリプトだけ更新）。
  # ~/.claude 未作成時（fresh machine で chezmoi apply 前）は skip、失敗しても switch は止めない。
  home.activation.herdrClaudeIntegration = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "$HOME/.claude" ]; then
      $DRY_RUN_CMD "${config.programs.herdr.package}/bin/herdr" integration install claude || true
    fi
  '';

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
