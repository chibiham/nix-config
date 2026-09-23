#!/usr/bin/env bash
# HWEカーネルとGPU LEDの起動時消灯をまとめて反映する。OSは再起動しない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $EUID -ne 0 ]]; then
  exec sudo /bin/bash "$(realpath "$0")" "$@"
fi

bash "$SCRIPT_DIR/install-hwe-kernel-ubuntu.sh"
bash "$SCRIPT_DIR/install-gpu-led-off-ubuntu.sh"
echo "ハードウェア設定を反映しました。カーネルの切り替えは次回の手動再起動時です。"
