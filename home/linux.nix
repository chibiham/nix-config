# Linux固有のHome Manager設定
# OSサービス（sshd、Tailscale、GPUドライバ）はNixではなくUbuntu側で管理する。
{ config, pkgs, ... }:

let
  # RTX搭載LinuxではCUDA版llama.cppを使う。モデル本体は巨大かつ更新が
  # ネットワーク依存なので、scripts/install-qwen38-ubuntu.shで取得する。
  llama-cpp-cuda = pkgs.llama-cpp.override { cudaSupport = true; };

  # 3090の24GBを取り合うサービス（Qwen/ComfyUI/Applio）を排他で切り替える。
  # 実体の排他はunit側のConflicts=で担保し、ここは入口を揃えるだけにする。
  ai-mode = pkgs.writeShellScriptBin "ai-mode" ''
    set -euo pipefail

    usage() {
      echo "usage: ai-mode {qwen|comfy|applio|stop|status}" >&2
      exit 2
    }

    case "''${1:-}" in
      qwen)
        systemctl --user start qwen38.service
        ;;
      comfy)
        systemctl --user start comfyui.service
        ;;
      applio)
        systemctl --user start applio.service
        ;;
      stop)
        systemctl --user stop qwen38.service comfyui.service applio.service
        ;;
      status)
        systemctl --user --no-pager --full status qwen38.service comfyui.service applio.service || true
        ;;
      *) usage ;;
    esac
  '';

  # Civitaiのモデル取得（Claude Codeのcivitai-download skillから使う）
  civitai-download = pkgs.writeShellApplication {
    name = "civitai-download";
    runtimeInputs = with pkgs; [
      curl
      jq
      coreutils
      gnused
    ];
    text = builtins.readFile ../scripts/civitai-download.sh;
  };
in

{
  targets.genericLinux.enable = true;

  home.packages = [
    llama-cpp-cuda
    pkgs.cudaPackages.cuda_nvcc
    pkgs.aria2
    ai-mode
    civitai-download
  ];

  # op inject用テンプレート（update-secretsコマンドで展開）
  # Mac用の MyMachine Vault は読ませず、このマシン専用の Service Account が
  # 読める "chibihamuntu" Vault だけを参照する
  home.file.".secrets/env.tpl" = {
    force = true;
    text = ''
      export CIVITAI_TOKEN="op://chibihamuntu/CIVITAI_TOKEN/credential"
    '';
  };

  # Claude Code skill（~/.claude/skills はマシン横断のskills repoと共存するため
  # ディレクトリ単位で置く）
  home.file.".claude/skills/civitai-download".source = ../claude/skills/civitai-download;

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
