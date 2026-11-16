#!/usr/bin/env bash
# ~/turn-off-gpu-led.shを基に、毎回GPUを検出して消灯する。
# 機器番号やI2Cバス番号は再起動で変わり得るため固定しない。
#
# 対象はOpenRGBの一覧の行（小文字）に GPU_LED_MATCH が当たるもので、ちょうど GPU_LED_COUNT 台のときだけ消す。
# 既定（Gigabyte RTX 3090 が1台）は chibihamuntu。ほかのホストは /etc/default/gpu-led-off で変える
# （install-gpu-led-off-ubuntu.sh が hosts/ubuntu/<ホスト名>.env から書く）。
set -euo pipefail

OPENRGB_APP="${OPENRGB_APP:-/opt/openrgb-1.0rc3.1/AppRun}"
OPENRGB_CONFIG="${OPENRGB_CONFIG:-/var/lib/gpu-led-off}"
GPU_LED_MATCH="${GPU_LED_MATCH:-gigabyte.*rtx ?3090}"
GPU_LED_COUNT="${GPU_LED_COUNT:-1}"
export QT_QPA_PLATFORM=offscreen

device_list="$("$OPENRGB_APP" --noautoconnect --config "$OPENRGB_CONFIG" --list-devices)"
printf '%s\n' "$device_list"

if [[ "$GPU_LED_COUNT" == 1 ]]; then
  # 対象なし・複数一致の場合、全機器へOffを送らず失敗として扱う。
  gpu_name="$(printf '%s\n' "$device_list" | awk -v pattern="$GPU_LED_MATCH" '
    /^[0-9]+:/ && tolower($0) ~ pattern {
      sub(/^[0-9]+:[[:space:]]*/, "")
      name = $0
      count++
    }
    END { if (count == 1) print name; else exit 1 }
  ')" || {
    echo "GPU（${GPU_LED_MATCH}）を一意に検出できません。LED設定は変更しません。" >&2
    exit 1
  }

  # 検出時と制御時で番号が変わっても、同じGPUだけを選択する。
  "$OPENRGB_APP" --noautoconnect --config "$OPENRGB_CONFIG" --device "$gpu_name" --mode Off
  echo "GPU LEDをOffに設定しました: $gpu_name"
  exit 0
fi

# 同じ名前のカードが複数ある場合は名前で区別できないので、一覧の番号で選ぶ。
# 一覧と制御の間で番号が変わらないよう、同じ起動の中で続けて呼ぶ。台数が違えば何も変えない。
mapfile -t gpu_indexes < <(printf '%s\n' "$device_list" | awk -v pattern="$GPU_LED_MATCH" '
  /^[0-9]+:/ && tolower($0) ~ pattern { sub(/:.*/, ""); print }
')
if [[ ${#gpu_indexes[@]} -ne "$GPU_LED_COUNT" ]]; then
  echo "GPU（${GPU_LED_MATCH}）が${#gpu_indexes[@]}台見えます（期待: ${GPU_LED_COUNT}台）。LED設定は変更しません。" >&2
  exit 1
fi
args=()
for index in "${gpu_indexes[@]}"; do
  args+=(--device "$index" --mode Off)
done
"$OPENRGB_APP" --noautoconnect --config "$OPENRGB_CONFIG" "${args[@]}"
echo "GPU LEDをOffに設定しました: 機器番号 ${gpu_indexes[*]}"
