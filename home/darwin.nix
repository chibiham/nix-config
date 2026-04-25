# macOS固有の設定
{ pkgs, config, lib, ... }:

{
  # Karabiner-Elements設定
  # Note: Karabiner GUIで変更しても home-manager switch で上書きされる
  xdg.configFile."karabiner/karabiner.json" = {
    force = true;  # 既存ファイルを上書き
    text = builtins.toJSON {
    profiles = [
      {
        name = "Default profile";
        selected = true;
        complex_modifications = {
          rules = [
            {
              description = "Change right_command+hjkl to arrow keys";
              manipulators = [
                {
                  type = "basic";
                  from = {
                    key_code = "j";
                    modifiers = {
                      mandatory = [ "right_command" ];
                      optional = [ "any" ];
                    };
                  };
                  to = [{ key_code = "down_arrow"; }];
                }
                {
                  type = "basic";
                  from = {
                    key_code = "h";
                    modifiers = {
                      mandatory = [ "right_command" ];
                      optional = [ "any" ];
                    };
                  };
                  to = [{ key_code = "left_arrow"; }];
                }
                {
                  type = "basic";
                  from = {
                    key_code = "k";
                    modifiers = {
                      mandatory = [ "right_command" ];
                      optional = [ "any" ];
                    };
                  };
                  to = [{ key_code = "up_arrow"; }];
                }
                {
                  type = "basic";
                  from = {
                    key_code = "l";
                    modifiers = {
                      mandatory = [ "right_command" ];
                      optional = [ "any" ];
                    };
                  };
                  to = [{ key_code = "right_arrow"; }];
                }
              ];
            }
          ];
        };
        devices = [
          {
            identifiers = {
              is_keyboard = true;
              product_id = 638;
              vendor_id = 1452;
            };
            simple_modifications = [
              {
                from = { key_code = "caps_lock"; };
                to = [{ key_code = "left_control"; }];
              }
              {
                from = { key_code = "left_control"; };
                to = [{ key_code = "escape"; }];
              }
            ];
          }
          {
            identifiers = {
              is_keyboard = true;
              product_id = 37904;
              vendor_id = 1423;
            };
            simple_modifications = [
              {
                from = { key_code = "caps_lock"; };
                to = [{ key_code = "escape"; }];
              }
            ];
          }
        ];
        simple_modifications = [
          {
            from = { key_code = "caps_lock"; };
            to = [{ key_code = "escape"; }];
          }
          {
            from = { key_code = "international1"; };
            to = [{ key_code = "right_shift"; }];
          }
          {
            from = { key_code = "international3"; };
            to = [{ key_code = "grave_accent_and_tilde"; }];
          }
          {
            from = { key_code = "japanese_kana"; };
            to = [{ apple_vendor_top_case_key_code = "keyboard_fn"; }];
          }
        ];
        virtual_hid_keyboard = {
          country_code = 0;
          keyboard_type_v2 = "ansi";
        };
      }
    ];
  };
  };

  # macOS専用パッケージ
  home.packages = with pkgs; [
    coreutils  # GNU版コマンド（gls, gcat等）
  ];

  # macOS固有のSSH設定
  programs.ssh = {
    # OrbStack: LinuxマシンのSSH設定（全Hostブロックより前に読み込む必要がある）
    extraConfig = ''
      Include ~/.orbstack/ssh/config
    '';

    matchBlocks = {
      # GitHub: 秘密鍵はactivationで1Passwordから取得済みのファイルを使用
      "github.com" = {
        identityFile = "~/.ssh/id_ed25519";
        identityAgent = "none";  # 1Password agentをバイパス（鍵ファイルを直接使用）
      };

      # 全ホストに1Password SSHエージェントを適用（github.com はidentityAgent noneで除外）
      "*" = lib.hm.dag.entryAfter [ "github.com" ] {
        identityAgent = "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
      };
    };
  };

  # macOS固有の環境変数
  home.sessionVariables = {
    # Homebrew（自動更新を無効化）
    HOMEBREW_NO_AUTO_UPDATE = "1";
    # 1Password SSH Agent
    SSH_AUTH_SOCK = "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
  };

  # macOS固有のPATH
  # Note: Homebrewのパスは .zprofile の brew shellenv で設定
  home.sessionPath = [
    "$HOME/Library/pnpm"
  ];

  # macOS固有のZsh設定
  programs.zsh.initContent = ''
    # iTerm2 Shell Integration
    if [[ "$TERM_PROGRAM" == "iTerm.app" ]]; then
      iterm2_print_user_vars() {
        iterm2_set_user_var badge $(whoami)
      }
      function badge() {
        printf "\e]1337;SetBadgeFormat=%s\a" $(echo -n "$1" | base64)
      }
      test -e "$HOME/dotfiles/bin/.iterm2_shell_integration.zsh" && source "$HOME/dotfiles/bin/.iterm2_shell_integration.zsh"
    fi

    # Google Cloud SDK (if installed)
    if [[ -f "$HOME/Downloads/google-cloud-sdk/path.zsh.inc" ]]; then
      source "$HOME/Downloads/google-cloud-sdk/path.zsh.inc"
    fi
    if [[ -f "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc" ]]; then
      source "$HOME/Downloads/google-cloud-sdk/completion.zsh.inc"
    fi
  '';


  # SSH秘密鍵を1Passwordから取得（新マシンセットアップ用）
  # 前提: 1Password GUIで "SSH Key" タイプのアイテムを作成
  #   - Vault: MyMachine
  #   - Item名: ssh-key-ed25519
  #   - 秘密鍵: id_ed25519 の内容をペースト
  home.activation.setupSSHKeyFromOp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    if command -v op &> /dev/null && [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
      if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        echo "Fetching SSH private key from 1Password..."
        ${pkgs._1password-cli}/bin/op read "op://MyMachine/ssh-key-ed25519/private key" \
          > "$HOME/.ssh/id_ed25519" 2>/dev/null \
          && chmod 600 "$HOME/.ssh/id_ed25519" \
          && echo "✓ SSH秘密鍵を1Passwordから取得しました (~/.ssh/id_ed25519)" \
          || echo "⚠ SSH鍵の取得に失敗。1PasswordにVault:MyMachine / Item:ssh-key-ed25519 が存在するか確認してください"
      fi
    else
      echo "⚠ 1Passwordが未認証のためSSH鍵の取得をスキップ（OP_SERVICE_ACCOUNT_TOKEN が未設定）"
    fi
  '';

  # macOS システム設定の自動化
  home.activation.macosSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "macOS設定を適用中..."

    # キーボード設定
    /usr/bin/defaults write NSGlobalDomain KeyRepeat -int 1                          # リピート速度最速
    /usr/bin/defaults write NSGlobalDomain InitialKeyRepeat -int 10                  # 遅延最短
    /usr/bin/defaults write NSGlobalDomain com.apple.keyboard.fnState -bool true     # FnキーをF1-F12として使用
    /usr/bin/defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false      # 長押しアクセント無効

    # 音声入力
    /usr/bin/defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool true   # 音声入力を有効化

    # テキスト入力設定
    /usr/bin/defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false  # スマート引用符無効
    /usr/bin/defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false   # スマートダッシュ無効
    /usr/bin/defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool true  # タイプミス修正有効

    # 日本語IM設定（可能な範囲で）
    /usr/bin/defaults write com.apple.inputmethod.Kotoeri JIMPrefLiveConversionKey -bool false    # ライブ変換無効
    /usr/bin/defaults write com.apple.inputmethod.Kotoeri JIMPrefWindowsModeKey -bool false       # Windows風キー操作無効

    # マジックマウス設定（右側で右クリック）
    /usr/bin/defaults write com.apple.AppleMultitouchMouse MouseButtonMode TwoButton              # セカンダリクリック有効
    /usr/bin/defaults write com.apple.driver.AppleBluetoothMultitouch.mouse MouseButtonMode TwoButton  # Bluetooth経由の場合

    # Dock設定
    /usr/bin/defaults write com.apple.dock autohide -bool true                                     # 自動的に隠す
    /usr/bin/killall Dock 2>/dev/null || true                                                      # Dock再起動（設定反映）

    # Finder設定
    /usr/bin/defaults write com.apple.finder FXPreferredViewStyle -string "clmv"                   # デフォルトをカラム表示
    /usr/bin/defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true          # ネットワークドライブで.DS_Store無効
    /usr/bin/defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true              # USBドライブで.DS_Store無効
    /usr/bin/killall Finder 2>/dev/null || true                                                    # Finder再起動（設定反映）

    # 起動音を無効化（sudo必要）
    if /usr/bin/sudo -n /usr/sbin/nvram StartupMute=%01 2>/dev/null; then
      echo "✓ 起動音を無効化しました"
    else
      echo "⚠ 起動音の無効化をスキップ（sudoが必要）。手動で実行: sudo nvram StartupMute=%01"
    fi

    # リモートログイン（SSH）を有効化（sudo必要）
    if /usr/bin/sudo -n /usr/sbin/systemsetup -setremotelogin on 2>/dev/null; then
      echo "✓ リモートログイン（SSH）を有効化しました"
    else
      echo "⚠ リモートログインの有効化をスキップ（sudoが必要）。手動で実行: sudo systemsetup -setremotelogin on"
    fi

    # SSHパスワード認証を無効化（鍵認証のみ許可）
    SSHD_CONFIG="/etc/ssh/sshd_config"
    if /usr/bin/sudo -n /usr/bin/grep -q "^PasswordAuthentication" "$SSHD_CONFIG" 2>/dev/null; then
      /usr/bin/sudo -n /usr/bin/sed -i.bak 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG" 2>/dev/null
      /usr/bin/sudo -n /usr/bin/sed -i.bak 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$SSHD_CONFIG" 2>/dev/null
      /usr/bin/sudo -n /bin/rm -f "$SSHD_CONFIG.bak" 2>/dev/null
      /usr/bin/sudo -n launchctl stop com.openssh.sshd 2>/dev/null || true
      echo "✓ SSHパスワード認証を無効化しました（鍵認証のみ）"
    else
      echo "⚠ SSHパスワード認証の無効化をスキップ（sudoが必要）。手動で実行:"
      echo "  sudo sed -i.bak 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config"
    fi

    # スリープ設定（sudo必要）
    # AC電源接続時: スリープ無効、ディスプレイは30分でオフ
    if /usr/bin/sudo -n /usr/bin/pmset -c sleep 0 displaysleep 30 2>/dev/null; then
      echo "✓ スリープ設定を適用しました（スリープ無効、ディスプレイ30分）"
    else
      echo "⚠ スリープ設定をスキップ（sudoが必要）。手動で実行: sudo pmset -c sleep 0 displaysleep 30"
    fi

    # Ghostty terminfo配置（SSH接続元がGhosttyの場合に正常表示するため）
    GHOSTTY_TERMINFO="/Applications/Ghostty.app/Contents/Resources/terminfo/78/xterm-ghostty"
    if [[ -f "$GHOSTTY_TERMINFO" ]]; then
      /bin/mkdir -p "$HOME/.terminfo/78"
      /bin/cp "$GHOSTTY_TERMINFO" "$HOME/.terminfo/78/xterm-ghostty"
      echo "✓ Ghostty terminfoを配置しました"
    else
      echo "⚠ Ghostty.appが見つかりません。terminfoの配置をスキップ"
    fi

    echo "✓ macOS設定完了（一部設定は再ログインまたは再起動後に反映）"
  '';
}
