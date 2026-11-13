#!/bin/bash
# fan2go の cmd センサー: NVIDIA GPU の温度の最大を、ミリ度（℃×1000）で1行に出す。
# install-case-fan-control-ubuntu.sh が /usr/local/sbin/case-fan-gpu-temp（root 所有）として置く。
#
#   case-fan-gpu-temp <期待する枚数（0なら確かめない）> <読めないときの温度（℃）>
#
# 読めないとき（nvidia-smi の失敗・時間切れ、枚数の不足、数でない値）は、終了コードを 0 にしたまま
# 「読めないときの温度」を出す。曲線の最大を超える温度にしておけば、ケースファンは全開になる
# （fan2go の版によって、センサーの失敗の扱いが違うため。ここで全開側に倒す）。
# 最後に読んだ結果を CASE_FAN_STATUS_FILE（既定 /run/fan2go/case-fan-gpu-temp.status）に書く。
set -u

expected="${1:-0}"
failsafe_c="${2:-100}"
smi="${CASE_FAN_NVIDIA_SMI:-/usr/bin/nvidia-smi}"
status_file="${CASE_FAN_STATUS_FILE:-/run/fan2go/case-fan-gpu-temp.status}"

[[ "$expected" =~ ^[0-9]+$ ]] || expected=0
[[ "$failsafe_c" =~ ^[0-9]+$ ]] || failsafe_c=100

record() {
  # 書けなくても温度は出す（状態のファイルは確かめるためだけのもの）
  { printf '%s %s\n' "$(date -Iseconds)" "$1" > "$status_file.tmp" &&
      mv -f "$status_file.tmp" "$status_file"; } 2>/dev/null || true
}

failsafe() {
  echo "case-fan-gpu-temp: $1。全開側の ${failsafe_c}℃ を出します" >&2
  record "failsafe ${failsafe_c} $1"
  printf '%d\n' $((failsafe_c * 1000))
  exit 0
}

if ! out="$(timeout -k 0.5 1.5 "$smi" --query-gpu=temperature.gpu --format=csv,noheader,nounits 2>&1)"; then
  failsafe "nvidia-smi が失敗した: $(head -1 <<<"$out")"
fi

max=-1
count=0
while IFS= read -r line; do
  line="${line//[[:space:]]/}"
  [[ -n "$line" ]] || continue
  [[ "$line" =~ ^[0-9]+$ ]] || failsafe "数でない値: $line"
  count=$((count + 1))
  ((line > max)) && max=$line
done <<<"$out"

((count > 0)) || failsafe "GPU が1枚も見えない"
if ((expected > 0 && count != expected)); then
  failsafe "GPU が ${count} 枚（${expected} 枚のはず）"
fi

record "ok ${max} gpus=${count}"
printf '%d\n' $((max * 1000))
