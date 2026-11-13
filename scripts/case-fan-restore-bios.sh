#!/bin/bash
# ケースファンの制御を BIOS（マザーボードの自動制御）へ戻す。
# fan2go.service の ExecStopPost が、止まるたび（正常な停止・落ちたとき・再起動の前）に呼ぶ。
# fan2go 自身も止まるときに元へ戻すが、強制終了などで戻せなかったときの保険。
# install-case-fan-control-ubuntu.sh が /usr/local/sbin/case-fan-restore-bios として置く。
#
# 設定（CASE_FAN_RESTORE_CONF、既定 /etc/fan2go/case-fan-restore.conf）は1行に1チャネル:
#   <hwmon の name> <pwm のチャネル> <戻す pwmN_enable の値>
# 値は、導入のときに fan2go が動いていない状態で読んだもの（BIOS が決めた自動の値）。
set -u

conf="${CASE_FAN_RESTORE_CONF:-/etc/fan2go/case-fan-restore.conf}"
hwmon_root="${CASE_FAN_HWMON_ROOT:-/sys/class/hwmon}"

[[ -r "$conf" ]] || { echo "case-fan-restore-bios: $conf がありません" >&2; exit 0; }

failed=0
while read -r name channel enable _; do
  [[ -n "${name:-}" && "${name:0:1}" != "#" ]] || continue
  if [[ ! "$channel" =~ ^[0-9]+$ || ! "$enable" =~ ^[0-9]+$ ]]; then
    echo "case-fan-restore-bios: 読めない行: $name $channel $enable" >&2
    failed=1
    continue
  fi
  dir=""
  for d in "$hwmon_root"/hwmon*; do
    if [[ "$(cat "$d/name" 2>/dev/null)" == "$name" ]]; then
      dir="$d"
      break
    fi
  done
  if [[ -z "$dir" ]]; then
    echo "case-fan-restore-bios: hwmon $name が見つかりません（ドライバが外れている）" >&2
    failed=1
    continue
  fi
  if printf '%s\n' "$enable" > "$dir/pwm${channel}_enable" 2>/dev/null; then
    echo "case-fan-restore-bios: $name pwm$channel を pwm${channel}_enable=$enable（BIOS の制御）へ戻しました"
  else
    echo "case-fan-restore-bios: $name pwm$channel を戻せませんでした" >&2
    failed=1
  fi
done < "$conf"
exit "$failed"
