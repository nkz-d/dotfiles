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
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-darwin,
      sops-nix,
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
      # identity は chezmoi が private.nix.tmpl から生成する private.nix から取る
      # （username=.chezmoi.username, homeDirectory=.chezmoi.homeDir, git=init プロンプト）。
      # private.nix はコミットしない（個人情報を平文でリポジトリに置かない）ので、flake の
      # 評価・switch は chezmoi apply 済みの ~/.config/home-manager で行うこと。
      private = import ./private.nix;

      sharedOverlays = [
        # 一時対応（2026-09）: dotnet-sdk_8（8.0.425）のソースビルドが aarch64-darwin の Hydra で
        # 失敗しており、それをテストでしか使わない pre-commit までキャッシュから落ちている。
        # テストを切って dotnet への依存を外す（preCheck が dotnet-sdk のパスを埋め込むので
        # それも空にする）。python3Packages.identify が pytestCheckHook を runtime dependencies に
        # 入れており doCheck と無関係に pytest フェーズが差し込まれるため dontUsePytestCheck も要る。
        # pre-commit が再びキャッシュされたらこの overlay は削除する。
        (final: prev: {
          pre-commit = prev.pre-commit.overridePythonAttrs (_: {
            doCheck = false;
            dontUsePytestCheck = true;
            preCheck = "";
          });
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
      # 素の nixfmt は stdin 専用になったので treefmt ラッパーの nixfmt-tree を使う。
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
