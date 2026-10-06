#!/usr/bin/env bash
# HWEカーネル、GPU LEDの起動時消灯、RAPLの読み取り権限をまとめて反映する。OSは再起動しない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $EUID -ne 0 ]]; then
  exec sudo /bin/bash "$(realpath "$0")" "$@"
fi

bash "$SCRIPT_DIR/install-hwe-kernel-ubuntu.sh"
bash "$SCRIPT_DIR/install-gpu-led-off-ubuntu.sh"
bash "$SCRIPT_DIR/install-rapl-power-access-ubuntu.sh"
echo "ハードウェア設定を反映しました。カーネルの切り替えは次回の手動再起動時です。"
