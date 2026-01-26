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
}
