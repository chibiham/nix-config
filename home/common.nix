# 共通設定（macOS / WSL 両方で使う）
{ pkgs, lib, ... }:

{
  # Home Managerのバージョン（変更しないで）
  home.stateVersion = "24.05";

  # Home Manager自身を有効化
  programs.home-manager.enable = true;

  # ===================
  # パッケージ
  # ===================
  home.packages = with pkgs; [
    # 開発ツール
    git
    gh              # GitHub CLI
    claude-code     # Claude Code CLI
    jq              # JSON処理
    ripgrep         # 高速grep
    fd              # 高速find
    fzf             # ファジーファインダー
    eza             # モダンなls (旧exa)
    bat             # モダンなcat
    delta           # gitのdiff表示

    # バージョン管理
    mise  # Polyglot runtime version manager

    # Node.js (miseで管理、一時的にコメントアウト)
    # nodejs_22  # miseで管理
    # pnpm       # miseで管理

    # シークレット管理
    _1password-cli  # op コマンド

    # インフラ・クラウドツール
    awscli          # AWS CLI
    terraform       # Infrastructure as Code
    flyctl          # Fly.io CLI
    cloudflared     # Cloudflare Tunnel

    # ビルドツール
    cmake           # クロスプラットフォームビルドシステム

    # AI CLI
    gemini-cli      # Google Gemini CLI

    # アーカイブ
    unrar           # RAR解凍

    # セキュリティ
    gnupg           # GPG（暗号化・署名）
    pinentry_mac    # GPG PIN入力（macOS）

    # その他
    htop
    tree
    curl
    wget

    # LSPサーバー
    nodePackages.typescript-language-server  # TypeScript/JavaScript
    nil                                       # Nix
    lua-language-server                      # Lua
    pyright                                   # Python
    gopls                                     # Go
    rust-analyzer                            # Rust
    nodePackages.vscode-langservers-extracted # JSON/HTML/CSS/ESLint
    yaml-language-server                     # YAML
    marksman                                  # Markdown

    # フォーマッター
    stylua                  # Lua
    nodePackages.prettier   # JS/TS/JSON/YAML
    black                   # Python
    gofumpt                 # Go
    rustfmt                 # Rust

    # 追加ツール
    tree-sitter             # パーサー（Treesitter用）
    gcc                     # Treesitterコンパイル用

    # フォント（WezTerm用）
    pkgs.nerd-fonts.jetbrains-mono
  ];

  # ===================
  # Git設定
  # ===================
  programs.git = {
    enable = true;

    # Git LFS
    lfs.enable = true;

    # 設定 (25.11ではsettingsを使用)
    settings = {
      # GPG署名設定
      user.signingkey = "973655571CACBD16FB1DD4E1455F463BA021E7D9";
      commit.gpgsign = true;
      tag.gpgsign = true;
      user = {
        name = "chibiham";
        email = "ryuto.chiba@chibiham.com";
      };

      alias = {
        co = "checkout";
      };

      init.defaultBranch = "main";
      pull.rebase = true;

      # VS Code をエディタ/diff/mergeツールに
      core.editor = "code --wait";
      diff.tool = "vscode";
      difftool.vscode.cmd = "code --wait --diff $LOCAL $REMOTE";
      merge.tool = "vscode";
      mergetool.vscode.cmd = "code --wait $MERGED";

      # GPGプログラムはプラットフォーム固有ファイルで設定
      # darwin.nix: /opt/homebrew/bin/gpg
      # wsl.nix: Nixで管理されるgpg

      # delta (diff表示) - 任意で有効化
      # core.pager = "delta";
      # interactive.diffFilter = "delta --color-only";
      # delta = {
      #   navigate = true;
      #   light = false;
      #   line-numbers = true;
      # };
    };
  };

  # ===================
  # Zsh設定
  # ===================
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    enableCompletion = true;
    syntaxHighlighting.enable = true;

    # ヒストリ設定
    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreAllDups = true;
      share = true;
    };

    # エイリアス
    shellAliases = {
      # Docker
      dcom = "docker compose";

      # モダンコマンド置き換え
      ls = "eza";
      ll = "eza -l";
      la = "eza -la";
      cat = "bat";

      # Git
      g = "git";
      gs = "git status";
      gd = "git diff";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git pull";
    };

    # 追加の初期化スクリプト（.zshrc の末尾に追加される）
    initContent = ''
      # シークレット環境変数の読み込み（OP_SERVICE_ACCOUNT_TOKEN用）
      [[ -f ~/.secrets/.env ]] && source ~/.secrets/.env

      # 1Password からシークレットを自動展開
      if command -v op &> /dev/null && [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
        export OPENAI_API_KEY=$(op read "op://MyMachine/OPEN_AI_API_KEY/credential" 2>/dev/null || echo "")
        export AWS_ACCESS_KEY_ID=$(op read "op://MyMachine/AWS_CREDENTIALS/username" 2>/dev/null || echo "")
        export AWS_SECRET_ACCESS_KEY=$(op read "op://MyMachine/AWS_CREDENTIALS/password" 2>/dev/null || echo "")
        export CLOUDFLARE_API_TOKEN=$(op read "op://MyMachine/CLOUDFLARE_API_TOKEN/credential" 2>/dev/null || echo "")
        export GEMINI_API_KEY=$(op read "op://MyMachine/GEMINI_API_KEY/credential" 2>/dev/null || echo "")
        export CLAUDE_CODE_OAUTH_TOKEN=$(op read "op://MyMachine/CLAUDE_CODE_AUTH_TOKEN/credential" 2>/dev/null || echo "")
        export ANTHROPIC_API_KEY=$(op read "op://MyMachine/ANTHROPIC_API_KEY/credential" 2>/dev/null || echo "")
        export BRAVE_API_KEY=$(op read "op://MyMachine/BRAVE_API_KEY/credential" 2>/dev/null || echo "")
      fi

      # fzf キーバインド
      if command -v fzf &> /dev/null; then
        source <(fzf --zsh)
      fi

      # GPG TTY設定
      export GPG_TTY=$(tty)

      # mise（runtime version manager）
      if command -v mise &> /dev/null; then
        eval "$(mise activate zsh)"
      fi

      # カスタム関数: fzfでSSH接続
      function sshf () {
        local selected_host=$(grep "Host " ./ssh_config | grep -v '*' | cut -b 6- | fzf)
        if [ -n "$selected_host" ]; then
          echo "ssh -F ./ssh_config ''${selected_host}"
          ssh -F ./ssh_config $selected_host
        fi
      }
    '';
  };

  # ===================
  # Starship（プロンプト）
  # ===================
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      # プロンプトのフォーマット
      format = "$directory$git_branch$git_status$nodejs$python$rust$golang$nix_shell$cmd_duration$line_break$character";

      character = {
        success_symbol = "[❯](bold green)";
        error_symbol = "[❯](bold red)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };

      git_branch = {
        symbol = " ";
        format = "[$symbol$branch]($style) ";
      };

      git_status = {
        format = "[$all_status$ahead_behind]($style) ";
      };

      nodejs = {
        symbol = " ";
        format = "[$symbol($version )]($style)";
      };

      nix_shell = {
        symbol = " ";
        format = "[$symbol$state]($style) ";
      };

      cmd_duration = {
        min_time = 2000;
        format = "[$duration]($style) ";
      };
    };
  };

  # ===================
  # fzf（ファジーファインダー）
  # ===================
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [
      "--height 40%"
      "--layout=reverse"
      "--border"
    ];
  };

  # ===================
  # direnv
  # ===================
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;  # nix-direnv統合（高速化）

    # mise統合
    stdlib = ''
      if command -v mise &> /dev/null; then
        eval "$(mise direnv activate)"
      fi
    '';
  };

  # ===================
  # フォント設定
  # ===================
  fonts.fontconfig.enable = true;

  # ===================
  # NeoVim
  # ===================
  programs.neovim = {
    enable = true;
    defaultEditor = true;  # EDITORをnvimに設定
    viAlias = true;        # vi -> nvim
    vimAlias = true;       # vim -> nvim
    vimdiffAlias = true;   # vimdiff -> nvim -d

    package = pkgs.neovim-unwrapped;

    extraPackages = with pkgs; [
      git
      # nodejs_22 は mise で管理
    ];
  };

  # NeoVim設定ファイル（ディレクトリ全体をリンク）
  xdg.configFile."nvim" = {
    source = ./nvim;
    recursive = true;
  };

  # mise global configuration
  xdg.configFile."mise/config.toml".text = ''
    [settings]
    auto_install = true
    legacy_version_file = true  # .node-version等を自動検出
    experimental = true

    [tools]
    # グローバルデフォルト（activation hookで自動インストール）
    node = "22"
    python = "3.12"
    pnpm = "latest"
  '';

  # ===================
  # WezTerm
  # ===================
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;

    extraConfig = ''
      local config = wezterm.config_builder()

      -- ========== シェル設定 ==========
      config.default_prog = { '/bin/zsh', '-l' }  -- ログインシェルとして起動

      -- ========== 外観 ==========
      config.color_scheme = 'Catppuccin Mocha'
      config.font = wezterm.font('JetBrainsMono Nerd Font', { weight = 'Regular' })
      config.font_size = 13

      -- ウィンドウ
      config.window_close_confirmation = 'NeverPrompt'
      config.window_decorations = 'RESIZE'
      config.window_background_opacity = 0.95
      config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }

      -- タブバー
      config.use_fancy_tab_bar = false
      config.hide_tab_bar_if_only_one_tab = true
      config.tab_bar_at_bottom = true

      -- カーソル
      config.default_cursor_style = 'BlinkingBar'
      config.cursor_blink_rate = 500

      -- ========== プラットフォーム検出 ==========
      local is_darwin = wezterm.target_triple:find("darwin") ~= nil
      local is_linux = wezterm.target_triple:find("linux") ~= nil

      if is_darwin then
        -- macOS固有
        config.macos_window_background_blur = 20
        config.native_macos_fullscreen_mode = false
      end

      if is_linux then
        -- WSL固有
        config.default_domain = 'WSL:Ubuntu'
        config.wsl_domains = {
          {
            name = 'WSL:Ubuntu',
            distribution = 'Ubuntu',
          },
        }
      end

      -- ========== キーバインド ==========
      local act = wezterm.action
      config.keys = {
        -- 分割
        { key = 'd', mods = 'CMD|SHIFT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
        { key = 'd', mods = 'CMD', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },

        -- ペイン移動
        { key = 'LeftArrow', mods = 'CMD|SHIFT', action = act.ActivatePaneDirection('Left') },
        { key = 'RightArrow', mods = 'CMD|SHIFT', action = act.ActivatePaneDirection('Right') },
        { key = 'UpArrow', mods = 'CMD|SHIFT', action = act.ActivatePaneDirection('Up') },
        { key = 'DownArrow', mods = 'CMD|SHIFT', action = act.ActivatePaneDirection('Down') },

        -- ペイン閉じる
        { key = 'w', mods = 'CMD', action = act.CloseCurrentPane { confirm = false } },
      }

      return config
    '';
  };

  # ===================
  # 環境変数
  # ===================
  home.sessionVariables = {
    # EDITOR = "code --wait";  # NeoVimのdefaultEditor = trueで自動設定される
    LANG = "ja_JP.UTF-8";

    # 基本設定（.zprofileから移行）
    BROWSER = "open";  # macOS
    PAGER = "less";
    LESS = "-g -i -M -R -S -w -X -z-4";

    # Homebrew設定
    HOMEBREW_BREWFILE = "$HOME/.config/nix-config/Brewfile";

    # pnpm グローバルストア設定
    PNPM_HOME = "$HOME/.local/share/pnpm";

    # mise設定
    MISE_DATA_DIR = "$HOME/.local/share/mise";
    MISE_CONFIG_DIR = "$HOME/.config/mise";
    MISE_CACHE_DIR = "$HOME/.cache/mise";
    MISE_AUTO_INSTALL = "1";  # バージョンファイル検出時に自動インストール
    MISE_TRUSTED_CONFIG_PATHS = "$HOME";  # ホームディレクトリ配下を信頼
  };

  # ===================
  # シークレット用ディレクトリ・テンプレート
  # ===================
  home.file.".secrets/.env.template".text = ''
    # シークレット環境変数設定
    # このファイルをコピーして .env を作成してください
    # cp ~/.secrets/.env.template ~/.secrets/.env
    #
    # 1Password Service Account Token を設定すると、
    # 他のシークレットは自動的に1Passwordから取得されます

    # 必須: 1Password Service Account Token
    # https://my.1password.com/developer/serviceaccounts から取得
    export OP_SERVICE_ACCOUNT_TOKEN=""

    # 以下のシークレットは自動的に1Passwordから取得されます:
    # - OPENAI_API_KEY (op://MyMachine/OPEN_AI_API_KEY/credential)
    # - AWS_ACCESS_KEY_ID (op://MyMachine/AWS_CREDENTIALS/username)
    # - AWS_SECRET_ACCESS_KEY (op://MyMachine/AWS_CREDENTIALS/password)
    # - CLOUDFLARE_API_TOKEN (op://MyMachine/CLOUDFLARE_API_TOKEN/credential)
    # - GEMINI_API_KEY (op://MyMachine/GEMINI_API_KEY/credential)
    # - CLAUDE_CODE_OAUTH_TOKEN (op://MyMachine/CLAUDE_CODE_AUTH_TOKEN/credential)
    # - ANTHROPIC_API_KEY (op://MyMachine/ANTHROPIC_API_KEY/credential)
    # - BRAVE_API_KEY (op://MyMachine/BRAVE_API_KEY/credential)
    #
    # 注意: 1Passwordの "MyMachine" Vault に上記のアイテムが存在する必要があります
  '';

  # ===================
  # 追加のPATH
  # ===================
  home.sessionPath = [
    "$HOME/bin"
    "$HOME/go/bin"
    "$HOME/.local/share/pnpm"  # pnpm グローバルbin
    "$HOME/.local/share/mise/shims"  # mise shims
  ];

  # ===================
  # アクティベーション（home-manager switch時に実行）
  # ===================

  # GPG鍵の自動インポート（1Passwordから）
  home.activation.setupGPG = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # 1PasswordからGPG鍵をインポート（まだインポートされていない場合）
    if command -v op &> /dev/null && [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
      if ! ${pkgs.gnupg}/bin/gpg --list-secret-keys 973655571CACBD16FB1DD4E1455F463BA021E7D9 &>/dev/null; then
        echo "Importing GPG key from 1Password..."
        op read "op://MyMachine/gpg-key-chibiham/private key" 2>/dev/null | ${pkgs.gnupg}/bin/gpg --import 2>/dev/null || true

        # Trust the key
        echo "973655571CACBD16FB1DD4E1455F463BA021E7D9:6:" | ${pkgs.gnupg}/bin/gpg --import-ownertrust 2>/dev/null || true
      fi
    fi
  '';

  # mise共通ランタイムインストール
  home.activation.installMiseRuntimes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${pkgs.mise}/bin:$PATH"

    # グローバルバージョンをインストール（未インストールの場合のみ）
    ${pkgs.mise}/bin/mise use --global node@22 2>/dev/null || true
    ${pkgs.mise}/bin/mise use --global python@3.12 2>/dev/null || true
    ${pkgs.mise}/bin/mise use --global pnpm@latest 2>/dev/null || true
  '';

  # pnpmグローバルパッケージインストール（mise管理のpnpmを使用）
  home.activation.installGlobalPnpmPackages = lib.hm.dag.entryAfter [ "installMiseRuntimes" ] ''
    export PNPM_HOME="$HOME/.local/share/pnpm"
    export PATH="${pkgs.git}/bin:$HOME/.local/share/mise/shims:$PNPM_HOME:$PATH"
    mkdir -p "$PNPM_HOME"

    # mise経由でpnpmが利用可能になるまで待つ
    if command -v pnpm &> /dev/null; then
      # clawdbot をグローバルインストール（未インストールの場合のみ）
      if [ ! -f "$PNPM_HOME/clawdbot" ]; then
        pnpm add -g clawdbot@latest 2>/dev/null || true
      fi
    fi
  '';
}
