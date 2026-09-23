#!/usr/bin/env bash
# 固定版OpenRGBと、起動時にGPUを消灯するsystem serviceを導入する。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENRGB_VERSION=1.0rc3.1
OPENRGB_SHA256=42910311b364ae525ca593f53f5fadcf746b4de41e9e49302a5aa5dd614a608a
OPENRGB_URL="https://codeberg.org/OpenRGB/OpenRGB/releases/download/release_candidate_${OPENRGB_VERSION}/OpenRGB_${OPENRGB_VERSION}_x86_64_5e81e26.AppImage"
OPENRGB_DIR="/opt/openrgb-${OPENRGB_VERSION}"

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo "このスクリプトはUbuntu x86_64専用です" >&2
  exit 1
fi
if [[ $EUID -ne 0 ]]; then
  exec sudo /bin/bash "$(realpath "$0")" "$@"
fi

work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT

if [[ ! -x "$OPENRGB_DIR/AppRun" || ! -f "$OPENRGB_DIR/.appimage-sha256" ]] ||
   [[ "$(cat "$OPENRGB_DIR/.appimage-sha256" 2>/dev/null || true)" != "$OPENRGB_SHA256" ]]; then
  # 前回の公式AppImageがあれば再利用し、同じSHA256で検証する。
  invoking_home="$(getent passwd "${SUDO_USER:-root}" | cut -d: -f6)"
  local_appimage="${OPENRGB_APPIMAGE:-$invoking_home/OpenRGB.AppImage}"
  if [[ -f "$local_appimage" ]]; then
    cp -- "$local_appimage" "$work_dir/OpenRGB.AppImage"
  else
    curl --fail --location --retry 3 --output "$work_dir/OpenRGB.AppImage" "$OPENRGB_URL"
  fi
  printf '%s  %s\n' "$OPENRGB_SHA256" "$work_dir/OpenRGB.AppImage" | sha256sum --check --status
  chmod 0755 "$work_dir/OpenRGB.AppImage"
  (
    cd "$work_dir"
    ./OpenRGB.AppImage --appimage-extract > extract.log
  )
  # rootサービスはユーザー領域の実行ファイルに依存させない。
  install -d -m 0755 "$OPENRGB_DIR"
  cp -a "$work_dir/squashfs-root/." "$OPENRGB_DIR/"
  chown -R root:root "$OPENRGB_DIR"
  chmod -R go-w "$OPENRGB_DIR"
  printf '%s\n' "$OPENRGB_SHA256" > "$OPENRGB_DIR/.appimage-sha256"
fi

QT_QPA_PLATFORM=offscreen "$OPENRGB_DIR/AppRun" --version
install -m 0755 "$REPO_DIR/scripts/turn-off-gpu-led.sh" /usr/local/sbin/turn-off-gpu-led
install -m 0644 "$REPO_DIR/systemd/gpu-led-off.service" /etc/systemd/system/gpu-led-off.service
systemctl daemon-reload
systemctl enable gpu-led-off.service
# 再実行時も即座にOffを反映する。OSやNVIDIAドライバは再起動しない。
systemctl restart gpu-led-off.service
systemctl --no-pager --full status gpu-led-off.service
echo "GPU LEDの消灯を反映しました。今後はOS起動時にも実行します。"
