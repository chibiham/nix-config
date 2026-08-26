#!/usr/bin/env bash
# Tailscaleはsystemdサービスを使うため、Home ManagerではなくUbuntu側へ導入する。
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]] || ! command -v apt-get >/dev/null; then
  echo "このスクリプトはUbuntu/Debian系Linux専用です" >&2
  exit 1
fi

if ! command -v tailscale >/dev/null; then
  echo "Tailscale公式インストーラを実行します"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

sudo systemctl enable --now tailscaled
sudo tailscale up

echo "Tailscale IP: $(tailscale ip -4)"
echo "SSH接続を確認してから、必要に応じてUFWを設定してください"
