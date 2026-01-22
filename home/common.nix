# 共通設定（macOS / WSL 両方で使う）
{ pkgs, ... }:

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

    # Node.js (Clawdbot用)
    nodejs_22
    pnpm

    # シークレット管理
    _1password-cli  # op コマンド

    # その他
    htop
    tree
    curl
    wget
  ];

  # ===================
  # Git設定
  # ===================
  programs.git = {
    enable = true;

    # GPG署名
    signing = {
      key = "AF298761AC95B1C4827896A811135C38F21EA265";
      signByDefault = true;
    };

    # Git LFS
    lfs.enable = true;

    # 新しい設定形式 (settings)
    settings = {
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

      # タグも署名
      tag.gpgsign = true;

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
      # シークレット環境変数の読み込み
      [[ -f ~/.secrets/.env ]] && source ~/.secrets/.env

      # fzf キーバインド
      if command -v fzf &> /dev/null; then
        source <(fzf --zsh)
      fi

      # GPG TTY設定
      export GPG_TTY=$(tty)

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
  };

  # ===================
  # 環境変数
  # ===================
  home.sessionVariables = {
    EDITOR = "code --wait";
    LANG = "ja_JP.UTF-8";
  };

  # ===================
  # シークレット用ディレクトリ・テンプレート
  # ===================
  home.file.".secrets/.env.template".text = ''
    # シークレット環境変数（手動設定）
    # このファイルをコピーして .env を作成し、値を設定してください
    # cp ~/.secrets/.env.template ~/.secrets/.env
    #
    # 値は1Passwordからコピー（MyMachine Vault）

    export OPENAI_API_KEY=""
    export ANTHROPIC_API_KEY=""
    export AWS_ACCESS_KEY_ID=""
    export AWS_SECRET_ACCESS_KEY=""
    export CLOUDFLARE_API_TOKEN=""
    export GEMINI_API_KEY=""
    export CLAUDE_CODE_OAUTH_TOKEN=""
  '';

  # ===================
  # 追加のPATH
  # ===================
  home.sessionPath = [
    "$HOME/bin"
    "$HOME/go/bin"
  ];
}
