# macOS固有の設定
{ pkgs, config, ... }:

{
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
  home.sessionPath = [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
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

  # Git: macOSのGPGパス
  programs.git.settings.gpg.program = "/opt/homebrew/bin/gpg";
}
