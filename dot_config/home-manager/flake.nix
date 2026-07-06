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
      nixpkgs,
      home-manager,
      nix-darwin,
      sops-nix,
      ...
    }:
    let
      system = "aarch64-darwin";

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
          };

      sharedOverlays = [
        (_: prev: {
          mise = prev.mise.overrideAttrs (_: {
            doCheck = false;
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
            settings.user = {
              name = private.gitName;
              email = private.email;
            };
          };
        };
    in
    {
      # Standalone home-manager: `home-manager switch --flake .#macos`
      homeConfigurations.macos = home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs {
          inherit system;
          overlays = sharedOverlays;
          config.allowUnfree = true; # _1password-cli (op) 等 unfree を許可
        };
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

      # `nix fmt` 用フォーマッタ（nix ファイルはこのディレクトリ配下にしか無い）。
      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt;
    };
}
