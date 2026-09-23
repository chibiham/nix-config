#!/usr/bin/env bash
# ~/turn-off-gpu-led.shを基に、毎回GPUを検出して消灯する。
# 機器番号やI2Cバス番号は再起動で変わり得るため固定しない。
set -euo pipefail

OPENRGB_APP="${OPENRGB_APP:-/opt/openrgb-1.0rc3.1/AppRun}"
OPENRGB_CONFIG="${OPENRGB_CONFIG:-/var/lib/gpu-led-off}"
export QT_QPA_PLATFORM=offscreen

device_list="$("$OPENRGB_APP" --noautoconnect --config "$OPENRGB_CONFIG" --list-devices)"
printf '%s\n' "$device_list"

# 対象なし・複数一致の場合、全機器へOffを送らず失敗として扱う。
gpu_name="$(printf '%s\n' "$device_list" | awk '
  /^[0-9]+:/ && tolower($0) ~ /gigabyte.*rtx ?3090/ {
    sub(/^[0-9]+:[[:space:]]*/, "")
    name = $0
    count++
  }
  END { if (count == 1) print name; else exit 1 }
')" || {
  echo "Gigabyte RTX 3090を一意に検出できません。LED設定は変更しません。" >&2
  exit 1
}

# 検出時と制御時で番号が変わっても、同じGPUだけを選択する。
"$OPENRGB_APP" --noautoconnect --config "$OPENRGB_CONFIG" --device "$gpu_name" --mode Off
echo "GPU LEDをOffに設定しました: $gpu_name"
