#!/usr/bin/env bash
# Ubuntu 24.04のHWEと、導入済みNVIDIAドライバに対応するモジュールを追加する。
# 実行中のカーネルを残す。再起動、ドライバの再ロードは行わない。
set -euo pipefail

dry_run=false
case "${1:-}" in
  --dry-run) dry_run=true ;;
  "") ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || exit 2

# shellcheck source=/dev/null
source /etc/os-release
if [[ "$ID" != ubuntu || "$VERSION_ID" != 24.04 ]]; then
  echo "このスクリプトはUbuntu 24.04専用です" >&2
  exit 1
fi

if ! "$dry_run" && [[ $EUID -ne 0 ]]; then
  exec sudo /bin/bash "$(realpath "$0")" "$@"
fi

running_kernel="$(uname -r)"
packages=(linux-generic-hwe-24.04)
mapfile -t nvidia_drivers < <(
  dpkg-query -W -f='${binary:Package} ${db:Status-Abbrev}\n' 'nvidia-driver-*' 2>/dev/null |
    awk '$2 == "ii" { sub(/:amd64$/, "", $1); print $1 }'
)
if [[ ${#nvidia_drivers[@]} -gt 1 ]]; then
  echo "複数のNVIDIAドライバが導入されています。先に構成を確認してください" >&2
  exit 1
elif [[ ${#nvidia_drivers[@]} -eq 1 ]]; then
  driver_suffix="${nvidia_drivers[0]#nvidia-driver-}"
  if [[ ! "$driver_suffix" =~ ^[0-9]+(-server)?(-open)?$ ]]; then
    echo "未対応のNVIDIAパッケージ名: ${nvidia_drivers[0]}" >&2
    exit 1
  fi
  # ドライバの世代は固定せず、現在導入済みのものに合わせる。
  packages+=("linux-modules-nvidia-${driver_suffix}-generic-hwe-24.04")
fi

if ! "$dry_run"; then
  apt-get update
fi
printf '現在のカーネル: %s\n追加対象: %s\n' "$running_kernel" "${packages[*]}"
apt-get --simulate --no-remove install --install-recommends "${packages[@]}"
if "$dry_run"; then
  echo "確認のみ。インストールも再起動も行っていません。"
  exit 0
fi

# 直前の正常なカーネルとGPUモジュールをautoremoveの対象から外す。
keep_packages=()
for package in "linux-image-$running_kernel" "linux-modules-$running_kernel" \
  "linux-modules-extra-$running_kernel" "linux-headers-$running_kernel" \
  "linux-modules-nvidia-${driver_suffix:-none}-$running_kernel"; do
  if [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$package" 2>/dev/null || true)" == "ii " ]]; then
    keep_packages+=("$package")
  fi
done
if [[ ${#keep_packages[@]} -gt 0 ]]; then
  apt-mark manual "${keep_packages[@]}"
fi

# needrestartによる稼働中サービスの再起動も避ける。
NEEDRESTART_MODE=l apt-get --no-remove install --install-recommends -y "${packages[@]}"

target_kernel="$(dpkg-query -W -f='${Depends}' linux-image-generic-hwe-24.04 |
  sed -nE 's/.*linux-image-([0-9][a-z0-9.+-]*-generic)(,|[[:space:]]|$).*/\1/p')"
if [[ -z "$target_kernel" || ! -s "/boot/vmlinuz-$target_kernel" || ! -s "/boot/initrd.img-$target_kernel" ]]; then
  echo "HWEカーネルまたはinitramfsを確認できませんでした。再起動前に確認してください" >&2
  exit 1
fi
if [[ ${#nvidia_drivers[@]} -eq 1 ]]; then
  printf 'HWE用NVIDIAモジュール: '
  modinfo -k "$target_kernel" -F version nvidia
fi
printf '導入済み: %s\n現在稼働中: %s\n' "$target_kernel" "$(uname -r)"
echo "次回の手動再起動でHWEへ切り替わります。自動再起動は行いません。"
