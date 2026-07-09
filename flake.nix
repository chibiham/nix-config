{
  description = "ちびはむ's Nix configuration";

  inputs = {
    # Nixパッケージ（安定版）
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Home Manager
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # macOS Spotlight統合
    mac-app-util = {
      url = "github:hraban/mac-app-util";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, home-manager, mac-app-util, ... }:
    let
      # 対応システム
      systems = [
        "aarch64-darwin"  # macOS (Apple Silicon)
        "x86_64-darwin"   # macOS (Intel)
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        config = {
          # unfreeパッケージを許可（1password-cli等）
          allowUnfree = true;
        };
      };

      # macOSユーザー用のHome Manager設定を生成
      mkDarwinHome = { username, system ? "aarch64-darwin" }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          modules = [
            ./home/common.nix
            ./home/darwin.nix
            mac-app-util.homeManagerModules.default  # Spotlight統合
            {
              home.username = username;
              home.homeDirectory = "/Users/${username}";
            }
          ];
        };
    in
    {
      # Home Manager設定
      homeConfigurations = {
        "chibimaru@darwin" = mkDarwinHome { username = "chibimaru"; };
        "chibiham@darwin" = mkDarwinHome { username = "chibiham"; };
      };

      # flake.lockでピン留めされたhome-manager CLI
      # `nix run home-manager` (registry経由=master追従) ではなくこちらを使う:
      #   nix run .#home-manager -- switch --flake .#$USER@darwin
      apps = forAllSystems (system: {
        home-manager = {
          type = "app";
          program = "${home-manager.packages.${system}.home-manager}/bin/home-manager";
        };
      });
    };
}
