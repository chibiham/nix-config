#!/usr/bin/env bash
# Ubuntu Serverの初期セットアップ。何度実行しても安全な範囲だけを扱う。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLAKE_TARGET="${USER}@ubuntu-server"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Linux" ]] || ! command -v apt-get >/dev/null; then
  echo "このスクリプトはUbuntu/Debian系Linux専用です" >&2
  exit 1
fi

step "Ubuntuの基礎パッケージ"
sudo apt-get update
sudo apt-get install -y ca-certificates curl git openssh-server xz-utils
sudo systemctl enable --now ssh

if ! command -v nix >/dev/null; then
  cat >&2 <<'EOF'
Nixが未導入です。Determinate Nix Installer等でNixを導入し、いったんログインし直してから再実行してください:
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
EOF
  exit 1
fi

step "Home Manager"
nix run "$REPO_DIR#home-manager" -- switch -b backup --flake "$REPO_DIR#$FLAKE_TARGET"
export PATH="$HOME/.nix-profile/bin:$PATH"

step "miseランタイム"
mise install --yes

ok "Ubuntuの基礎セットアップが完了しました"
echo "次: $REPO_DIR/scripts/install-tailscale-ubuntu.sh"
echo "GPUドライバとComfyUIはGPU装着後に別途セットアップします"
