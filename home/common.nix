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
    jq              # JSON処理
    ripgrep         # 高速grep
    fd              # 高速find
    fzf             # ファジーファインダー
    eza             # モダンなls (旧exa)
    bat             # モダンなcat
    delta           # gitのdiff表示

    # バージョン管理
    mise  # Polyglot runtime version manager
    uv    # Fast Python package installer and resolver

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
      # SSH署名設定（1Password SSH Agent経由）
      user.signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB0sBTSjm9KmyYVGjT5FPImrH3izZtM/FegoEPE+bxw/";
      commit.gpgsign = true;
      tag.gpgsign = true;
      gpg.format = "ssh";
      "gpg \"ssh\"".program = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
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

      # SSH署名プログラムはcommon.nixで設定（1Password経由）
      # WSLの場合は wsl.nix でパスを上書きする

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
  # GPG設定
  # ===================
  programs.gpg = {
    enable = true;
    settings = {
      default-key = "8A5EBFD96EB7478A";
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
      # シークレット環境変数の読み込み（home-manager switch時に生成済み）
      [[ -f ~/.secrets/.env ]] && source ~/.secrets/.env
      [[ -f ~/.secrets/.env.secrets ]] && source ~/.secrets/.env.secrets

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
  # Claude Code ステータスライン
  # ===================
  home.file.".claude/statusline.sh" = {
    executable = true;
    text = ''
#!/bin/bash
input=$(cat)
MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
USED=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
IN=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
OUT=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')

if [ "$USED" -gt 80 ]; then COLOR="\033[91m"
elif [ "$USED" -gt 50 ]; then COLOR="\033[93m"
else COLOR="\033[92m"; fi
RESET="\033[0m"

echo -e "''${COLOR}[$MODEL] in:''${IN} out:''${OUT} | ctx:''${USED}% | \$''${COST}''${RESET}"
    '';
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
    # - SWITCHBOT_TOKEN (op://MyMachine/SWITCHBOT_TOKEN/credential)
    # - SWITCHBOT_SECRET (op://MyMachine/SWITCHBOT_SECRET/credential)
    #
    # 注意: 1Passwordの "MyMachine" Vault に上記のアイテムが存在する必要があります
  '';

  # ===================
  # SSH authorized_keys（1Password管理の共通鍵）
  # シンボリンクだとsshdのStrictModesで拒否されるため実ファイルとして配置
  # ===================
  home.activation.setupAuthorizedKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB0sBTSjm9KmyYVGjT5FPImrH3izZtM/FegoEPE+bxw/" > "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
  '';

  # ===================
  # 追加のPATH
  # ===================
  home.sessionPath = [
    "$HOME/.local/bin"  # claude-code等
    "$HOME/bin"
    "$HOME/bin/gamadv-xtd3"  # Google Workspace管理ツール
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
      if ! ${pkgs.gnupg}/bin/gpg --list-secret-keys 8A5EBFD96EB7478A &>/dev/null; then
        echo "Importing GPG key from 1Password..."
        op read "op://MyMachine/gpg-key-chibiham/private_key" 2>/dev/null | ${pkgs.gnupg}/bin/gpg --import 2>/dev/null || true

        # Trust the key (full fingerprint required)
        echo "A0447F00AE56DEC97196B41F8A5EBFD96EB7478A:6:" | ${pkgs.gnupg}/bin/gpg --import-ownertrust 2>/dev/null || true
      fi
    fi
  '';

  # 1Passwordからシークレットを展開してファイルに書き出し
  home.activation.generateSecrets = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -f "$HOME/.secrets/.env" ]; then
      source "$HOME/.secrets/.env"
    fi
    if command -v op &> /dev/null && [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ] && [ -f "$HOME/.secrets/env.tpl" ]; then
      echo "Generating secrets from 1Password..."
      ${pkgs._1password-cli}/bin/op inject -i "$HOME/.secrets/env.tpl" > "$HOME/.secrets/.env.secrets" 2>/dev/null \
        && chmod 600 "$HOME/.secrets/.env.secrets" \
        && echo "✓ Secrets written to ~/.secrets/.env.secrets" \
        || echo "⚠ Failed to generate secrets (1Password may not be authenticated)"
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

  # プライベートリポジトリのクローン（1Passwordから GITHUB_TOKEN を取得）
  home.activation.clonePrivateRepos = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    export PATH="${pkgs.git}/bin:${pkgs._1password-cli}/bin:$PATH"

    clone_repo() {
      local repo="$1"
      local dest="$2"
      if [ ! -d "$dest" ]; then
        echo "Cloning $repo to $dest..."
        GITHUB_TOKEN="op://MyMachine/GITHUB_PAT/credential" \
          ${pkgs._1password-cli}/bin/op run -- \
          ${pkgs.git}/bin/git clone "https://github.com/$repo.git" "$dest" 2>/dev/null || true
      fi
    }

    clone_repo "chibiham/chibiham-memos" "$HOME/memo"
    clone_repo "chibiham/clawd" "$HOME/clawd"
    clone_repo "chibiham/affairs" "$HOME/affairs"
    clone_repo "chibiham/skills" "$HOME/.agents/skills"
  '';

  # ~/.agents/skills の各スキルを ~/.claude/skills にシンボリンク
  home.activation.linkAgentSkills = lib.hm.dag.entryAfter [ "clonePrivateRepos" ] ''
    if [ -d "$HOME/.agents/skills" ]; then
      mkdir -p "$HOME/.claude/skills"
      for skill in "$HOME/.agents/skills"/*/; do
        name=$(basename "$skill")
        ln -sfn "$skill" "$HOME/.claude/skills/$name"
      done
      echo "✓ Agent skills linked to ~/.claude/skills"
    fi
  '';

  # Claude Code settings.json に statusLine 設定をマージ
  home.activation.setupClaudeStatusLine = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SETTINGS_FILE="$HOME/.claude/settings.json"
    if [ -f "$SETTINGS_FILE" ]; then
      # 既存の settings.json に statusLine をマージ
      ${pkgs.jq}/bin/jq '. + {"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}}' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
        && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    else
      mkdir -p "$HOME/.claude"
      echo '{"statusLine": {"type": "command", "command": "~/.claude/statusline.sh"}}' | ${pkgs.jq}/bin/jq . > "$SETTINGS_FILE"
    fi
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
