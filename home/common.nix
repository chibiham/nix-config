# 共通設定
#
# 方針:
# - このファイル（と OS別モジュール）の適用 = `home-manager switch` は
#   ネットワーク・1Password認証・sudo に依存せず、常に冪等であること
# - 命令的な初期構築は scripts/ のOS別bootstrapに分離
{ pkgs, lib, ... }:

let
  # 1Password管理の共通マシン鍵（公開鍵）
  # 認証・Git署名・authorized_keys すべてこの鍵に一本化
  machinePubKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB0sBTSjm9KmyYVGjT5FPImrH3izZtM/FegoEPE+bxw/";
  gitEmail = "ryuto.chiba@chibiham.com";

  # シークレット再生成コマンド（activationではなく明示実行）
  update-secrets = pkgs.writeShellScriptBin "update-secrets" ''
    set -euo pipefail
    if [ -z "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ] && [ -f "$HOME/.secrets/.env" ]; then
      source "$HOME/.secrets/.env"
    fi
    if [ -z "''${OP_SERVICE_ACCOUNT_TOKEN:-}" ]; then
      echo "⚠ OP_SERVICE_ACCOUNT_TOKEN が未設定です（~/.secrets/.env に設定してください）" >&2
      exit 1
    fi
    ${pkgs._1password-cli}/bin/op inject -i "$HOME/.secrets/env.tpl" > "$HOME/.secrets/.env.secrets.tmp"
    mv "$HOME/.secrets/.env.secrets.tmp" "$HOME/.secrets/.env.secrets"
    chmod 600 "$HOME/.secrets/.env.secrets"
    echo "✓ ~/.secrets/.env.secrets を更新しました（新しいシェルで反映）"
  '';
in
{
  # Home Managerのバージョン（変更しないで）
  home.stateVersion = "24.05";

  # Home Manager自身を有効化
  programs.home-manager.enable = true;

  # ===================
  # Nixガベージコレクション（launchdで週次実行）
  # 古い世代のstore pathを自動削除してディスクを節約
  # ===================
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # ===================
  # パッケージ
  # ===================
  home.packages = with pkgs; [
    # 開発ツール
    git
    gh # GitHub CLI
    jq # JSON処理
    ripgrep # 高速grep
    fd # 高速find
    fzf # ファジーファインダー
    eza # モダンなls (旧exa)
    bat # モダンなcat
    # delta は programs.delta で管理

    # バージョン管理
    mise # Polyglot runtime version manager
    uv # Fast Python package installer and resolver

    # シークレット管理
    _1password-cli # op コマンド
    update-secrets # ~/.secrets/.env.secrets を1Passwordから再生成

    # インフラ・クラウドツール
    awscli # AWS CLI
    terraform # Infrastructure as Code
    flyctl # Fly.io CLI
    cloudflared # Cloudflare Tunnel

    # ビルドツール
    cmake # クロスプラットフォームビルドシステム

    # アーカイブ
    unrar # RAR解凍

    # セキュリティ
    gnupg # GPG（暗号化用途。Git署名はSSH形式に移行済み）

    # その他
    htop
    tree
    curl
    wget

    # LSPサーバー
    nodePackages.typescript-language-server # TypeScript/JavaScript
    nil # Nix
    lua-language-server # Lua
    pyright # Python
    gopls # Go
    rust-analyzer # Rust
    nodePackages.vscode-langservers-extracted # JSON/HTML/CSS/ESLint
    yaml-language-server # YAML
    marksman # Markdown

    # フォーマッター
    stylua # Lua
    nodePackages.prettier # JS/TS/JSON/YAML
    black # Python
    gofumpt # Go
    rustfmt # Rust

    # 追加ツール
    tree-sitter # パーサー（Treesitter用）
    gcc # Treesitterコンパイル用

    # フォント（ターミナル用）
    pkgs.nerd-fonts.jetbrains-mono
  ];

  # ===================
  # Git設定
  # 認証: SSH（~/.ssh/id_ed25519、1Passwordからbootstrapで取得）
  # 署名: 同じ鍵でSSH署名（commit/tagとも常時署名）
  # ===================
  programs.git = {
    enable = true;

    # Git LFS
    lfs.enable = true;

    # 設定 (25.11ではsettingsを使用)
    settings = {
      user = {
        name = "chibiham";
        email = gitEmail;
        # 鍵ファイルパスを指定（インラインの公開鍵だとGPGにフォールバックしてcommitがブロックされる）
        signingkey = "~/.ssh/id_ed25519";
      };
      commit.gpgsign = true;
      tag.gpgsign = true;
      gpg.format = "ssh";
      # 自分のコミットの署名検証用（git log --show-signature）
      gpg.ssh.allowedSignersFile = "~/.config/git/allowed_signers";

      alias = {
        co = "checkout";
      };

      init.defaultBranch = "main";
      pull.rebase = true;

      core.editor = "nvim";
    };
  };

  # delta（gitのdiff表示。25.11からgit外のトップレベルオプション）
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true; # n/N でファイル間移動
      line-numbers = true;
    };
  };

  # SSH署名の検証用 allowed_signers
  home.file.".config/git/allowed_signers".text = ''
    ${gitEmail} ${machinePubKey}
  '';

  # ===================
  # SSH設定
  # github.com: 1Passwordから取得した鍵ファイルで認証（agentはバイパス）
  #   → Git認証と署名が常に同じ鍵・同じ経路になり、端末間で挙動が揃う
  # その他ホスト: darwin.nix の Host * で1Password SSH agentを適用
  # ===================
  # 既存の ~/.ssh/config を強制上書き（checkLinkTargets対策）
  home.file.".ssh/config".force = true;

  programs.ssh = {
    enable = true;
    # デフォルト値は matchBlocks."*"（darwin.nix）で明示管理
    enableDefaultConfig = false;
    matchBlocks = {
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "~/.ssh/id_ed25519";
        identitiesOnly = true;
        # 1Password agentをバイパスして鍵ファイルを直接使用
        identityAgent = "none";
        extraOptions = {
          # 初回接続（bootstrapのclone等）でホスト鍵確認に止められない
          StrictHostKeyChecking = "accept-new";
        };
      };
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

      # tmux
      ta = "tmux attach -t"; # セッションにアタッチ
      tl = "tmux list-sessions"; # セッション一覧
      tn = "tmux new -s"; # 新規セッション作成

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
      # シークレット環境変数の読み込み（update-secretsで生成）
      [[ -f ~/.secrets/.env ]] && source ~/.secrets/.env
      [[ -f ~/.secrets/.env.secrets ]] && source ~/.secrets/.env.secrets

      # BRAVE_API_KEY → BRAVE_SEARCH_API_KEY エイリアス（移行期暫定）
      [[ -n "$BRAVE_API_KEY" ]] && export BRAVE_SEARCH_API_KEY="$BRAVE_API_KEY"

      # GPG TTY設定
      export GPG_TTY=$(tty)

      # SSH先でterminfoが見つからない場合のフォールバック
      if [[ -n "$SSH_CONNECTION" ]] && ! infocmp "$TERM" &>/dev/null 2>&1; then
        export TERM=xterm-256color
      fi

      # mise（runtime version manager）
      if command -v mise &> /dev/null; then
        eval "$(mise activate zsh)"
      fi
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
    nix-direnv.enable = true; # nix-direnv統合（高速化）

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
  # tmux
  # ===================
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color"; # 256色対応
    mouse = true; # マウス操作（スクロール、ペイン選択、リサイズ）
    baseIndex = 1; # ウィンドウ番号を1から開始（0は押しにくい）
    escapeTime = 0; # Escキーの遅延をなくす（Vim用）
    historyLimit = 10000; # スクロールバック行数

    # プレフィックスキーを Ctrl+a に変更（Ctrl+bより押しやすい）
    prefix = "C-a";

    extraConfig = ''
      # --- ペイン分割（直感的なキー） ---
      # | で縦分割、- で横分割（現在のディレクトリを引き継ぐ）
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # --- ペイン移動（Vim風: hjkl） ---
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R

      # --- ペインリサイズ（Shift + 矢印キー） ---
      bind -r S-Left  resize-pane -L 5
      bind -r S-Right resize-pane -R 5
      bind -r S-Down  resize-pane -D 5
      bind -r S-Up    resize-pane -U 5

      # --- 新しいウィンドウは現在のディレクトリで開く ---
      bind c new-window -c "#{pane_current_path}"

      # --- 設定リロード ---
      bind r source-file ~/.tmux.conf \; display "Config reloaded!"

      # --- ステータスバー ---
      set -g status-position top
      set -g status-style "bg=default,fg=white"
      set -g status-left "#[fg=cyan,bold] #S "
      set -g status-right "#[fg=white]%m/%d %H:%M "
      set -g status-left-length 20
      set -g window-status-current-format "#[fg=cyan,bold] #I:#W "
      set -g window-status-format " #I:#W "

      # --- ペインの境界線 ---
      set -g pane-border-style "fg=brightblack"
      set -g pane-active-border-style "fg=cyan"

      # --- コピーモード（Vim風） ---
      setw -g mode-keys vi
      bind -T copy-mode-vi v send -X begin-selection
      bind -T copy-mode-vi y send -X copy-selection-and-cancel

      # --- ウィンドウ番号の自動振り直し ---
      set -g renumber-windows on

      # --- フォーカスイベント（Vim/NeoVim連携用） ---
      set -g focus-events on
    '';
  };

  # ===================
  # NeoVim
  # ===================
  programs.neovim = {
    enable = true;
    defaultEditor = true; # EDITORをnvimに設定
    viAlias = true; # vi -> nvim
    vimAlias = true; # vim -> nvim
    vimdiffAlias = true; # vimdiff -> nvim -d

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
  # auto_install = true なので、bootstrap後は各ツールが必要時に自動インストールされる
  xdg.configFile."mise/config.toml".text = ''
    [settings]
    auto_install = true
    # .node-version等の言語固有バージョンファイルを検出（旧legacy_version_file）
    idiomatic_version_file_enable_tools = ["node"]
    experimental = true

    [tools]
    # グローバルデフォルト（bootstrapの mise install で導入）
    # pnpmはmise/Aquaのasset解決に依存させず、bootstrapでnpmから導入する。
    node = "24"
    python = "3.12"
  '';

  # Codexからtailnet内のOpenAI Responses互換llama.cppサーバーを利用する。
  # 通常のOpenAIプロバイダーは変更せず、`codex -p qwen-local`で明示的に選ぶ。
  home.file.".codex/qwen-local.config.toml".text = ''
    model = "Qwen3.8-27B-UD-Q4_K_M"
    model_provider = "qwen-local"
    model_context_window = 131072
    analytics.enabled = false
    feedback.enabled = false

    [tui]
    status_line = ["model-name", "context-remaining", "context-window-size", "used-tokens", "current-dir"]

    [otel]
    exporter = "none"
    metrics_exporter = "none"
    trace_exporter = "none"
    log_user_prompt = false

    [model_providers.qwen-local]
    name = "Qwen local (Ubuntu)"
    base_url = "https://chibihamuntu.tailded45d.ts.net:8443/v1"
    wire_api = "responses"
    requires_openai_auth = false
  '';

  home.file.".codex/qwen-local-uncensored.config.toml".text = ''
    model = "Qwen3.8-27B-Uncensored-Q4_K_M"
    model_provider = "qwen-local"
    model_context_window = 131072
    analytics.enabled = false
    feedback.enabled = false

    [tui]
    status_line = ["model-name", "context-remaining", "context-window-size", "used-tokens", "current-dir"]

    [otel]
    exporter = "none"
    metrics_exporter = "none"
    trace_exporter = "none"
    log_user_prompt = false

    [model_providers.qwen-local]
    name = "Qwen local (Ubuntu)"
    base_url = "https://chibihamuntu.tailded45d.ts.net:8443/v1"
    wire_api = "responses"
    requires_openai_auth = false
  '';

  # ===================
  # 環境変数
  # ===================
  home.sessionVariables = {
    # EDITOR = "code --wait";  # NeoVimのdefaultEditor = trueで自動設定される
    LANG = "ja_JP.UTF-8";

    # 基本設定（.zprofileから移行）
    PAGER = "less";
    LESS = "-g -i -M -R -S -w -X -z-4";

    # pnpm グローバルストア設定
    PNPM_HOME = "$HOME/.local/share/pnpm";

    # mise設定
    MISE_DATA_DIR = "$HOME/.local/share/mise";
    MISE_CONFIG_DIR = "$HOME/.config/mise";
    MISE_CACHE_DIR = "$HOME/.cache/mise";
    MISE_AUTO_INSTALL = "1"; # バージョンファイル検出時に自動インストール
    MISE_TRUSTED_CONFIG_PATHS = "$HOME"; # ホームディレクトリ配下を信頼
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
    # （scripts/bootstrap.sh を使えば対話的に作成されます）

    # 必須: 1Password Service Account Token
    # https://my.1password.com/developer/serviceaccounts から取得
    # export OP_SERVICE_ACCOUNT_TOKEN="..."

    # 他のシークレットは `update-secrets` コマンドで
    # ~/.secrets/.env.secrets に展開されます（env.tpl参照）
    # 注意: 1Passwordの "MyMachine" Vault に該当アイテムが存在する必要があります
  '';

  # op inject用テンプレート（update-secretsコマンドで展開）
  home.file.".secrets/env.tpl" = {
    force = true;
    text = ''
      export OPENAI_API_KEY="op://MyMachine/OPEN_AI_API_KEY/credential"
      export AWS_ACCESS_KEY_ID="op://MyMachine/AWS_CREDENTIALS/access_key_id"
      export AWS_SECRET_ACCESS_KEY="op://MyMachine/AWS_CREDENTIALS/secret_access_key"
      export CLOUDFLARE_API_TOKEN="op://MyMachine/CLOUDFLARE_API_TOKEN/credential"
      export GEMINI_API_KEY="op://MyMachine/GEMINI_API_KEY/credential"
      export CLAUDE_CODE_OAUTH_TOKEN="op://MyMachine/CLAUDE_CODE_AUTH_TOKEN/credential"
      export BRAVE_SEARCH_API_KEY="op://MyMachine/BRAVE_API_KEY/credential"
      export SWITCHBOT_TOKEN="op://MyMachine/SWITCHBOT_TOKEN/credential"
      export SWITCHBOT_SECRET="op://MyMachine/SWITCHBOT_SECRET/credential"
      export XAI_API_KEY="op://MyMachine/XAI_API_KEY/credential"
      export GITHUB_TOKEN="op://MyMachine/GITHUB_TOKEN/credential"
    '';
  };

  # ===================
  # 追加のPATH
  # ===================
  home.sessionPath = [
    "$HOME/.local/bin" # claude-code等
    "$HOME/bin"
    "$HOME/bin/gamadv-xtd3" # Google Workspace管理ツール
    "$HOME/go/bin"
    "$HOME/.local/share/pnpm" # pnpm グローバルbin
    "$HOME/.local/share/mise/shims" # mise shims
  ];

  # ===================
  # アクティベーション（home-manager switch時に実行）
  # ここに置くのは「ローカル完結・冪等・認証不要」なものだけ。
  # ネットワークや1Password認証が必要な処理は scripts/bootstrap.sh へ。
  # ===================

  # SSH authorized_keys（1Password管理の共通鍵）
  # シンボリックリンクだとsshdのStrictModesで拒否されるため実ファイルに追記管理
  home.activation.setupAuthorizedKeys = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    touch "$HOME/.ssh/authorized_keys"
    if ! grep -qxF "${machinePubKey}" "$HOME/.ssh/authorized_keys"; then
      echo "${machinePubKey}" >> "$HOME/.ssh/authorized_keys"
    fi
    chmod 600 "$HOME/.ssh/authorized_keys"
    if [ -f "$HOME/.ssh/id_ed25519" ]; then
      chmod 600 "$HOME/.ssh/id_ed25519"
    fi
  '';

  # ~/.agents/skills の各スキルを ~/.claude/skills にシンボリックリンク
  # （~/.agents/skills 自体のcloneは bootstrap.sh が行う）
  home.activation.linkAgentSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "$HOME/.agents/skills" ]; then
      mkdir -p "$HOME/.claude/skills"
      for skill in "$HOME/.agents/skills"/*/; do
        name=$(basename "$skill")
        ln -sfn "$skill" "$HOME/.claude/skills/$name"
      done
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

  # Qwen Codeからtailnet内のOpenAI互換llama.cppサーバーを利用する。
  # settings.jsonはQwen Code自身も更新するため、Nix Storeへのリンクではなく
  # activationで対象項目だけを冪等にマージする。
  home.activation.setupQwenCodeLocalModels = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    SETTINGS_DIR="$HOME/.qwen"
    SETTINGS_FILE="$SETTINGS_DIR/settings.json"
    BASE_URL="https://chibihamuntu.tailded45d.ts.net:8443/v1"
    mkdir -p "$SETTINGS_DIR"

    if [ ! -f "$SETTINGS_FILE" ]; then
      echo '{}' > "$SETTINGS_FILE"
    fi

    ${pkgs.jq}/bin/jq --arg baseUrl "$BASE_URL" '
      .modelProviders.openai = (
        ((.modelProviders.openai // []) | map(select(.baseUrl != $baseUrl)))
        + [
          {
            "id": "Qwen3.8-27B-UD-Q4_K_M",
            "name": "Qwen3.8 27B (Ubuntu)",
            "description": "Local Qwen3.8 via Tailscale",
            "envKey": "LOCAL_QWEN_API_KEY",
            "baseUrl": $baseUrl,
            "generationConfig": {
              "timeout": 300000,
              "maxRetries": 1,
              "contextWindowSize": 131072
            }
          },
          {
            "id": "Qwen3.8-27B-Uncensored-Q4_K_M",
            "name": "Qwen3.8 27B Uncensored (Ubuntu)",
            "description": "Local uncensored Qwen3.8 via Tailscale",
            "envKey": "LOCAL_QWEN_API_KEY",
            "baseUrl": $baseUrl,
            "generationConfig": {
              "timeout": 300000,
              "maxRetries": 1,
              "contextWindowSize": 131072
            }
          }
        ]
      )
      | .env.LOCAL_QWEN_API_KEY = "not-needed"
      | .security.auth.selectedType = "openai"
      | .model.name = "Qwen3.8-27B-UD-Q4_K_M"
    ' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" \
      && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
  '';
}
