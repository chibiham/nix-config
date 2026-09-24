# Mac mini固有のHome Manager設定。
# 共通設定は ../common.nix と ../darwin.nix で管理する。
{
  config,
  lib,
  pkgs,
  ...
}:

let
  modelDir = "${config.home.homeDirectory}/models/qwen3.8-27b";
  modelFile = "${modelDir}/Qwen3.8-27B-Uncensored-Q4_K_M.gguf";
  serviceLabel = "org.nix-community.home.qwen38";

  qwen38 = pkgs.writeShellScriptBin "qwen38" ''
    set -euo pipefail

    domain="gui/$UID"
    service="$domain/${serviceLabel}"

    usage() {
      echo "usage: qwen38 {start|stop|restart|status|logs}" >&2
      exit 2
    }

    case "''${1:-}" in
      start)
        if [[ ! -s ${lib.escapeShellArg modelFile} ]]; then
          echo "モデルがありません。先に次を実行してください:" >&2
          echo "  ~/.config/nix-config/scripts/install-qwen38-mac-mini.sh" >&2
          exit 1
        fi
        /bin/launchctl kickstart -k "$service"
        echo "Qwen3.8を起動しました: http://127.0.0.1:8080"
        ;;
      stop)
        /bin/launchctl kill SIGTERM "$service" 2>/dev/null || true
        echo "Qwen3.8を停止しました"
        ;;
      restart)
        /bin/launchctl kickstart -k "$service"
        echo "Qwen3.8を再起動しました: http://127.0.0.1:8080"
        ;;
      status)
        /bin/launchctl print "$service" 2>/dev/null || true
        echo
        ${pkgs.curl}/bin/curl --silent --show-error --max-time 2 \
          http://127.0.0.1:8080/health || true
        echo
        ;;
      logs)
        /usr/bin/tail -f \
          ${lib.escapeShellArg "${config.home.homeDirectory}/Library/Logs/qwen38.log"}
        ;;
      *) usage ;;
    esac
  '';
in

{
  home.packages = [
    pkgs.llama-cpp
    pkgs.aria2
    qwen38
  ];

  # 32GBを普段の作業へ残すため、ログイン時には起動しない。
  # `qwen38 start`で必要なときだけlaunchd jobを開始する。
  launchd.agents.qwen38 = {
    enable = true;
    config = {
      ProgramArguments = [
        "${lib.getExe' pkgs.llama-cpp "llama-server"}"
        "--model"
        modelFile
        "--host"
        "127.0.0.1"
        "--port"
        "8080"
        "--ctx-size"
        "131072"
        "--n-gpu-layers"
        "99"
        "--flash-attn"
        "on"
        "--cache-type-k"
        "q8_0"
        "--cache-type-v"
        "q8_0"
        "--parallel"
        "1"
        "--jinja"
      ];
      KeepAlive = false;
      RunAtLoad = false;
      ProcessType = "Interactive";
      StandardOutPath = "${config.home.homeDirectory}/Library/Logs/qwen38.log";
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/qwen38.log";
      SoftResourceLimits.NumberOfFiles = 4096;
    };
  };
}
