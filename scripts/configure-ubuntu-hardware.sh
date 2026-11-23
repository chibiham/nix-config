#!/usr/bin/env bash
# HWEカーネル、GPU LEDの起動時消灯、RAPLの読み取り権限、ケースファンの制御（CASE_FAN_CONTROL=1 のとき）をまとめて反映する。OSは再起動しない。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $EUID -ne 0 ]]; then
  exec sudo /bin/bash "$(realpath "$0")" "$@"
fi

# ホストごとの設定（GPU_LED_OFF・CPU_POWER_READ・CASE_FAN_CONTROL）
# shellcheck source=lib/ubuntu-host.sh
source "$SCRIPT_DIR/lib/ubuntu-host.sh"

bash "$SCRIPT_DIR/install-hwe-kernel-ubuntu.sh"
if [[ "$GPU_LED_OFF" == 1 ]]; then
  bash "$SCRIPT_DIR/install-gpu-led-off-ubuntu.sh"
else
  echo "GPU LEDの消灯は入れません（hosts/ubuntu/$UBUNTU_HOST.env の GPU_LED_OFF=0）"
fi
if [[ "$CPU_POWER_READ" == 1 ]]; then
  bash "$SCRIPT_DIR/install-rapl-power-access-ubuntu.sh"
else
  echo "CPU消費電力の読み取り権限は入れません（CPU_POWER_READ=0）"
fi
if [[ "$CASE_FAN_CONTROL" == 1 ]]; then
  bash "$SCRIPT_DIR/install-case-fan-control-ubuntu.sh"
fi
echo "ハードウェア設定を反映しました。カーネルの切り替えは次回の手動再起動時です。"
