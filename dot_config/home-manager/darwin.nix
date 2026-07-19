{ private, ... }:

{
  # nix-darwin module schema version。破壊的変更を跨ぐとき以外は据え置き。
  system.stateVersion = 5;

  # 単一ユーザ環境。homebrew や user-scoped activation はこの user を見る。
  system.primaryUser = private.username;

  # ホームは通常 username から導出する (/Users/<username>)。ただし username と
  # ホーム名が食い違う環境（OS ユーザー名 ≠ $HOME の basename の機体）の
  # ときだけ private.homeDirectory（= chezmoi の .chezmoi.homeDir）へフォールバック。
  users.users.${private.username} = {
    name = private.username;
    home =
      let
        derived = "/Users/${private.username}";
      in
      if (private.homeDirectory or derived) == derived then derived else private.homeDirectory;
  };

  nixpkgs.hostPlatform = "aarch64-darwin";

  # Determinate Nix が daemon と /etc/nix/nix.conf を管理しているので、nix-darwin 側の
  # Nix 管理は完全にオフ。これがないと両者が nix.conf/launchd を取り合って壊れる。
  nix.enable = false;

  # /etc/zshrc は Determinate Nix 由来のものを尊重し、nix-darwin 側では触らない
  # （shell は home-manager の programs.zsh が ~/.zshrc を管理している）。
  programs.zsh.enable = false;

  # --------------------------------------------------------------------------
  # Homebrew bridge — casks / mas / taps を宣言的に管理する（③ の主目的）。
  # cleanup = "uninstall": この宣言(Brewfile)に無い brew/cask は uninstall される
  # ＝宣言が source of truth。CLI は nixpkgs へ移行済みなので brews は mas のみ。
  # 意図的に「ここに置かない」もの（cleanup で撤去される）:
  #   - chezmoi: curl(get.chezmoi.io)で ~/.local/bin に入れる前提
  #   - zsh: Apple 標準 /bin/zsh を使う（chsh で切替。brew zsh は撤去）
  #   - python@3.12 / python-tk / ruby-build / gcc / terraformer: 不要として撤去
  #   - 1password-cli(op)→nix / google-cloud-sdk→gcloud-cli に一本化
  # prefix は標準の /opt/homebrew
  # --------------------------------------------------------------------------
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = false;
      cleanup = "uninstall";
      upgrade = false;
    };

    taps = [
      {
        name = "anthropics/tap";
        trusted = true;
      }
      {
        name = "microsoft/apm";
        trusted = true;
      }
    ];

    brews = [
      "mas"
      "apm"
    ];

    casks = [
      "1password"
      "alt-tab"
      "anthropics/tap/ant"
      "blackhole-16ch"
      "blender"
      "chatgpt"
      "clipy"
      "codex"
      "cursor"
      "discord"
      "espanso"
      "expo-orbit"
      "figma"
      "font-fira-code-nerd-font"
      "font-hackgen"
      "font-hackgen-nerd"
      "font-iosevka"
      "gcloud-cli"
      "ghostty"
      "google-chrome"
      "google-japanese-ime"
      "icon-composer"
      "iterm2"
      "karabiner-elements"
      "keyboardcleantool"
      "ngrok"
      "obsidian"
      "orbstack"
      "raycast"
      "visual-studio-code"
    ];

    masApps = {
      "1Password for Safari" = 1569813296;
      "Apple Configurator" = 1037126344;
      "Developer" = 640199958;
      "GarageBand" = 682658836;
      "iMovie" = 408981434;
      "Keynote" = 409183694;
      "Kindle" = 302584613;
      "LINE" = 539883307;
      "Magnet" = 441258766;
      "Numbers" = 361304891;
      "Pages" = 361309726;
      "Slack" = 803453959;
      "TestFlight" = 899247664;
      "Transporter" = 1450874784;
      "Xcode" = 497799835;
    };
  };

  # --------------------------------------------------------------------------
  # Touch ID で sudo を通す → darwin-rebuild switch 等の毎回のパスワードが指紋に。
  # /etc/pam.d/sudo_local に書く方式なので macOS アップデートでも消えない。
  # --------------------------------------------------------------------------
  security.pam.services.sudo_local.touchIdAuth = true;

  # macOS デフォルト（旧 ~/.dotfiles/bootstrap.sh の `defaults write` を移植）。
  # darwin-rebuild switch で適用。反映に再ログインや Dock/SystemUIServer 再起動が
  # 要る項目もある。
  system.defaults = {
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 11; # 入力開始までの待ち（小さいほど速い）
      KeyRepeat = 1; # リピート速度（小さいほど速い）
      "com.apple.trackpad.scaling" = 3.0; # ポインタ速度（0〜3, 大きいほど速い）
      "com.apple.mouse.tapBehavior" = 1; # タップでクリック（1=有効）
    };
    finder = {
      AppleShowAllFiles = true;
      ShowPathbar = true;
    };
    dock = {
      autohide = true;
      tilesize = 40;
      mineffect = "scale";
    };
    trackpad = {
      TrackpadThreeFingerDrag = true; # 3本指ドラッグ（内蔵トラックパッド）
      Clicking = true; # タップでクリック（内蔵）
    };
    menuExtraClock.ShowSeconds = true;

    WindowManager.EnableStandardClickToShowDesktop = false;

    # 型付きオプションが無いもの / 外付け(Bluetooth)トラックパッドのドメインは
    # 生 defaults として書く（domain → key → value）。
    CustomUserPreferences = {
      NSGlobalDomain = {
        AppleEnableSwipeNavigateWithScrolls = true; # 2本指スワイプで戻る/進む
      };
      "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
        TrackpadThreeFingerDrag = true;
        Clicking = true; # タップでクリック（外付け）
      };
    };

    # システム側（root で defaults write）。
    CustomSystemPreferences = {
      # IME 切り替え時のカーソル横ポップアップ（Sonoma 以降の入力インジケータ）を無効化
      "/Library/Preferences/FeatureFlags/Domain/UIKit" = {
        redesigned_text_cursor.Enabled = false;
      };
    };
  };
}
