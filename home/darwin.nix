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

  # Git: GPGパス（Nix版を使用）
  programs.git.settings = {
    gpg.program = "${pkgs.gnupg}/bin/gpg";
  };

  # macOS システム設定の自動化
  home.activation.macosSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    echo "macOS設定を適用中..."

    # キーボード設定
    /usr/bin/defaults write NSGlobalDomain KeyRepeat -int 1                          # リピート速度最速
    /usr/bin/defaults write NSGlobalDomain InitialKeyRepeat -int 10                  # 遅延最短
    /usr/bin/defaults write com.apple.keyboard.fnState -bool true                    # FnキーをF1-F12として使用
    /usr/bin/defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false      # 長押しアクセント無効

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

    # 起動音を無効化（sudo必要）
    if /usr/bin/sudo -n /usr/sbin/nvram StartupMute=%01 2>/dev/null; then
      echo "✓ 起動音を無効化しました"
    else
      echo "⚠ 起動音の無効化をスキップ（sudoが必要）。手動で実行: sudo nvram StartupMute=%01"
    fi

    # スリープ設定（sudo必要）
    # AC電源接続時: スリープ無効、ディスプレイは30分でオフ
    if /usr/bin/sudo -n /usr/bin/pmset -c sleep 0 displaysleep 30 2>/dev/null; then
      echo "✓ スリープ設定を適用しました（スリープ無効、ディスプレイ30分）"
    else
      echo "⚠ スリープ設定をスキップ（sudoが必要）。手動で実行: sudo pmset -c sleep 0 displaysleep 30"
    fi

    echo "✓ macOS設定完了（一部設定は再ログインまたは再起動後に反映）"
  '';
}
