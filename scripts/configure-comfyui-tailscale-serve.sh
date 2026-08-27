#!/usr/bin/env bash
# localhostのComfyUIを、同じtailnetの端末だけにHTTPS公開する。
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "このスクリプトはLinux専用です" >&2
  exit 1
fi

for command in tailscale curl; do
  if ! command -v "$command" >/dev/null; then
    echo "必要なコマンドがありません: $command" >&2
    exit 1
  fi
done

if ! tailscale status >/dev/null 2>&1; then
  echo "Tailscaleへ接続されていません。先にsudo tailscale upを実行してください" >&2
  exit 1
fi

# systemd起動直後でもComfyUIが応答するまで少し待つ。
for _ in $(seq 1 30); do
  if curl -fsS --max-time 2 http://127.0.0.1:8188/ >/dev/null; then
    break
  fi
  sleep 1
done
if ! curl -fsS --max-time 2 http://127.0.0.1:8188/ >/dev/null; then
  echo "ComfyUIが127.0.0.1:8188で応答していません" >&2
  echo "確認: systemctl --user status comfyui --no-pager" >&2
  exit 1
fi

echo "ComfyUIをtailnet内だけにHTTPS公開します"
echo "初回はHTTPSを有効化するための認証URLが表示される場合があります"
sudo tailscale serve --bg http://127.0.0.1:8188

echo
sudo tailscale serve status
echo
echo "上記のhttps://...ts.net URLを、同じtailnetの端末から開いてください"
echo "インターネットへ公開するTailscale Funnelは有効化していません"
