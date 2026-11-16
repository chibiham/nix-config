#!/usr/bin/env bash
# art-studio（~/ai/apps/art-studio。unit 本体は ~/ai/scripts/install-art-studio が書く）に、
# このホストだけの差分を drop-in で足す。書くのは ComfyUI の URL と、モザイクの YOLO を載せる GPU。
# どちらも hosts/ubuntu/<ホスト名>.env の ART_STUDIO_COMFYUI_URL・ART_STUDIO_CUDA_DEVICES で決める。
# 両方とも空なら何も書かない（chibihamuntu）。install-art-studio を流し直しても drop-in は残る。
# --dry-run は書く中身を表示するだけ。
set -euo pipefail

# shellcheck source=lib/ubuntu-host.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/ubuntu-host.sh"

dry_run=0
case "${1:-}" in
  "") ;;
  --dry-run) dry_run=1 ;;
  *) echo "usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

DROPIN_DIR="$HOME/.config/systemd/user/art-studio.service.d"
DROPIN_FILE="$DROPIN_DIR/$UBUNTU_HOST.conf"

if [[ -z "$ART_STUDIO_COMFYUI_URL" && -z "$ART_STUDIO_CUDA_DEVICES" ]]; then
  echo "ART_STUDIO_COMFYUI_URL・ART_STUDIO_CUDA_DEVICES が空なので、drop-in は書きません（hosts/ubuntu/$UBUNTU_HOST.env）"
  exit 0
fi

content="# $UBUNTU_HOST だけの差分（install-art-studio を流し直しても消えないよう drop-in に置く）
[Service]
"
if [[ -n "$ART_STUDIO_COMFYUI_URL" ]]; then
  content+="# 同じ機械の ComfyUI に直接つなぐ（既定は chibihamuntu の Tailscale Serve）
Environment=COMFYUI_URL=$ART_STUDIO_COMFYUI_URL
"
fi
if [[ -n "$ART_STUDIO_CUDA_DEVICES" ]]; then
  content+="# モザイクの YOLO を画像生成の GPU $ART_STUDIO_CUDA_DEVICES に載せる（GPU 1 は LLM）
Environment=CUDA_DEVICE_ORDER=PCI_BUS_ID
Environment=CUDA_VISIBLE_DEVICES=$ART_STUDIO_CUDA_DEVICES
"
fi

if (( dry_run )); then
  echo "(dry-run) $DROPIN_FILE:"
  printf '%s' "$content"
  exit 0
fi

mkdir -p "$DROPIN_DIR"
printf '%s' "$content" > "$DROPIN_FILE"
echo "書いた: $DROPIN_FILE"
systemctl --user daemon-reload
# 動いていれば読み直す（止まっていれば起こさない。起動・有効化は install-art-studio の役目）
systemctl --user try-restart art-studio.service
systemctl --user --no-pager show art-studio.service -p Environment
