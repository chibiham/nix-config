{
  description = "ちびはむ's Nix configuration";

  inputs = {
    # Nixパッケージ（安定版）
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # 更新の速いツール用（下のoverlayで個別に指定）
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

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

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      mac-app-util,
      ...
    }:
    let
      # 対応システム
      systems = [
        "aarch64-darwin" # macOS (Apple Silicon)
        "x86_64-darwin" # macOS (Intel)
        "x86_64-linux" # Ubuntu Server (Intel/AMD)
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;

      # 更新の速いツールはunstableから取る（それ以外はstable）
      unstableOverlay =
        system: final: prev:
        let
          unstable = import nixpkgs-unstable {
            inherit system;
            config = {
              allowUnfree = true;
              # Ubuntu機のRTX 3090 (Ampere) 専用。全CUDA世代をコンパイルせず、
              # llama.cppの初回構築時間とNix store使用量を抑える。
              cudaCapabilities = [ "8.6" ];
            };
          };
        in
        {
          inherit (unstable) gemini-cli flyctl llama-cpp;
        };

      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          config = {
            # unfreeパッケージを許可（1password-cli等）
            allowUnfree = true;
          };
          overlays = [ (unstableOverlay system) ];
        };

      # macOSユーザー用のHome Manager設定を生成
      mkDarwinHome =
        {
          username,
          system ? "aarch64-darwin",
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          modules = [
            ./home/common.nix
            ./home/darwin.nix
            mac-app-util.homeManagerModules.default # Spotlight統合
            {
              home.username = username;
              home.homeDirectory = "/Users/${username}";
            }
          ];
        };

      # Ubuntu/Linuxユーザー用のHome Manager設定を生成
      mkLinuxHome =
        {
          username,
          system ? "x86_64-linux",
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor system;
          modules = [
            ./home/common.nix
            ./home/linux.nix
            {
              home.username = username;
              home.homeDirectory = "/home/${username}";
            }
          ];
        };
    in
    {
      # Home Manager設定
      homeConfigurations = {
        "chibimaru@darwin" = mkDarwinHome { username = "chibimaru"; };
        "chibiham@darwin" = mkDarwinHome { username = "chibiham"; };
        "chibiham@ubuntu-server" = mkLinuxHome { username = "chibiham"; };
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

      # `nix fmt` 用フォーマッター
      formatter = forAllSystems (system: (pkgsFor system).nixfmt-rfc-style);
    };
}
