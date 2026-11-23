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

    # Oh My Pi（omp）。Claude Codeを装わないAnthropic OAuthにしたfork。
    # nixpkgsはfollowsしない（ビルドにunstableとbun2nixが要るため上流の固定に任せる）。
    omp.url = "github:chibiham/oh-my-pi/d874579702a0a21e800312b520fe94a5d33c58da";

    # macOS Spotlight統合
    # mac-app-utilはSBCLでビルドされる。SBCL 2.5.10はmacOS 27でヒープ確保に失敗する
    # （failed to allocate ... at 0x300100000）。2.6.8では動くため、nixpkgs-unstableに追従させる。
    mac-app-util = {
      url = "github:hraban/mac-app-util";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      mac-app-util,
      omp,
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
      #
      # cudaCapabilities: Ubuntu機のGPUの世代だけを指定する。全CUDA世代をコンパイルせず、
      # llama.cppの初回構築時間とNix store使用量を抑える。
      #   chibihamuntu: RTX 3090 (Ampere) = 8.6（既定）
      #   dekahamuntu:  RTX 5060 Ti (Blackwell) = 12.0（CUDA 12.8以降が要る）
      unstableOverlay =
        {
          system,
          cudaCapabilities ? [ "8.6" ],
        }:
        final: prev:
        let
          unstable = import nixpkgs-unstable {
            inherit system;
            config = {
              allowUnfree = true;
              inherit cudaCapabilities;
            };
          };
        in
        {
          inherit (unstable) flyctl llama-cpp;
        };

      pkgsFor =
        {
          system,
          cudaCapabilities ? [ "8.6" ],
        }:
        import nixpkgs {
          inherit system;
          config = {
            # unfreeパッケージを許可（1password-cli等）
            allowUnfree = true;
          };
          overlays = [ (unstableOverlay { inherit system cudaCapabilities; }) ];
        };

      # macOSユーザー用のHome Manager設定を生成
      mkDarwinHome =
        {
          username,
          hostModule,
          system ? "aarch64-darwin",
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor { inherit system; };
          modules = [
            ./home/common.nix
            ./home/darwin.nix
            hostModule
            omp.homeManagerModules.default
            mac-app-util.homeManagerModules.default # Spotlight統合
            {
              home.username = username;
              home.homeDirectory = "/Users/${username}";
            }
          ];
        };

      # Ubuntu/Linuxユーザー用のHome Manager設定を生成
      # hostModule: ホストごとの差（home/hosts/<ホスト>.nix）。なければchibihamuntuと同じ
      mkLinuxHome =
        {
          username,
          system ? "x86_64-linux",
          hostModule ? null,
          cudaCapabilities ? [ "8.6" ],
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsFor { inherit system cudaCapabilities; };
          modules = [
            ./home/common.nix
            ./home/linux.nix
            omp.homeManagerModules.default
            {
              home.username = username;
              home.homeDirectory = "/home/${username}";
            }
          ]
          ++ nixpkgs.lib.optional (hostModule != null) hostModule;
        };
    in
    {
      # Home Manager設定
      homeConfigurations = {
        "chibiham@macbook" = mkDarwinHome {
          username = "chibiham";
          hostModule = ./home/hosts/macbook.nix;
        };
        "chibiham@mac-mini" = mkDarwinHome {
          username = "chibiham";
          hostModule = ./home/hosts/mac-mini.nix;
        };
        # chibihamuntu（RTX 3090・Intel）。名前は導入時のまま
        "chibiham@ubuntu-server" = mkLinuxHome { username = "chibiham"; };
        # dekahamuntu（RTX 5060 Ti 16GB ×2・AMD Ryzen）
        "chibiham@dekahamuntu" = mkLinuxHome {
          username = "chibiham";
          hostModule = ./home/hosts/dekahamuntu.nix;
          cudaCapabilities = [ "12.0" ];
        };
      };

      # flake.lockでピン留めされたhome-manager CLI
      # `nix run home-manager` (registry経由=master追従) ではなくこちらを使う:
      #   nix run .#home-manager -- switch --flake .#$USER@mac-mini
      apps = forAllSystems (system: {
        home-manager = {
          type = "app";
          program = "${home-manager.packages.${system}.home-manager}/bin/home-manager";
        };
      });

      # `nix fmt` 用フォーマッター
      formatter = forAllSystems (system: (pkgsFor { inherit system; }).nixfmt-rfc-style);
    };
}
