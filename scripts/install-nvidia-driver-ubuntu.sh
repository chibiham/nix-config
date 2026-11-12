#!/usr/bin/env bash
# Ubuntuが推奨するNVIDIAドライバを導入する。CUDA ToolkitやComfyUIは扱わない。
set -euo pipefail

# ホストごとの設定（NVIDIA_EXPECTED_GPUS・NVIDIA_REQUIRE_OPEN・NVIDIA_MIN_DRIVER）
# shellcheck source=lib/ubuntu-host.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/ubuntu-host.sh"

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
gpu_count="$(lspci -d 10de: | grep -ciE 'VGA|3D|Display')"
if [[ "$NVIDIA_EXPECTED_GPUS" -gt 0 && "$gpu_count" -ne "$NVIDIA_EXPECTED_GPUS" ]]; then
  echo "NVIDIA GPUが${gpu_count}枚見えます（期待: ${NVIDIA_EXPECTED_GPUS}枚）。装着・補助電源・BIOSのPCIe設定を確認してください" >&2
  exit 1
fi

# 正常にロード済みなら、aptやカーネルへ不要な変更を加えない。
if command -v nvidia-smi >/dev/null && nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
  ok "NVIDIAドライバは動作済みです"
  exit 0
fi

step "Ubuntuの推奨ドライバ"
ubuntu-drivers devices

# Blackwell（RTX 50）以降はオープンカーネルモジュールでしか動かない。
# 推奨がプロプライエタリ版や古い世代なら、何も入れずに止まる（版は固定しない。ADR 0001）。
if [[ "$NVIDIA_REQUIRE_OPEN" == 1 || "$NVIDIA_MIN_DRIVER" -gt 0 ]]; then
  recommended="$(ubuntu-drivers devices 2>/dev/null | awk '/recommended/ { for (i = 1; i <= NF; i++) if ($i ~ /^nvidia-driver-/) print $i }' | head -1)"
  if [[ -z "$recommended" ]]; then
    echo "推奨ドライバを読み取れませんでした。上の一覧を確認してください" >&2
    exit 1
  fi
  echo "推奨: $recommended"
  if [[ "$NVIDIA_REQUIRE_OPEN" == 1 && "$recommended" != *-open ]]; then
    echo "推奨がオープンカーネルモジュール版ではありません。このGPUには *-open が必須です" >&2
    echo "一覧から nvidia-driver-<世代>-open を選び、確かめてから手で入れてください:" >&2
    echo "  sudo apt-get install nvidia-driver-<世代>-open" >&2
    exit 1
  fi
  recommended_major="$(sed -nE 's/^nvidia-driver-([0-9]+).*/\1/p' <<<"$recommended")"
  if [[ "$NVIDIA_MIN_DRIVER" -gt 0 && "${recommended_major:-0}" -lt "$NVIDIA_MIN_DRIVER" ]]; then
    echo "推奨ドライバの世代（${recommended_major}）が、このGPUに要る世代（${NVIDIA_MIN_DRIVER}以降）より古いです" >&2
    exit 1
  fi
fi

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
