#!/usr/bin/env bash
# Tailscaleはsystemdサービスを使うため、Home ManagerではなくUbuntu側へ導入する。
set -euo pipefail

# ホストごとの設定（TAILSCALE_HOSTNAME）
# shellcheck source=lib/ubuntu-host.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/ubuntu-host.sh"

if [[ "$(uname -s)" != "Linux" ]] || ! command -v apt-get >/dev/null; then
  echo "このスクリプトはUbuntu/Debian系Linux専用です" >&2
  exit 1
fi

if ! command -v tailscale >/dev/null; then
  echo "Tailscale公式インストーラを実行します"
  curl -fsSL https://tailscale.com/install.sh | sh
fi

sudo systemctl enable --now tailscaled
# 認証はURLを表示してブラウザで行う（認証キーはスクリプトに書かない）
up_args=()
if [[ -n "$TAILSCALE_HOSTNAME" ]]; then
  up_args+=("--hostname=$TAILSCALE_HOSTNAME")
fi
sudo tailscale up "${up_args[@]}"
# serve（configure-tailscale-serve-ubuntu.sh、install-qwen38 など）をsudoなしで設定できるようにする。
# chibihamuntu はこの形（OperatorUser=chibiham）で動いている
sudo tailscale set --operator="$USER"

echo "Tailscale IP: $(tailscale ip -4)"
echo "SSH接続を確認してから、必要に応じてUFWを設定してください"
echo "tailnet内への公開（ホストの TAILSCALE_SERVE）: $(dirname "${BASH_SOURCE[0]}")/configure-tailscale-serve-ubuntu.sh"
