# ChatGPTからBlender MCPを使うためのOpenAI Secure MCP Tunnel。
# tunnel-clientが外向きにOpenAIのcontrol planeへ接続し、stdioのMCPサーバー
# （mcp-for-blender）を中継する。Blender側はアドオンの「Start MCP Server」で
# localhost:9876 を待ち受けておく。
# アドオンはサーバーと同じバージョンで入れる:
#   uvx mcp-for-blender@<mcpForBlenderVersion> install-addon
{
  config,
  lib,
  pkgs,
  ...
}:

let
  tunnelId = "tunnel_6ab7fa7ac8048191ab787114e5aeacdc";
  # アドオンのプロトコルと揃えるためピン留めする
  mcpForBlenderVersion = "2.1.0";
  # qwen38が8080を使うので避ける
  healthAddr = "127.0.0.1:8765";
  logFile = "${config.home.homeDirectory}/Library/Logs/tunnel-client-blender.log";

  tunnel-client = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "tunnel-client";
    version = "0.0.15";
    # ハッシュはリリースのSHA256SUMS.txtと同じzip自体のもの
    src = pkgs.fetchurl {
      url = "https://github.com/openai/tunnel-client/releases/download/v${version}/tunnel-client-v${version}-darwin-arm64.zip";
      hash = "sha256-ssrjqp30W0wv6bHXAOuszjn5/ramtGuG5kmfmlG/cv8=";
    };
    nativeBuildInputs = [ pkgs.unzip ];
    sourceRoot = ".";
    # 同梱のcloudflaredはnixpkgs版と衝突しないようlibexecに置く
    installPhase = ''
      mkdir -p $out/libexec/tunnel-client $out/bin
      cp tunnel-client cloudflared cloudflared-manifest.json $out/libexec/tunnel-client/
      chmod +x $out/libexec/tunnel-client/tunnel-client $out/libexec/tunnel-client/cloudflared
      cat > $out/bin/tunnel-client <<EOF
      #!/bin/sh
      exec $out/libexec/tunnel-client/tunnel-client "\$@"
      EOF
      chmod +x $out/bin/tunnel-client
    '';
    meta.platforms = [ "aarch64-darwin" ];
  };

  # tunnel-clientはプロファイルディレクトリ外を指すsymlinkを読まないので、
  # ~/.config/tunnel-client には置かず --config でstoreのパスを直接渡す
  tunnelConfig = pkgs.writeText "tunnel-client-blender.yaml" ''
    config_version: 1
    control_plane:
      base_url: "https://api.openai.com"
      tunnel_id: "${tunnelId}"
      api_key: "env:CONTROL_PLANE_API_KEY"
    health:
      listen_addr: "${healthAddr}"
    admin_ui:
      open_browser: false
    log:
      level: info
      format: json
    mcp:
      commands:
        - channel: main
          command: "${pkgs.uv}/bin/uvx mcp-for-blender@${mcpForBlenderVersion}"
  '';

  # APIキーはupdate-secretsが展開する ~/.secrets/.env.secrets から読む
  runTunnel = pkgs.writeShellScript "tunnel-client-blender" ''
    set -euo pipefail
    if [ -f "$HOME/.secrets/.env.secrets" ]; then
      source "$HOME/.secrets/.env.secrets"
    fi
    if [ -z "''${CONTROL_PLANE_API_KEY:-}" ]; then
      echo "CONTROL_PLANE_API_KEY が未設定です（update-secrets を実行してください）" >&2
      exit 1
    fi
    export CONTROL_PLANE_API_KEY
    exec ${tunnel-client}/bin/tunnel-client run --config ${tunnelConfig}
  '';
in

{
  home.packages = [ tunnel-client ];

  # ログイン時に起動し、落ちたら再起動する
  launchd.agents.tunnel-client-blender = {
    enable = true;
    config = {
      ProgramArguments = [ "${runTunnel}" ];
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 30;
      StandardOutPath = logFile;
      StandardErrorPath = logFile;
    };
  };
}
