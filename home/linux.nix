# Linux固有のHome Manager設定
# OSサービス（sshd、Tailscale、GPUドライバ）はNixではなくUbuntu側で管理する。
{ ... }:

{
  targets.genericLinux.enable = true;

  # GUIなしのサーバーではURLを表示するだけにする。
  home.sessionVariables.BROWSER = "echo";

  programs.ssh.matchBlocks."*" = {
    forwardAgent = false;
  };
}
