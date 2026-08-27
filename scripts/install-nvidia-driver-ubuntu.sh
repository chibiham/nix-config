#!/usr/bin/env bash
# Ubuntuが推奨するNVIDIAドライバを導入する。CUDA ToolkitやComfyUIは扱わない。
set -euo pipefail

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Linux" ]] || ! command -v apt-get >/dev/null; then
  echo "このスクリプトはUbuntu/Debian系Linux専用です" >&2
  exit 1
fi

step "検出ツール"
sudo apt-get update
sudo apt-get install -y pciutils ubuntu-drivers-common

if ! lspci -d 10de: | grep -qiE 'VGA|3D|Display'; then
  echo "NVIDIA GPUをPCIe上で検出できませんでした" >&2
  echo "補助電源、PCIeスロット、BIOS設定を確認してください" >&2
  exit 1
fi

step "NVIDIA GPU"
lspci -d 10de: | grep -iE 'VGA|3D|Display'

# 正常にロード済みなら、aptやカーネルへ不要な変更を加えない。
if command -v nvidia-smi >/dev/null && nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
  ok "NVIDIAドライバは動作済みです"
  exit 0
fi

step "Ubuntuの推奨ドライバ"
ubuntu-drivers devices

step "推奨ドライバをインストール"
sudo ubuntu-drivers install

if command -v mokutil >/dev/null; then
  echo
  mokutil --sb-state 2>/dev/null || true
fi

echo
ok "NVIDIAドライバをインストールしました"
warn "カーネルモジュールをロードするため、作業を保存してから再起動してください"
echo "  sudo reboot"
echo
echo "再起動後の確認:"
echo "  nvidia-smi"
echo "  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv"
