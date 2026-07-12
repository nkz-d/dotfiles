{
  description = "nix config (home-manager + nix-darwin, macOS)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # 一時 input: herdr 0.7.3 用（overlay 参照）。本体 bump 時に撤去
    nixpkgs-herdr.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-darwin,
      sops-nix,
      nixpkgs-herdr,
      ...
    }:
    let
      system = "aarch64-darwin";

      pkgs = import nixpkgs {
        inherit system;
        overlays = sharedOverlays;
        config.allowUnfree = true; # _1password-cli (op) 等 unfree を許可
      };

      # マシン固有の identity。chezmoi が apply 時に private.nix.tmpl から
      # ~/.config/home-manager/private.nix を生成する（username=.chezmoi.username,
      # homeDirectory=.chezmoi.homeDir, git=init プロンプト）。private.nix が無い
      # 環境では下のフォールバックを使う。
      private =
        if builtins.pathExists ./private.nix then
          import ./private.nix
        else
          {
            username = "daikinagaoka";
            homeDirectory = "/Users/nekoze";
            gitName = "nekoze";
            email = "14988862+nekoze1210@users.noreply.github.com";
            githubUsername = "nekoze1210";
          };

      sharedOverlays = [
        (_: prev: {
          mise = prev.mise.overrideAttrs (_: {
            doCheck = false;
          });
          # herdr だけ新しい nixpkgs から取る（本体 pin の bump は Hydra の darwin
          # キャッシュ不足 + Tahoe の cctools ld クラッシュで時期尚早。整い次第
          # 本体を bump してこの input ごと撤去する）
          herdr = nixpkgs-herdr.legacyPackages.${prev.stdenv.hostPlatform.system}.herdr;
        })
      ];

      # home-manager 側の user モジュール（standalone と、③で足す nix-darwin module の
      homeUser =
        { ... }:
        {
          imports = [
            ./common.nix
            ./secrets.nix
            sops-nix.homeManagerModules.sops
          ];
          home.username = private.username;
          home.homeDirectory = private.homeDirectory;
          programs.git = {
            enable = true;
            settings = {
              user = {
                name = private.gitName;
                email = private.email;
              };
              ghq.user = private.githubUsername;
            };
          };
        };
    in
    {
      # Standalone home-manager: `home-manager switch --flake .#macos`
      homeConfigurations.macos = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [ homeUser ];
      };

      # nix-darwin（system 層 + homebrew 宣言管理）: `darwin-rebuild switch --flake .#macos`
      # home は当面 standalone home-manager 側で管理（useUserPackages によるパッケージ移動で
      # ~/.nix-profile/bin の PATH 設定が崩れるのを避けるため、home-manager の darwin module
      # 統合はあえてしない。統合は将来の選択肢）。
      darwinConfigurations.macos = nix-darwin.lib.darwinSystem {
        modules = [
          {
            nixpkgs.overlays = sharedOverlays;
            nixpkgs.config.allowUnfree = true;
          }
          ./darwin.nix
        ];
        specialArgs = { inherit private; };
      };

      # 初回ブートストラップ用の pin 済みランナー（README 手順5・6）。
      # `nix run home-manager/master` / `sudo nix run nix-darwin` は master の
      # 未 pin ランナーを取ってくるので使わない。自 flake の apps なら
      # ランナーも構成も flake.lock で固定され、./result も残らない。
      apps.${system} = {
        # 手順5: home-manager 初回 activation（-b backup 相当を内蔵）
        bootstrap-home = {
          type = "app";
          meta.description = "first-run home-manager activation (pinned, backs up clobbered files)";
          program = "${pkgs.writeShellScript "bootstrap-home" ''
            export HOME_MANAGER_BACKUP_EXT="''${HOME_MANAGER_BACKUP_EXT:-backup}"
            exec ${self.homeConfigurations.macos.activationPackage}/activate "$@"
          ''}";
        };
        # 手順6: darwin-rebuild 初回 switch（root が要るのは activation だけなので
        # 評価・ビルドはユーザ権限で済ませ、sudo はスクリプト内部で昇格する）
        bootstrap-darwin = {
          type = "app";
          meta.description = "first-run darwin-rebuild switch (pinned, sudo inside)";
          program = "${pkgs.writeShellScript "bootstrap-darwin" ''
            exec /usr/bin/sudo ${self.darwinConfigurations.macos.system}/sw/bin/darwin-rebuild switch --flake ${self}#macos "$@"
          ''}";
        };
      };

      # `nix fmt` 用フォーマッタ（nix ファイルはこのディレクトリ配下にしか無い）。
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
    };
}
