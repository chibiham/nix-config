#!/usr/bin/env bash
# RAPLの消費電力カウンタ（/sys/class/powercap/*/energy_uj）をpowerグループに読ませる。
# グループ追加の反映は次回ログインから。OSは再起動しない。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$(uname -s)" != Linux ]]; then
  echo "このスクリプトはLinux専用です" >&2
  exit 1
fi
if [[ $EUID -ne 0 ]]; then
  exec sudo /bin/bash "$(realpath "$0")" "$@"
fi

target_user="${1:-${SUDO_USER:-}}"
if [[ -z "$target_user" || "$target_user" == root ]]; then
  echo "usage: $0 [user]（sudo経由なら実行ユーザー）" >&2
  exit 2
fi

getent group power > /dev/null || groupadd --system power
if ! id -nG "$target_user" | tr ' ' '\n' | grep -qx power; then
  usermod -aG power "$target_user"
fi

install -m 0644 "$REPO_DIR/udev/99-rapl-power.rules" /etc/udev/rules.d/99-rapl-power.rules
udevadm control --reload
# 既存デバイスにもaddを再送して権限をその場で反映する。
udevadm trigger --subsystem-match=powercap --action=add
udevadm settle

ls -l /sys/class/powercap/*/energy_uj
echo "RAPLを${target_user}（powerグループ）から読めるようにしました。新しいログインから有効です。"
