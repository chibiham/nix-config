# WSL固有の設定
{ pkgs, ... }:

{
  # WSL専用パッケージ
  home.packages = with pkgs; [
    wslu  # WSLユーティリティ (wslview等)
  ];

  # WSL固有の環境変数
  home.sessionVariables = {
    # Windows側との連携用
    BROWSER = "wslview";
    # 1Password SSH Agent (Windows側の1Passwordと連携)
    # 要: npiperelay + socat でソケット転送設定
    SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
  };

  # WSL固有のPATH
  home.sessionPath = [
    "$HOME/.local/bin"
  ];

  # WSL固有のZsh設定
  programs.zsh.initContent = ''
    # Windows側のVS Codeを使う
    if command -v code &> /dev/null; then
      export EDITOR="code --wait"
    fi

    # WSLでクリップボードを共有
    alias pbcopy="clip.exe"
    alias pbpaste="powershell.exe -command 'Get-Clipboard' | head -n -1"
  '';

  # Git: WSLのGPGパス（Nixで管理されるgpgを使用）
  programs.git.settings.gpg.program = "${pkgs.gnupg}/bin/gpg";
}
