#!/usr/bin/env bash
# ケースファンを GPU の温度（と CPU の温度）に合わせて回す。道具は fan2go（公式の配布バイナリを版とハッシュで固定）。
# 値はホストの設定（hosts/ubuntu/<ホスト名>.env の CASE_FAN_*）から決める。既定は切（CASE_FAN_CONTROL=0）。
#
#   install-case-fan-control-ubuntu.sh --probe                 # 読むだけ（sudo 不要）。ドライバ・pwm・fan・温度を出し、env の値の手がかりを出す
#   install-case-fan-control-ubuntu.sh --probe --load-module   # Super I/O のドライバ（CASE_FAN_MODULE）を一時的に読み込んでから調べる（sudo。再起動で消える。ファンは変えない）
#   install-case-fan-control-ubuntu.sh --identify <チャネル>   # そのチャネルを 10 秒だけ全開にして RPM を見せ、元に戻す（sudo。どのファンがどれかを見分ける）
#   install-case-fan-control-ubuntu.sh --print-config          # 書く予定の /etc/fan2go/fan2go.yaml を出すだけ（sudo 不要）
#   install-case-fan-control-ubuntu.sh                         # 入れる・入れ直す（sudo）
#   install-case-fan-control-ubuntu.sh --uninstall             # 外して BIOS の制御へ戻す（sudo）
#
# 落ちたとき・止めたときは、fan2go 自身（controlMode.onExit: restore）と unit の ExecStopPost
# （case-fan-restore-bios）が BIOS の制御へ戻す。GPU の温度が読めないときは全開側に倒す（case-fan-gpu-temp）。
# OS の再起動はしない。acpi_enforce_resources=lax（GRUB）は CASE_FAN_ACPI_LAX=1 のときだけ入れる。
set -euo pipefail

FAN2GO_VERSION=0.15.0
# 公式のリリースの fan2go-linux-amd64-no-nvml（GitHub のリリースの digest と同じ）
FAN2GO_SHA256=7dd0c080d78cd30eb6e1252d5d8caffd91ce871a6729fb4118b5574ec54fd234
FAN2GO_URL="https://github.com/markusressel/fan2go/releases/download/${FAN2GO_VERSION}/fan2go-linux-amd64-no-nvml"

FAN2GO_BIN=/usr/local/bin/fan2go
GPU_TEMP_BIN=/usr/local/sbin/case-fan-gpu-temp
RESTORE_BIN=/usr/local/sbin/case-fan-restore-bios
CONFIG_DIR=/etc/fan2go
CONFIG_FILE=$CONFIG_DIR/fan2go.yaml
# 検査してから置き換えるための一時の設定。fan2go（viper）は拡張子で形式を決めるので .yaml で終える
CONFIG_NEW=$CONFIG_DIR/fan2go.new.yaml
RESTORE_CONF=$CONFIG_DIR/case-fan-restore.conf
UNIT_FILE=/etc/systemd/system/fan2go.service
MODULES_LOAD_FILE=/etc/modules-load.d/case-fan-control.conf
GRUB_DROPIN=/etc/default/grub.d/60-case-fan-acpi-lax.cfg
STATUS_FILE=/run/fan2go/case-fan-gpu-temp.status
# GPU の温度が読めないときに出す温度（℃）。曲線の最大の温度より高くして、全開にする
GPU_FAILSAFE_C=100

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  sed -n '2,10p' "$(realpath "${BASH_SOURCE[0]}")" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

mode=install
load_module=false
identify_channel=""
case "${1:-}" in
  "") ;;
  --probe)
    mode=probe
    case "${2:-}" in
      "") ;;
      --load-module) load_module=true ;;
      *) usage ;;
    esac
    [[ $# -le 2 ]] || usage
    ;;
  --identify)
    mode=identify
    identify_channel="${2:-}"
    [[ "$identify_channel" =~ ^[0-9]+$ && $# -eq 2 ]] || usage
    ;;
  --print-config) mode=print-config; [[ $# -eq 1 ]] || usage ;;
  --uninstall) mode=uninstall; [[ $# -eq 1 ]] || usage ;;
  # 試験だけ: 設定を書いて検査する所を、CASE_FAN_TEST_CONFIG_DIR と CASE_FAN_TEST_FAN2GO で動かす（sudo 不要）
  --test-write-config)
    mode=test-write-config
    [[ $# -eq 1 && -n "${CASE_FAN_TEST_CONFIG_DIR:-}" && -n "${CASE_FAN_TEST_FAN2GO:-}" ]] || usage
    FAN2GO_BIN=$CASE_FAN_TEST_FAN2GO
    CONFIG_DIR=$CASE_FAN_TEST_CONFIG_DIR
    CONFIG_FILE=$CONFIG_DIR/fan2go.yaml
    CONFIG_NEW=$CONFIG_DIR/fan2go.new.yaml
    ;;
  *) usage ;;
esac

needs_root=false
case "$mode" in
  install | identify | uninstall) needs_root=true ;;
  probe) if "$load_module"; then needs_root=true; fi ;;
esac
# --print-config は試験のため Linux でなくても動く
if [[ "$mode" != print-config && "$mode" != test-write-config && "$(uname -s)" != Linux ]]; then
  echo "このスクリプトはLinux専用です" >&2
  exit 1
fi
if "$needs_root" && [[ $EUID -ne 0 ]]; then
  exec sudo /bin/bash "$(realpath "$0")" "$@"
fi

# ホストごとの設定（CASE_FAN_*、NVIDIA_EXPECTED_GPUS）
# shellcheck source=lib/ubuntu-host.sh
source "$SCRIPT_DIR/lib/ubuntu-host.sh"

# 試験のときだけ、にせの hwmon の木を指す（sudo 越しでは落ちる）
HWMON_ROOT="${CASE_FAN_HWMON_ROOT:-/sys/class/hwmon}"

ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }
ng()   { printf '\033[1;31m✗ %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
die()  { echo "$1" >&2; exit 1; }

read_value() { cat "$1" 2>/dev/null || echo "?"; }

# hwmon の name が $1 と同じディレクトリを出す。0個なら 1、2個以上なら 2 で返る
find_hwmon() {
  local want="$1" d found=()
  for d in "$HWMON_ROOT"/hwmon*; do
    [[ "$(read_value "$d/name")" == "$want" ]] && found+=("$d")
  done
  [[ ${#found[@]} -ge 1 ]] || return 1
  [[ ${#found[@]} -eq 1 ]] || return 2
  printf '%s\n' "${found[0]}"
}

# Super I/O のファン制御のチップ（nct6775 の系統と、nct6683 の系統）の name か
is_superio_name() { [[ "$1" =~ ^(nct6[0-9]{3}|nct5[0-9]{3})$ ]]; }

# "45:30 60:45" → 1行に「温度 PWM(0..255)」。温度は増え続けること、デューティは 0..100
curve_points() {
  local spec="$1" label="$2" item temp duty prev=-1
  [[ -n "$spec" ]] || return 0
  for item in $spec; do
    if [[ ! "$item" =~ ^([0-9]{1,3}):([0-9]{1,3})$ ]]; then
      die "$label の点が読めません: $item（「温度:デューティ%」を空白区切り。例 45:30）"
    fi
    temp=$((10#${BASH_REMATCH[1]}))
    duty=$((10#${BASH_REMATCH[2]}))
    ((duty <= 100)) || die "$label のデューティは 0..100: $item"
    ((temp > prev)) || die "$label の温度は増え続けること: $spec"
    prev=$temp
    printf '%d %d\n' "$temp" "$(((duty * 255 + 50) / 100))"
  done
}

# CASE_FAN_CHANNELS（"2 3" または "pwm:rpm" の "2:2 3:4"）→ 1行に「pwm rpm」
channel_pairs() {
  local item
  [[ -n "$CASE_FAN_CHANNELS" ]] || die "CASE_FAN_CHANNELS が空です（hosts/ubuntu/$UBUNTU_HOST.env。--probe の出力から決める）"
  for item in $CASE_FAN_CHANNELS; do
    if [[ "$item" =~ ^([1-9][0-9]?)$ ]]; then
      printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[1]}"
    elif [[ "$item" =~ ^([1-9][0-9]?):([1-9][0-9]?)$ ]]; then
      printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
      die "CASE_FAN_CHANNELS の値が読めません: $item（例: \"2 3\" や \"2:2\"）"
    fi
  done
}

# 設定の値と sysfs を確かめる。通れば fan_dir・pairs・gpu_points・cpu_points・min_pwm を決める
check_settings() {
  [[ -n "$CASE_FAN_HWMON" ]] || die "CASE_FAN_HWMON が空です（例: nct6799。--probe の出力の name）"
  [[ "$CASE_FAN_HWMON" =~ ^[a-z0-9_]+$ ]] || die "CASE_FAN_HWMON は hwmon の name そのもの（英小文字・数字・_）: $CASE_FAN_HWMON"
  if [[ ! "$CASE_FAN_MIN_DUTY" =~ ^[0-9]+$ ]] || ((CASE_FAN_MIN_DUTY < 10 || CASE_FAN_MIN_DUTY > 100)); then
    die "CASE_FAN_MIN_DUTY は 10..100: $CASE_FAN_MIN_DUTY"
  fi
  [[ -n "$CASE_FAN_GPU_CURVE" ]] || die "CASE_FAN_GPU_CURVE が空です"
  if [[ -n "$CASE_FAN_CPU_CURVE" ]]; then
    [[ "$CASE_FAN_CPU_HWMON" =~ ^[a-z0-9_]+$ ]] || die "CASE_FAN_CPU_HWMON が使えません: $CASE_FAN_CPU_HWMON"
    [[ "$CASE_FAN_CPU_TEMP_CHANNEL" =~ ^[1-9][0-9]?$ ]] || die "CASE_FAN_CPU_TEMP_CHANNEL が使えません: $CASE_FAN_CPU_TEMP_CHANNEL"
  fi

  local rc=0
  fan_dir="$(find_hwmon "$CASE_FAN_HWMON")" || rc=$?
  case "$rc" in
    0) ;;
    1) die "hwmon $CASE_FAN_HWMON が見つかりません（ドライバ $CASE_FAN_MODULE が掴めていない。--probe で確かめる）" ;;
    *) die "hwmon $CASE_FAN_HWMON が複数あります。どれを操るか決められないので止めます" ;;
  esac

  local out
  out="$(channel_pairs)" || exit 1
  mapfile -t pairs <<<"$out"
  local pair pwm rpm seen=" "
  for pair in "${pairs[@]}"; do
    read -r pwm rpm <<<"$pair"
    [[ "$seen" != *" $pwm "* ]] || die "CASE_FAN_CHANNELS に pwm$pwm が2回あります"
    seen+="$pwm "
    [[ -e "$fan_dir/pwm$pwm" && -e "$fan_dir/pwm${pwm}_enable" ]] ||
      die "$CASE_FAN_HWMON に pwm$pwm（と pwm${pwm}_enable）がありません"
    [[ -e "$fan_dir/fan${rpm}_input" ]] || die "$CASE_FAN_HWMON に fan${rpm}_input がありません"
  done

  if [[ -n "$CASE_FAN_CPU_CURVE" ]]; then
    local cpu_dir
    cpu_dir="$(find_hwmon "$CASE_FAN_CPU_HWMON")" || die "CPU の温度の hwmon $CASE_FAN_CPU_HWMON が1つに決まりません"
    [[ -e "$cpu_dir/temp${CASE_FAN_CPU_TEMP_CHANNEL}_input" ]] ||
      die "$CASE_FAN_CPU_HWMON に temp${CASE_FAN_CPU_TEMP_CHANNEL}_input がありません"
  fi

  out="$(curve_points "$CASE_FAN_GPU_CURVE" CASE_FAN_GPU_CURVE)" || exit 1
  mapfile -t gpu_points <<<"$out"
  [[ ${#gpu_points[@]} -ge 2 ]] || die "CASE_FAN_GPU_CURVE は2点以上"
  cpu_points=()
  if [[ -n "$CASE_FAN_CPU_CURVE" ]]; then
    out="$(curve_points "$CASE_FAN_CPU_CURVE" CASE_FAN_CPU_CURVE)" || exit 1
    mapfile -t cpu_points <<<"$out"
    [[ ${#cpu_points[@]} -ge 2 ]] || die "CASE_FAN_CPU_CURVE は2点以上"
  fi
  # fan2go 0.15.0 の線形の曲線は、最後の点より上では最後の値のまま。読めないときの ${GPU_FAILSAFE_C}℃ で全開にするには、
  # 最後の点が ${GPU_FAILSAFE_C}℃ より下で、かつ 100%（curve_points の丸めで 100% だけが 255 になる）であること。CPU の曲線には求めない
  local last_temp last_pwm
  read -r last_temp last_pwm <<<"${gpu_points[-1]}"
  ((GPU_FAILSAFE_C > last_temp)) || die "GPU の曲線の最後の温度（${last_temp}℃）は ${GPU_FAILSAFE_C}℃ より低くすること（読めないときに全開にするため）"
  ((last_pwm == 255)) || die "CASE_FAN_GPU_CURVE の最後の点は 100% にすること（いまは PWM ${last_pwm}/255）。GPU が読めないとき（${GPU_FAILSAFE_C}℃ を出す）に全開にするため"
  min_pwm=$(((CASE_FAN_MIN_DUTY * 255 + 50) / 100))
}

render_curve() {
  local id="$1" sensor="$2" point temp pwm
  shift 2
  printf '  - id: %s\n    linear:\n      sensor: %s\n      steps:\n' "$id" "$sensor"
  for point in "$@"; do
    read -r temp pwm <<<"$point"
    printf '        - %d: %d\n' "$temp" "$pwm"
  done
}

render_config() {
  local pair pwm rpm expected="${NVIDIA_EXPECTED_GPUS:-0}"
  [[ "$expected" =~ ^[0-9]+$ ]] || expected=0
  # ファンが指す曲線。fan2go 0.15.0 の function の曲線は 2 本以上が要るので、CPU の曲線がなければ GPU の曲線を直に指す
  local fan_curve=gpu_curve how="GPU の曲線（CPU の曲線なし）"
  if [[ ${#cpu_points[@]} -gt 0 ]]; then
    fan_curve=case_fans
    how="max(GPU の曲線, CPU の曲線)"
  fi
  cat <<EOF
# install-case-fan-control-ubuntu.sh が hosts/ubuntu/$UBUNTU_HOST.env（CASE_FAN_*）から書く。手で直さない（入れ直すと上書きされる）
# fan2go $FAN2GO_VERSION。ケースファン = $how。曲線の値は PWM（0..255）そのもの（useUnscaledCurveValues）
dbPath: /var/lib/fan2go/fan2go.db
runFanInitializationInParallel: false
# 温度は 1 秒ごとに読み、直近 10 回の平均で曲線を引く（GPU の温度の細かい上下でファンが揺れないように）
tempSensorPollingRate: 1s
tempRollingWindowSize: 10
rpmPollingRate: 1s
rpmRollingWindowSize: 10
fanController:
  adjustmentTickRate: 200ms

fans:
EOF
  for pair in "${pairs[@]}"; do
    read -r pwm rpm <<<"$pair"
    cat <<EOF
  - id: case_pwm$pwm
    hwmon:
      platform: $CASE_FAN_HWMON
      rpmChannel: $rpm
      pwmChannel: $pwm
    curve: $fan_curve
    # 止めない。最低は CASE_FAN_MIN_DUTY（$CASE_FAN_MIN_DUTY%）。初回の解析（PWM と RPM の関係を測る）の結果より、ここの値が勝つ
    neverStop: true
    minPwm: $min_pwm
    startPwm: $min_pwm
    maxPwm: 255
    pwmMap: identity
    setPwmToGetPwmMap: identity
    useUnscaledCurveValues: true
    # 1 回（200ms）に 3 まで動かす（0→255 に約 17 秒）
    controlAlgorithm:
      direct:
        maxPwmChangePerCycle: 3
    controlMode:
      active: pwm
      onExit: restore
EOF
  done
  cat <<EOF

sensors:
  # NVIDIA の GPU の温度の最大（ミリ度）。読めないとき・枚数が $expected 枚でないときは ${GPU_FAILSAFE_C}℃ を出す（全開）
  - id: gpu_max
    cmd:
      exec: $GPU_TEMP_BIN
      args: ['$expected', '$GPU_FAILSAFE_C']
EOF
  if [[ ${#cpu_points[@]} -gt 0 ]]; then
    cat <<EOF
  - id: cpu
    hwmon:
      platform: $CASE_FAN_CPU_HWMON
      channel: $CASE_FAN_CPU_TEMP_CHANNEL
EOF
  fi
  printf '\ncurves:\n'
  render_curve gpu_curve gpu_max "${gpu_points[@]}"
  if [[ ${#cpu_points[@]} -gt 0 ]]; then
    render_curve cpu_curve cpu "${cpu_points[@]}"
    printf '  - id: case_fans\n    function:\n      type: maximum\n      curves:\n        - gpu_curve\n        - cpu_curve\n'
  fi
  cat <<EOF

statistics:
  enabled: false
api:
  enabled: false
EOF
}

# --- 読むだけ ---------------------------------------------------------------

kernel_log() {
  # journalctl -k は adm / systemd-journal のグループなら読める。だめなら dmesg（root か dmesg_restrict=0）
  journalctl -k -b --no-pager -q -o short-monotonic 2>/dev/null || dmesg 2>/dev/null || return 1
}

# nct6775.ko の中の「ASUS の WMI 経由で読むボードの一覧」に、このボードの名前があるか（読むだけ）
board_in_nct6775_list() {
  local board="$1" file
  file="$(modinfo -n nct6775 2>/dev/null)" || { echo "不明（nct6775 のモジュールが見つからない）"; return; }
  local reader=(cat)
  case "$file" in
    *.zst)
      if ! command -v zstd >/dev/null; then
        echo "不明（zstd がない）"
        return
      fi
      reader=(zstd -dcq)
      ;;
    *.xz) reader=(xz -dc) ;;
  esac
  if "${reader[@]}" "$file" 2>/dev/null | tr '\0' '\n' | grep -qxF -- "$board"; then
    echo "ある（ACPI とぶつからずに WMI 経由で読める見込み）"
  else
    echo "ない（ISA を直に読みに行く。ACPI が握っていれば掴めない）"
  fi
}

list_hwmon() {
  local d name dev f n label
  for d in "$HWMON_ROOT"/hwmon*; do
    [[ -e "$d/name" ]] || continue
    name="$(read_value "$d/name")"
    dev="$(realpath "$d/device" 2>/dev/null || true)"
    echo "  $(basename "$d"): $name${dev:+  ($dev)}"
    for f in "$d"/temp*_input; do
      [[ -e "$f" ]] || continue
      n="${f##*/temp}"; n="${n%_input}"
      label="$(cat "$d/temp${n}_label" 2>/dev/null || true)"
      printf '    temp%s%s: %s℃\n' "$n" "${label:+ ($label)}" "$(awk '{ printf "%.1f", $1 / 1000 }' "$f" 2>/dev/null || echo '?')"
    done
    for f in "$d"/fan*_input; do
      [[ -e "$f" ]] || continue
      n="${f##*/fan}"; n="${n%_input}"
      printf '    fan%s: %s RPM\n' "$n" "$(read_value "$f")"
    done
    for f in "$d"/pwm[0-9]*; do
      [[ "$f" =~ /pwm[0-9]+$ ]] || continue
      n="${f##*/pwm}"
      printf '    pwm%s: %s/255  enable=%s  mode=%s\n' "$n" "$(read_value "$f")" \
        "$(read_value "$d/pwm${n}_enable")" "$(read_value "$d/pwm${n}_mode")"
    done
  done
}

probe() {
  local board vendor bios
  vendor="$(read_value /sys/class/dmi/id/board_vendor)"
  board="$(read_value /sys/class/dmi/id/board_name)"
  bios="$(read_value /sys/class/dmi/id/bios_version)"
  echo "== ボード・カーネル"
  echo "  $vendor / $board / BIOS $bios"
  echo "  カーネル $(uname -r)"
  if grep -qw 'acpi_enforce_resources=lax' /proc/cmdline; then
    echo "  起動オプション: acpi_enforce_resources=lax あり"
  else
    echo "  起動オプション: acpi_enforce_resources=lax なし"
  fi
  echo "  nct6775 の ASUS WMI のボード一覧に「$board」が: $(board_in_nct6775_list "$board")"
  echo "  ホストの設定: hosts/ubuntu/$UBUNTU_HOST.env（CASE_FAN_CONTROL=$CASE_FAN_CONTROL CASE_FAN_MODULE=$CASE_FAN_MODULE CASE_FAN_HWMON=${CASE_FAN_HWMON:-空} CASE_FAN_CHANNELS=${CASE_FAN_CHANNELS:-空} CASE_FAN_ACPI_LAX=$CASE_FAN_ACPI_LAX）"

  if "$load_module"; then
    echo
    echo "== $CASE_FAN_MODULE を一時的に読み込む（再起動で消える。ファンの制御は変えない）"
    if modprobe "$CASE_FAN_MODULE"; then
      ok "modprobe $CASE_FAN_MODULE"
    else
      ng "modprobe $CASE_FAN_MODULE が失敗した（チップが見つからない・ACPI とぶつかった。下のカーネルのログを見る）"
    fi
    sleep 1
  fi

  echo
  echo "== 読み込まれているドライバ"
  local m loaded=" "
  for m in nct6775 nct6775_core nct6683 asus_ec_sensors asus_wmi_sensors k10temp; do
    if grep -q "^$m " /proc/modules 2>/dev/null; then
      echo "  $m: 読み込み済み"
      loaded+="$m "
    else
      echo "  $m: なし"
    fi
  done

  echo
  echo "== hwmon（pwm の enable: 1=手動 2〜5=BIOS の自動 0=全開。mode: 1=PWM（4pin）0=DC（3pin））"
  list_hwmon

  local d name superio=()
  for d in "$HWMON_ROOT"/hwmon*; do
    name="$(read_value "$d/name")"
    is_superio_name "$name" && superio+=("$name")
  done

  echo
  echo "== カーネルのログ（Super I/O・ACPI のぶつかり）"
  local log hits conflict=false
  if log="$(kernel_log)"; then
    hits="$(grep -iE 'nct6775|nct6683|nct67[0-9]{2}|conflicts with OpRegion|resource conflict|acpi_enforce_resources' <<<"$log" | tail -20 || true)"
    if [[ -n "$hits" ]]; then
      # shellcheck disable=SC2001
      sed 's/^/  /' <<<"$hits"
      grep -qiE 'conflicts with OpRegion|resource conflict' <<<"$hits" && conflict=true
    else
      echo "  （該当なし）"
    fi
  else
    echo "  読めません（adm グループでないか、dmesg が root 限定）。--probe --load-module なら root で読む"
  fi

  echo
  echo "== NVIDIA GPU"
  if command -v nvidia-smi >/dev/null; then
    nvidia-smi --query-gpu=index,pci.bus_id,name,temperature.gpu,fan.speed,power.draw --format=csv,noheader 2>&1 | sed 's/^/  /'
    echo "  期待する枚数（NVIDIA_EXPECTED_GPUS）: $NVIDIA_EXPECTED_GPUS"
  else
    echo "  nvidia-smi がありません"
  fi
  if systemctl is-active --quiet nvidia-persistenced 2>/dev/null; then
    echo "  nvidia-persistenced: 動いている（nvidia-smi が速く返る）"
  else
    echo "  nvidia-persistenced: 動いていない（nvidia-smi が遅くなることがある）"
  fi

  echo
  echo "== fan2go"
  if [[ -x "$FAN2GO_BIN" ]]; then
    echo "  $FAN2GO_BIN: $("$FAN2GO_BIN" version 2>/dev/null || echo '?')、fan2go.service: $(systemctl is-active fan2go 2>/dev/null || true)"
    [[ -r "$STATUS_FILE" ]] && echo "  GPU の温度の最後の読み: $(cat "$STATUS_FILE")"
  else
    echo "  入っていない"
  fi
  if [[ -e /usr/lib/x86_64-linux-gnu/libsensors.so.5 ]]; then
    echo "  libsensors5: ある"
  else
    echo "  libsensors5: ない（入れるときに apt で入れる）"
  fi

  echo
  echo "== 見立て"
  if [[ ${#superio[@]} -gt 0 ]]; then
    local fan_capable=false
    for name in "${superio[@]}"; do
      d="$(find_hwmon "$name" 2>/dev/null || true)"
      if [[ -n "$d" ]] && compgen -G "$d/pwm[0-9]" >/dev/null; then
        fan_capable=true
        ok "Super I/O $name を掴めていて、pwm がある"
      else
        warn "Super I/O $name はあるが、pwm が出ていない（読むだけのドライバ。nct6683 なら ASUS のボードの制御はできない）"
      fi
    done
    if "$fan_capable"; then
      echo "  次: 上の fan の RPM で、ファンがつながっているチャネルを見る。どれが CPU_FAN かは --identify <チャネル> で確かめる（CPU_FAN は入れない）"
      echo "      hosts/ubuntu/$UBUNTU_HOST.env に CASE_FAN_HWMON=${superio[0]}、CASE_FAN_CHANNELS=\"<ケースファンの番号>\" を書く"
      if [[ ! -e "$MODULES_LOAD_FILE" ]]; then
        echo "      （いまの読み込みが一時的なら、再起動で消える。常に読み込む設定 $MODULES_LOAD_FILE は、入れるときにスクリプトが書く）"
      fi
    fi
  elif [[ "$loaded" != *" $CASE_FAN_MODULE "* && "$loaded" != *" nct6775 "* ]]; then
    warn "Super I/O のドライバ（$CASE_FAN_MODULE）が読み込まれていない（Ubuntu は自動では読み込まない）"
    echo "  次: $0 --probe --load-module   （一時的に読み込んでから、もう一度調べる。再起動で消える）"
  elif "$conflict" && ! grep -qw 'acpi_enforce_resources=lax' /proc/cmdline; then
    warn "nct6775 は読み込まれたが、ACPI が Super I/O の場所を握っていて掴めない。acpi_enforce_resources=lax が要りそう"
    echo "  lax は、ACPI（BIOS）と同じ I/O をドライバも触ることを許す（BIOS とドライバが同時に触ると読み違いが起きうる。広く使われている回避）"
    echo "  入れるなら: hosts/ubuntu/$UBUNTU_HOST.env に CASE_FAN_ACPI_LAX=1 → $0（GRUB を書き換える）→ 再起動 → --probe"
  else
    warn "ドライバは読み込まれたが、Super I/O が見つからない。ACPI のぶつかりもログにない"
    echo "  チップが nct6775 の系統でない見込み。nct6683（NCT6683/6686/6687）を試すなら: sudo modprobe nct6683 → --probe"
    echo "  （nct6683 は多くのボードで読むだけ。pwm が出なければ、このやり方ではケースファンを操れない）"
  fi
}

# --- 変更する ---------------------------------------------------------------

identify() {
  local ch="$identify_channel" dir enable pwm i n
  [[ -n "$CASE_FAN_HWMON" ]] || die "CASE_FAN_HWMON が空です（--probe の出力の Super I/O の name を env に書く）"
  dir="$(find_hwmon "$CASE_FAN_HWMON")" || die "hwmon $CASE_FAN_HWMON が1つに決まりません"
  [[ -e "$dir/pwm$ch" && -e "$dir/pwm${ch}_enable" ]] || die "$CASE_FAN_HWMON に pwm$ch がありません"
  if systemctl is-active --quiet fan2go 2>/dev/null; then
    die "fan2go が動いています。先に sudo systemctl stop fan2go（止めると BIOS の制御に戻る）"
  fi
  enable="$(cat "$dir/pwm${ch}_enable")"
  pwm="$(cat "$dir/pwm$ch")"
  # 何があっても元へ戻す
  # shellcheck disable=SC2064
  trap "printf '%s\n' '$pwm' > '$dir/pwm$ch' 2>/dev/null; printf '%s\n' '$enable' > '$dir/pwm${ch}_enable'; echo 'pwm$ch を元（enable=$enable）へ戻しました'" EXIT
  echo "pwm$ch を 10 秒だけ全開にします（元: enable=$enable pwm=$pwm）。どのファンの音が変わったかと、どの fan の RPM が上がったかを見る"
  echo 1 > "$dir/pwm${ch}_enable"
  echo 255 > "$dir/pwm$ch"
  for i in $(seq 1 10); do
    sleep 1
    printf '  %2ds:' "$i"
    for f in "$dir"/fan*_input; do
      n="${f##*/fan}"; n="${n%_input}"
      printf ' fan%s=%s' "$n" "$(read_value "$f")"
    done
    echo
  done
}

stop_fan2go() {
  if systemctl is-active --quiet fan2go 2>/dev/null; then
    echo "fan2go を止めます（BIOS の制御に戻る）"
    systemctl stop fan2go
  fi
}

set_grub_lax() {
  local want="$1"
  if [[ "$want" == 1 ]]; then
    if [[ ! -f "$GRUB_DROPIN" ]]; then
      install -d -m 0755 /etc/default/grub.d
      # GRUB の側で展開させるので、$ はそのまま書く
      # shellcheck disable=SC2016
      printf '%s\n%s\n' \
        "# install-case-fan-control-ubuntu.sh が書く（hosts/ubuntu/$UBUNTU_HOST.env の CASE_FAN_ACPI_LAX=1）。Super I/O（$CASE_FAN_MODULE）を ACPI と同時に触ることを許す" \
        'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT acpi_enforce_resources=lax"' > "$GRUB_DROPIN"
      chmod 0644 "$GRUB_DROPIN"
      update-grub
      echo "GRUB に acpi_enforce_resources=lax を足しました（$GRUB_DROPIN）"
    fi
  elif [[ -f "$GRUB_DROPIN" ]]; then
    rm -f -- "$GRUB_DROPIN"
    update-grub
    echo "GRUB から acpi_enforce_resources=lax を外しました（次の起動から）"
  fi
}

install_fan2go_binary() {
  if [[ -x "$FAN2GO_BIN" ]] && printf '%s  %s\n' "$FAN2GO_SHA256" "$FAN2GO_BIN" | sha256sum --check --status; then
    return
  fi
  local work
  work="$(mktemp -d)"
  curl --fail --location --retry 3 --output "$work/fan2go" "$FAN2GO_URL"
  printf '%s  %s\n' "$FAN2GO_SHA256" "$work/fan2go" | sha256sum --check --status ||
    { rm -rf -- "$work"; die "fan2go の SHA256 が合いません"; }
  install -o root -g root -m 0755 "$work/fan2go" "$FAN2GO_BIN"
  rm -rf -- "$work"
}

# 今の pwmN_enable を「BIOS の制御」として記録する。fan2go が止まっている状態で読む
write_restore_conf() {
  local pair pwm enable old lines=()
  for pair in "${pairs[@]}"; do
    read -r pwm _ <<<"$pair"
    enable="$(cat "$fan_dir/pwm${pwm}_enable")"
    if [[ "$enable" == 1 ]]; then
      # 手動のまま残っている。前に記録した値があればそれを使う
      old="$(awk -v n="$CASE_FAN_HWMON" -v c="$pwm" '$1 == n && $2 == c { print $3 }' "$RESTORE_CONF" 2>/dev/null || true)"
      [[ -n "$old" && "$old" != 1 ]] ||
        die "pwm$pwm が手動（enable=1）のままで、BIOS の値が分かりません。再起動して BIOS の制御に戻してから入れ直す"
      enable="$old"
    fi
    lines+=("$CASE_FAN_HWMON $pwm $enable")
  done
  {
    echo "# install-case-fan-control-ubuntu.sh が書く。<hwmon の name> <pwm のチャネル> <BIOS の pwmN_enable>"
    printf '%s\n' "${lines[@]}"
  } > "$RESTORE_CONF.tmp"
  chmod 0644 "$RESTORE_CONF.tmp"
  mv -f "$RESTORE_CONF.tmp" "$RESTORE_CONF"
}

# 設定を一時のファイルに書き、fan2go が受け付けたときだけ置き換える。失敗・中断で一時のファイルを残さない
write_config() {
  # 前の実行で残ったものがあっても、作り直す（root 所有・0644 にするため）
  rm -f -- "$CONFIG_NEW"
  # shellcheck disable=SC2064
  trap "rm -f -- '$CONFIG_NEW'" EXIT
  render_config > "$CONFIG_NEW"
  chmod 0644 "$CONFIG_NEW"
  if ! "$FAN2GO_BIN" -c "$CONFIG_NEW" --no-style config validate; then
    die "fan2go が設定を受け付けませんでした。何も起動していません（BIOS の制御のまま）"
  fi
  mv -f -- "$CONFIG_NEW" "$CONFIG_FILE"
  trap - EXIT
}

do_install() {
  if [[ "$CASE_FAN_CONTROL" != 1 ]]; then
    echo "ケースファンの制御は切ってあります（hosts/ubuntu/$UBUNTU_HOST.env の CASE_FAN_CONTROL=$CASE_FAN_CONTROL）。何も変えていません。"
    echo "まず $0 --probe で調べ、値を決めてから CASE_FAN_CONTROL=1 にする。外すのは --uninstall"
    exit 0
  fi
  # shellcheck source=/dev/null
  source /etc/os-release
  [[ "$ID" == ubuntu && "$(uname -m)" == x86_64 ]] || die "このスクリプトはUbuntu x86_64専用です"
  [[ "$CASE_FAN_MODULE" =~ ^[a-z0-9_]+$ ]] || die "CASE_FAN_MODULE が使えません: $CASE_FAN_MODULE"

  # Super I/O のドライバを起動のたびに読み込む
  printf '# install-case-fan-control-ubuntu.sh が書く（ケースファンの制御）\n%s\n' "$CASE_FAN_MODULE" > "$MODULES_LOAD_FILE"
  chmod 0644 "$MODULES_LOAD_FILE"

  set_grub_lax "$CASE_FAN_ACPI_LAX"
  if [[ "$CASE_FAN_ACPI_LAX" == 1 ]] && ! grep -qw 'acpi_enforce_resources=lax' /proc/cmdline; then
    echo "acpi_enforce_resources=lax は次の起動から効きます。再起動してから、--probe で pwm が見えるのを確かめ、もう一度このスクリプトを流す。"
    exit 0
  fi
  modprobe "$CASE_FAN_MODULE" || true

  check_settings

  if ! dpkg-query -W -f='${db:Status-Abbrev}' libsensors5 2>/dev/null | grep -q '^ii'; then
    apt-get update
    apt-get install -y libsensors5
  fi
  [[ -x /usr/bin/nvidia-smi ]] || warn "nvidia-smi がありません。GPU の温度は読めず、ケースファンは全開になります"

  stop_fan2go
  install_fan2go_binary
  # cmd センサーの実行ファイルは root だけが書ける場所・権限に置く（fan2go がそれ以外を拒む）
  install -o root -g root -m 0755 "$SCRIPT_DIR/case-fan-gpu-temp.sh" "$GPU_TEMP_BIN"
  install -o root -g root -m 0755 "$SCRIPT_DIR/case-fan-restore-bios.sh" "$RESTORE_BIN"
  install -d -o root -g root -m 0755 "$CONFIG_DIR"
  write_restore_conf

  write_config

  install -m 0644 "$REPO_DIR/systemd/fan2go.service" "$UNIT_FILE"
  systemctl daemon-reload
  systemctl enable fan2go.service
  systemctl restart fan2go.service

  echo "15 秒待って、状態を読みます"
  sleep 15
  systemctl --no-pager --full status fan2go.service || true
  if [[ -r "$STATUS_FILE" ]]; then
    echo "GPU の温度の最後の読み: $(cat "$STATUS_FILE")"
    grep -q ' failsafe ' "$STATUS_FILE" &&
      warn "GPU の温度が読めず、全開側に倒れています。理由は上の行。journalctl -u fan2go も見る"
  else
    warn "GPU の温度の状態（$STATUS_FILE）がまだありません。journalctl -u fan2go を見る"
  fi
  local pair pwm rpm
  for pair in "${pairs[@]}"; do
    read -r pwm rpm <<<"$pair"
    echo "pwm$pwm: $(read_value "$fan_dir/pwm$pwm")/255 enable=$(read_value "$fan_dir/pwm${pwm}_enable")  fan$rpm: $(read_value "$fan_dir/fan${rpm}_input") RPM"
  done
  echo "ケースファンの制御を入れました。止めると BIOS の制御に戻ります（sudo systemctl stop fan2go）。外すのは --uninstall"
}

do_uninstall() {
  if [[ -f "$UNIT_FILE" ]]; then
    systemctl disable --now fan2go.service || true
  fi
  # unit がなくても、記録があれば BIOS の制御へ戻す
  if [[ -x "$RESTORE_BIN" && -f "$RESTORE_CONF" ]]; then
    "$RESTORE_BIN" || true
  fi
  rm -f -- "$UNIT_FILE" "$CONFIG_FILE" "$CONFIG_NEW" "$RESTORE_CONF" "$FAN2GO_BIN" "$GPU_TEMP_BIN" "$RESTORE_BIN" "$MODULES_LOAD_FILE"
  rmdir "$CONFIG_DIR" 2>/dev/null || true
  rm -rf -- /var/lib/fan2go
  systemctl daemon-reload
  set_grub_lax 0
  echo "ケースファンの制御を外し、BIOS の制御に戻しました。$CASE_FAN_MODULE の読み込みは、次の起動からされません。"
  echo "hosts/ubuntu/$UBUNTU_HOST.env の CASE_FAN_CONTROL も 0 にしておく（入れ直しで戻らないように）"
}

case "$mode" in
  probe) probe ;;
  print-config) check_settings; render_config ;;
  test-write-config) check_settings; write_config ;;
  identify) identify ;;
  install) do_install ;;
  uninstall) do_uninstall ;;
esac
