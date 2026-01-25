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
        "x86_64-linux"    # Linux/WSL
      ];

      # 各システム用のpkgsを生成
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: import nixpkgs {
        inherit system;
        config = {
          # unfreeパッケージを許可（1password-cli等）
          allowUnfree = true;
        };
      };
    in
    {
      # Home Manager設定
      homeConfigurations = {
        # macOS (Apple Silicon) - MacBook Air
        "chibimaru@darwin" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor "aarch64-darwin";
          modules = [
            ./home/common.nix
            ./home/darwin.nix
            mac-app-util.homeManagerModules.default  # Spotlight統合
            {
              home.username = "chibimaru";
              home.homeDirectory = "/Users/chibimaru";
            }
          ];
        };

        # WSL (将来用)
        "chibimaru@wsl" = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor "x86_64-linux";
          modules = [
            ./home/common.nix
            ./home/wsl.nix
            {
              home.username = "chibimaru";
              home.homeDirectory = "/home/chibimaru";
            }
          ];
        };
      };
    };
}
