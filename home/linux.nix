# Linux固有のHome Manager設定
# OSサービス（sshd、Tailscale、GPUドライバ）はNixではなくUbuntu側で管理する。
{ config, pkgs, ... }:

let
  # RTX搭載LinuxではCUDA版llama.cppを使う。モデル本体は巨大かつ更新が
  # ネットワーク依存なので、scripts/install-qwen38-ubuntu.shで取得する。
  llama-cpp-cuda = pkgs.llama-cpp.override { cudaSupport = true; };

  ai-mode = pkgs.writeShellScriptBin "ai-mode" ''
    set -euo pipefail

    usage() {
      echo "usage: ai-mode {qwen|comfy|stop|status}" >&2
      exit 2
    }

    case "''${1:-}" in
      qwen)
        systemctl --user start qwen38.service
        ;;
      comfy)
        systemctl --user start comfyui.service
        ;;
      stop)
        systemctl --user stop qwen38.service comfyui.service
        ;;
      status)
        systemctl --user --no-pager --full status qwen38.service comfyui.service || true
        ;;
      *) usage ;;
    esac
  '';
in

{
  targets.genericLinux.enable = true;

  home.packages = [
    llama-cpp-cuda
    pkgs.aria2
    ai-mode
  ];

  # generic Linux上のNix製CUDAアプリから、Ubuntu/apt管理のNVIDIA driverだけを
  # 参照する。LD_LIBRARY_PATHへ/usr/lib全体を入れるとglibcが衝突するため、
  # libcudaだけをユーザー領域へ公開する。
  home.file.".local/lib/nvidia/libcuda.so.1".source =
    config.lib.file.mkOutOfStoreSymlink "/usr/lib/x86_64-linux-gnu/libcuda.so.1";
  home.file.".local/lib/nvidia/libcuda.so".source =
    config.lib.file.mkOutOfStoreSymlink "/usr/lib/x86_64-linux-gnu/libcuda.so.1";

  # GUIなしのサーバーではURLを表示するだけにする。
  home.sessionVariables.BROWSER = "echo";

  programs.ssh.matchBlocks."*" = {
    forwardAgent = false;
  };
}
