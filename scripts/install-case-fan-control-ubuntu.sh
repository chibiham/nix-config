#!/usr/bin/env bash
# ケースファンを GPU の温度（と CPU の温度）に合わせて回す。道具は fan2go（公式の配布バイナリを版とハッシュで固定）。
# 値はホストの設定（hosts/ubuntu/<ホスト名>.env の CASE_FAN_*）から決める。既定は切（CASE_FAN_CONTROL=0）。
#
#   install-case-fan-control-ubuntu.sh --probe                 # 読むだけ（sudo 不要）。ドライバ・pwm・fan・温度を出し、env の値の手がかりを出す
#   install-case-fan-control-ubuntu.sh --probe --load-module   # Super I/O のドライバ（CASE_FAN_MODULE）を一時的に読み込んでから調べる（sudo。再起動で消える。ファンは変えない）
#   install-case-fan-control-ubuntu.sh --identify <チャネル>   # そのチャネルを 10 秒だけ全開にして RPM を見せ、元に戻す（sudo。どのファンがどれかを見分ける。CASE_FAN_HWMON が空なら、pwm のある Super I/O が 1 つのときそれを使う）
#   install-case-fan-control-ubuntu.sh --identify <チャネル> --stop [--allow-pump]   # 全開の代わりに 10 秒だけ止める（pwm=0）。BIOS の曲線が全点 255・BIOS が全開（enable=0）のチャネル（ポンプなど）は --allow-pump がないと断る
#   install-case-fan-control-ubuntu.sh --print-config          # 書く予定の /etc/fan2go/fan2go.yaml を出すだけ（sudo 不要）
#   install-case-fan-control-ubuntu.sh                         # 入れる・入れ直す（sudo）
#   install-case-fan-control-ubuntu.sh --uninstall             # 外して BIOS の制御へ戻す（sudo）
#
# 落ちたとき・止めたときは、fan2go 自身（controlMode.onExit: restore）と unit の ExecStopPost
# （case-fan-restore-bios）が BIOS の制御へ戻す。GPU の温度が読めないときは全開側に倒す（case-fan-gpu-temp）。
# CASE_FAN_RAD_CHANNELS があれば、CPU の簡易水冷のラジエーターのファンを別の曲線（max(GPU, CPU[, CPU の保険])）で回す。
# その CPU の曲線は BIOS の曲線より弱くしない（BIOS と同じ温度の源なら、sysfs の BIOS の曲線と比べて、弱い所があれば止まる）。
# BIOS のモード（戻し先の pwmN_enable。いま 1 なら case-fan-restore.conf の記録）が全開（0）・SmartFan IV（5）でない・分からないチャネルも止まる。
# --identify は、元へ戻せなかったら（pwm・enable の書き戻しの失敗、読み戻しの食い違い）手で戻すコマンドを出し、0 でない終了コードで終わる。
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
# ラジエーターの組の比べで、BIOS のモード（pwmN_enable）を引く記録。下の試験の入口でだけ差し替わる
BIOS_MODE_RECORD=$RESTORE_CONF
UNIT_FILE=/etc/systemd/system/fan2go.service
MODULES_LOAD_FILE=/etc/modules-load.d/case-fan-control.conf
GRUB_DROPIN=/etc/default/grub.d/60-case-fan-acpi-lax.cfg
STATUS_FILE=/run/fan2go/case-fan-gpu-temp.status
# GPU の温度が読めないときに出す温度（℃）。曲線の最大の温度より高くして、全開にする
GPU_FAILSAFE_C=100

SCRIPT_DIR="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  sed -n '2,11p' "$(realpath "${BASH_SOURCE[0]}")" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

mode=install
load_module=false
identify_channel=""
identify_stop=false
allow_pump=false
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
    [[ "$identify_channel" =~ ^[0-9]+$ ]] || usage
    # 形は --identify <N> / --identify <N> --stop / --identify <N> --stop --allow-pump だけ
    case "$#:${3:-}:${4:-}" in
      2::) ;;
      3:--stop:) identify_stop=true ;;
      4:--stop:--allow-pump) identify_stop=true; allow_pump=true ;;
      *) usage ;;
    esac
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
  # 試験だけ: BIOS の pwmN_enable の記録（case-fan-restore.conf）を CASE_FAN_TEST_CONFIG_DIR に書く（sudo 不要）
  --test-write-restore-conf)
    mode=test-write-restore-conf
    [[ $# -eq 1 && -n "${CASE_FAN_TEST_CONFIG_DIR:-}" ]] || usage
    RESTORE_CONF=$CASE_FAN_TEST_CONFIG_DIR/case-fan-restore.conf
    ;;
  *) usage ;;
esac

# 試験だけ: CASE_FAN_HWMON_ROOT が /sys の外（にせの hwmon の木）を指しているときは、--identify を sudo なしで動かす。
# /sys の下（本物）・空・ないパスなら今までどおり sudo で起動し直す（sudo 越しでは CASE_FAN_HWMON_ROOT は落ちる）
fake_hwmon_root=false
if [[ -n "${CASE_FAN_HWMON_ROOT:-}" ]]; then
  fake_real="$(realpath -e -- "$CASE_FAN_HWMON_ROOT" 2>/dev/null || true)"
  if [[ -n "$fake_real" && "$fake_real" != /sys && "$fake_real" != /sys/* ]]; then
    fake_hwmon_root=true
  fi
  unset fake_real
fi
# 試験だけ: にせの木のときは、BIOS のモードの記録に本物の /etc/fan2go を読まない（CASE_FAN_TEST_CONFIG_DIR があればその中、なければ記録なし）。
# 本物の木では差し替えを受け付けない（--test-write-* は今までどおり書く先だけを差し替え、記録は本物を読む）
if "$fake_hwmon_root"; then
  BIOS_MODE_RECORD=""
  [[ -z "${CASE_FAN_TEST_CONFIG_DIR:-}" ]] || BIOS_MODE_RECORD=$CASE_FAN_TEST_CONFIG_DIR/case-fan-restore.conf
elif [[ -n "${CASE_FAN_TEST_CONFIG_DIR:-}" && "$mode" != test-write-* ]]; then
  echo "CASE_FAN_TEST_CONFIG_DIR は、にせの hwmon の木（CASE_FAN_HWMON_ROOT が /sys の外）の試験のときだけ使えます" >&2
  exit 1
fi

needs_root=false
case "$mode" in
  install | uninstall) needs_root=true ;;
  identify) if ! "$fake_hwmon_root"; then needs_root=true; fi ;;
  probe) if "$load_module"; then needs_root=true; fi ;;
esac
# --print-config は試験のため Linux でなくても動く
if [[ "$mode" != print-config && "$mode" != test-write-config && "$mode" != test-write-restore-conf && "$(uname -s)" != Linux ]]; then
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

# --identify が操る hwmon を決め、id_dir・id_name・id_how を決める。決まらなければ理由を id_why に入れて 1 で返る。
# CASE_FAN_HWMON が書いてあればその name。空なら、Super I/O の name で pwm のある hwmon がちょうど 1 つのときそれ（env に書く前に使うため）
pick_identify_hwmon() {
  id_dir="" id_name="" id_how="" id_why=""
  if [[ -n "$CASE_FAN_HWMON" ]]; then
    id_dir="$(find_hwmon "$CASE_FAN_HWMON")" || { id_why="hwmon $CASE_FAN_HWMON が1つに決まりません"; return 1; }
    id_name=$CASE_FAN_HWMON
    id_how="hosts/ubuntu/$UBUNTU_HOST.env の CASE_FAN_HWMON"
    return 0
  fi
  local d name found=() listed=()
  for d in "$HWMON_ROOT"/hwmon*; do
    name="$(read_value "$d/name")"
    is_superio_name "$name" || continue
    if compgen -G "$d/pwm[0-9]" >/dev/null; then
      found+=("$d")
      listed+=("$(basename "$d"): $name")
    else
      listed+=("$(basename "$d"): $name（pwm なし）")
    fi
  done
  if [[ ${#found[@]} -eq 1 ]]; then
    id_dir=${found[0]}
    id_name="$(read_value "$id_dir/name")"
    id_how="CASE_FAN_HWMON が空なので、pwm のある Super I/O から選んだ"
    return 0
  fi
  if [[ ${#found[@]} -eq 0 ]]; then
    id_why="CASE_FAN_HWMON が空で、pwm のある Super I/O の hwmon がありません（見つかった Super I/O: ${listed[*]:-なし}）。$0 --probe --load-module で調べる"
  else
    id_why="CASE_FAN_HWMON が空で、pwm のある Super I/O の hwmon が ${#found[@]} 個あります（${listed[*]}）。どれを操るか決められないので、hosts/ubuntu/$UBUNTU_HOST.env に CASE_FAN_HWMON を書く"
  fi
  return 1
}

# --identify --stop の守り: hwmon $1 の pwm$2 が、ポンプと見られるか。BIOS の自動の曲線（pwmN_auto_pointM_pwm。あるものを全部）が
# 全点 255 ならポンプ（止めると CPU が冷えなくなる）。pump_why に理由を入れる。
# 返り値: 0 = ポンプと見られる、1 = 見られない、2 = 曲線のファイルがなく判定できない、3 = 曲線が読めず判定できない
pump_check() {
  local dir="$1" ch="$2" f v vals=() n=0
  pump_why=""
  for f in "$dir/pwm${ch}_auto_point"[0-9]*_pwm; do
    [[ -e "$f" ]] || continue
    n=$((n + 1))
    v="$(cat "$f" 2>/dev/null)" || v=""
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      pump_why="$(basename "$f") が読めません"
      return 3
    fi
    vals+=("$v")
  done
  if ((n == 0)); then
    pump_why="pwm${ch}_auto_point*_pwm がありません"
    return 2
  fi
  pump_why="BIOS の曲線 pwm${ch}_auto_point*_pwm = ${vals[*]}"
  for v in "${vals[@]}"; do
    ((v == 255)) || return 1
  done
  return 0
}

# --identify --stop が断るか。断るなら 0 で返り、guard_why（文）と guard_short（--probe の短い理由）を入れる。
# 断るのは、曲線が全点 255（pump_check が 0）・曲線が読めない（3）・BIOS が全開にしている（いまの enable=0）のどれか。
# guard_nocurve は曲線のファイルがなく判定できない（pump_check が 2）とき true
stop_guard() {
  local dir="$1" ch="$2" rc=0 why=() short=()
  guard_why="" guard_short="" guard_nocurve=false
  pump_check "$dir" "$ch" || rc=$?
  case "$rc" in
    0) why+=("ポンプと見られる（$pump_why）"); short+=("BIOS の曲線が全点 255") ;;
    2) guard_nocurve=true ;;
    3) why+=("ポンプかどうか判定できない（$pump_why）"); short+=("曲線が読めない") ;;
  esac
  if [[ "$(read_value "$dir/pwm${ch}_enable")" == 0 ]]; then
    why+=("BIOS が全開にしている（enable=0）。ポンプなど、止めてはいけないものの見込み")
    short+=("BIOS が全開 enable=0")
  fi
  [[ ${#why[@]} -gt 0 ]] || return 1
  # 「、」でつなぐ（IFS は 1 バイトしか使えないことがあるので、自分でつなぐ）
  local i
  guard_why=${why[0]} guard_short=${short[0]}
  for ((i = 1; i < ${#why[@]}; i++)); do
    guard_why+="、${why[i]}"
    guard_short+="、${short[i]}"
  done
  return 0
}

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

# CASE_FAN_CHANNELS（"2 3" または "pwm:rpm" の "2:2 3:4"）→ 1行に「pwm rpm」。
# $1 は変数の名前（メッセージ用）、$2 は値（省けば CASE_FAN_CHANNELS）
channel_pairs() {
  local label="${1:-CASE_FAN_CHANNELS}" value="${2-$CASE_FAN_CHANNELS}" item
  [[ -n "$value" ]] || die "$label が空です（hosts/ubuntu/$UBUNTU_HOST.env。--probe の出力から決める）"
  for item in $value; do
    if [[ "$item" =~ ^([1-9][0-9]?)$ ]]; then
      printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[1]}"
    elif [[ "$item" =~ ^([1-9][0-9]?):([1-9][0-9]?)$ ]]; then
      printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
      die "$label の値が読めません: $item（例: \"2 3\" や \"2:2\"）"
    fi
  done
}

# 曲線（curve_points の出力の配列の名前 $1）を確かめる: 2 点以上、最後の点が 100%（255）。
# $2 は変数の名前、$3 は 100% を求める理由。$4 が空でなければ、最後の温度が GPU_FAILSAFE_C より下であることも求める
check_curve_shape() {
  local -n _pts="$1"
  local label="$2" reason="$3" gpu="${4:-}" last_temp last_pwm
  [[ ${#_pts[@]} -ge 2 ]] || die "$label は2点以上"
  read -r last_temp last_pwm <<<"${_pts[-1]}"
  if [[ -n "$gpu" ]]; then
    ((GPU_FAILSAFE_C > last_temp)) || die "$label の最後の温度（${last_temp}℃）は ${GPU_FAILSAFE_C}℃ より低くすること（読めないときに全開にするため）"
  fi
  ((last_pwm == 255)) || die "$label の最後の点は 100% にすること（いまは PWM ${last_pwm}/255）。$reason"
}

# hwmon の name $2 の temp$3_input があるか（$1 は変数の名前の頭。メッセージ用）
check_temp_source() {
  local label="$1" name="$2" ch="$3" dir
  [[ "$name" =~ ^[a-z0-9_]+$ ]] || die "${label}_HWMON が使えません: ${name:-空}"
  [[ "$ch" =~ ^[1-9][0-9]?$ ]] || die "${label}_TEMP_CHANNEL が使えません: ${ch:-空}"
  dir="$(find_hwmon "$name")" || die "${label}_HWMON の hwmon $name が1つに決まりません"
  [[ -e "$dir/temp${ch}_input" ]] || die "$name に temp${ch}_input がありません（${label}_TEMP_CHANNEL）"
}

# hwmon の dir $1 の pwm$2 の「BIOS のモード」（fan2go が止まったときに戻る pwmN_enable）を決める。
# いまの値が 1 以外ならそれ。1（fan2go が操っている・手動のまま）なら、記録（BIOS_MODE_RECORD。<name> <チャネル> <enable> の行。
# 同じチャネルが何行もあれば最後の行。case-fan-restore-bios は上から順に書くので最後が効く）の値。記録がない・1 なら空（分からない）。
# bios_mode に値（分からなければ空）、bios_mode_from に出所の文を入れる
rad_bios_mode() {
  local dir="$1" ch="$2" now rec=""
  bios_mode="" bios_mode_from=""
  now="$(cat "$dir/pwm${ch}_enable" 2>/dev/null)" || now=""
  if [[ ! "$now" =~ ^[0-9]+$ ]]; then
    bios_mode_from="pwm${ch}_enable が読めない（${now:-空}）"
    return 0
  fi
  if [[ "$now" != 1 ]]; then
    bios_mode=$now bios_mode_from="いまの値"
    return 0
  fi
  if [[ -n "$BIOS_MODE_RECORD" ]]; then
    rec="$(awk -v n="$CASE_FAN_HWMON" -v c="$ch" '$1 == n && $2 == c { v = $3 } END { print v }' "$BIOS_MODE_RECORD" 2>/dev/null || true)"
  fi
  if [[ "$rec" =~ ^[0-9]+$ && "$rec" != 1 ]]; then
    bios_mode=$rec bios_mode_from="いまは pwm${ch}_enable=1 なので、$BIOS_MODE_RECORD の記録"
  fi
}

# BIOS の曲線と、こちらの CPU の曲線（"温度 PWM" の行。$3 以降）を比べる。hwmon の dir $1 の pwm$2 について。
# まず BIOS のモード（rad_bios_mode）を見る: 5（SmartFan IV）だけ曲線を比べる。0（全開）・ほかの値・分からないときは止まる
# （全開はどの温度でも 255 なので、fan2go で操れば必ず弱くなる。ほかのモードは auto_point の曲線を使わず、比べるものがない）。
# BIOS の曲線は pwmN_auto_pointM_temp（ミリ度）・_pwm（あるものを全部）。点の間は直線、最初の点より下は最初の値、
# 最後の点より上は最後の値。BIOS の曲線は同じ温度に点が複数あってよい（段差）: その温度ちょうどでは、その温度の点の
# PWM の最大（段差の左右の高いほう。端の点でも同じ）。点の間は、すぐ左の点（同じ温度が複数あれば最後）とすぐ右の点
# （同じ温度が複数あれば最初）の直線。こちらの曲線は温度が増え続ける（curve_points）ので段差はない。
# 両方の点の温度で区切った区間の中では、2 本とも直線なので、差の最小は区間の端（の極限）で出る。段差の温度での
# BIOS の左右の極限はどちらもその温度の点の最大以下で、こちらの曲線は連続なので、点の温度の全部で最大と比べれば足りる。
# cmp_msg に結果の文を入れる。
# 返り値: 0 = どこでも BIOS 以上、1 = 弱い所がある、2 = 比べられない（源が違う・曲線のファイルがない）、3 = BIOS の曲線が読めない、
# 4 = BIOS のモードのせいで入れられない（全開・SmartFan IV でない・分からない）
rad_bios_compare() {
  local dir="$1" ch="$2" sel f m t p bios=() n=0 mode_text
  shift 2
  cmp_msg=""
  # BIOS のモードは、温度の源の比べより先に見る（源が違っても、全開のチャネルは入れない）
  rad_bios_mode "$dir" "$ch"
  case "$bios_mode" in
    5) mode_text="SmartFan IV（pwm${ch}_enable=5。$bios_mode_from）" ;;
    0)
      cmp_msg="BIOS が全開にしている（pwm${ch}_enable=0。$bios_mode_from）チャネルは、ラジエーターの組に入れられない（fan2go で操ると必ず BIOS より弱くなる）。BIOS の設定を自動（SmartFan）に変えるか、組から外す"
      return 4
      ;;
    "")
      if [[ -n "$bios_mode_from" ]]; then
        cmp_msg="$bios_mode_from ので、BIOS のモードが分からない。弱くならないと確かめられないので止める"
      else
        cmp_msg="いまは手動（pwm${ch}_enable=1）で、BIOS のモードの記録がない（${BIOS_MODE_RECORD:-記録の場所なし}）。弱くならないと確かめられないので止める。fan2go を止めて BIOS の制御に戻す（再起動）か、記録を確かめる"
      fi
      return 4
      ;;
    *)
      cmp_msg="BIOS の制御が SmartFan IV（5）でない（pwm${ch}_enable=$bios_mode。$bios_mode_from）ので、曲線を比べられない（2 = Thermal Cruise・3 = Fan Speed Cruise・4 = SmartFan III は auto_point の曲線を使わない）。弱くならないと確かめられないので止める"
      return 4
      ;;
  esac
  if [[ "$CASE_FAN_RAD_CPU_HWMON" != "$CASE_FAN_HWMON" ]]; then
    cmp_msg="CPU の温度の源（$CASE_FAN_RAD_CPU_HWMON の temp$CASE_FAN_RAD_CPU_TEMP_CHANNEL）が BIOS の側の hwmon（$CASE_FAN_HWMON）と違うので、BIOS の曲線とは比べられません"
    return 2
  fi
  sel="$(cat "$dir/pwm${ch}_temp_sel" 2>/dev/null)" || sel=""
  if [[ ! "$sel" =~ ^[0-9]+$ ]]; then
    cmp_msg="pwm${ch}_temp_sel が読めず、BIOS の温度の源が分からないので、BIOS の曲線とは比べられません"
    return 2
  fi
  if [[ "$sel" != "$CASE_FAN_RAD_CPU_TEMP_CHANNEL" ]]; then
    cmp_msg="BIOS の温度の源は temp$sel（pwm${ch}_temp_sel）で、CASE_FAN_RAD_CPU_TEMP_CHANNEL（temp$CASE_FAN_RAD_CPU_TEMP_CHANNEL）と違うので、BIOS の曲線とは比べられません"
    return 2
  fi
  for f in "$dir/pwm${ch}_auto_point"[0-9]*_pwm; do
    [[ -e "$f" ]] || continue
    [[ "$f" =~ _auto_point([0-9]+)_pwm$ ]] || continue
    m=${BASH_REMATCH[1]}
    p="$(cat "$f" 2>/dev/null)" || p=""
    t="$(cat "$dir/pwm${ch}_auto_point${m}_temp" 2>/dev/null)" || t=""
    if [[ ! "$p" =~ ^[0-9]+$ || ! "$t" =~ ^-?[0-9]+$ ]]; then
      cmp_msg="BIOS の曲線の点 $m（pwm${ch}_auto_point${m}_temp・_pwm）が読めません（temp=${t:-?} pwm=${p:-?}）"
      return 3
    fi
    bios+=("$m $t $p")
    n=$((n + 1))
  done
  if ((n == 0)); then
    cmp_msg="BIOS の曲線（pwm${ch}_auto_point*_temp・_pwm）がないので、BIOS の曲線とは比べられません"
    return 2
  fi
  local result rc=0
  # 点の番号の順に並べ（glob は文字の順なので 10 が 2 より前に来る）、温度はミリ度のまま、こちらの温度は ×1000 で比べる
  result="$(printf '%s\n' "${bios[@]}" | sort -n -k1,1 | awk -v ours="$(printf '%s;' "$@")" '
    # こちらの曲線（温度が増え続ける）
    function ev(k, T, P, x,   i) {
      if (x <= T[1]) return P[1]
      for (i = 2; i <= k; i++)
        if (x <= T[i]) return P[i-1] + (P[i] - P[i-1]) * (x - T[i-1]) / (T[i] - T[i-1])
      return P[k]
    }
    # 温度 y の点の PWM の最大
    function top(k, T, P, y,   i, v) {
      v = -1
      for (i = 1; i <= k; i++) if (T[i] == y && P[i] > v) v = P[i]
      return v
    }
    # BIOS の曲線（同じ温度の点が複数あってよい。上の説明のとおり安全側に）
    function evb(k, T, P, x,   i) {
      if (x <= T[1]) return top(k, T, P, T[1])
      if (x >= T[k]) return top(k, T, P, T[k])
      for (i = 1; i <= k; i++) if (T[i] == x) return top(k, T, P, x)
      # T[i] < x < T[i+1] になる i（i は温度 T[i] の点の最後、i+1 は温度 T[i+1] の点の最初）
      for (i = 1; i < k; i++)
        if (T[i] < x && x < T[i+1]) return P[i] + (P[i+1] - P[i]) * (x - T[i]) / (T[i+1] - T[i])
      return top(k, T, P, T[k])
    }
    function fmt(v) { v = sprintf("%.1f", v); sub(/\.0$/, "", v); return v }
    { nb++; BT[nb] = $2; BP[nb] = $3
      if (nb > 1 && BT[nb] < BT[nb-1]) { print "BIOS の曲線の温度が増えていません（点 " $1 "）"; err = 1; exit 3 } }
    END {
      if (err || nb == 0) exit 3
      no = split(ours, items, ";")
      k = 0
      for (i = 1; i <= no; i++) if (items[i] != "") { split(items[i], a, " "); k++; OT[k] = a[1] * 1000; OP[k] = a[2] }
      for (i = 1; i <= nb; i++) X[++nx] = BT[i]
      for (i = 1; i <= k; i++) X[++nx] = OT[i]
      bad = ""
      for (i = 1; i <= nx; i++) {
        x = X[i]
        if (x in seen) continue
        seen[x] = 1; nu++
        b = evb(nb, BT, BP, x); o = ev(k, OT, OP, x)
        if (o < b - 1e-9) bad = bad (bad == "" ? "" : "、") fmt(x / 1000) "℃ で BIOS " fmt(b) "、こちら " fmt(o)
      }
      if (bad != "") { print bad; exit 1 }
      print nu
    }')" || rc=$?
  case "$rc" in
    0) cmp_msg="CASE_FAN_RAD_CPU_CURVE は、BIOS の曲線（temp$sel。${n} 点）より弱い所がない（BIOS のモード: $mode_text。両方の点の温度 $result か所で比べた）" ;;
    1) cmp_msg="CASE_FAN_RAD_CPU_CURVE が BIOS の曲線（temp$sel）より弱い所があります: $result（PWM 0..255）" ;;
    *) cmp_msg="BIOS の曲線が読めません: ${result:-pwm${ch}_auto_point*}"; return 3 ;;
  esac
  return "$rc"
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
  check_rad_settings
}

# ラジエーターの組（CASE_FAN_RAD_*）を確かめる。通れば rad_pairs・rad_gpu_points・rad_cpu_points・rad_backup_points・rad_min_pwm を決める。
# CASE_FAN_RAD_CHANNELS が空なら、どれも空のまま（設定はケースファンだけ）
check_rad_settings() {
  rad_pairs=() rad_gpu_points=() rad_cpu_points=() rad_backup_points=() rad_min_pwm=""
  [[ -n "$CASE_FAN_RAD_CHANNELS" ]] || return 0
  if [[ ! "$CASE_FAN_RAD_MIN_DUTY" =~ ^[0-9]+$ ]] || ((CASE_FAN_RAD_MIN_DUTY < 10 || CASE_FAN_RAD_MIN_DUTY > 100)); then
    die "CASE_FAN_RAD_MIN_DUTY は 10..100: $CASE_FAN_RAD_MIN_DUTY"
  fi
  [[ -n "$CASE_FAN_RAD_GPU_CURVE" ]] || die "CASE_FAN_RAD_GPU_CURVE が空です（ラジエーターの組を使うなら必須）"
  # CPU のクーラーのファンを、CPU の曲線なしで操らせない
  [[ -n "$CASE_FAN_RAD_CPU_CURVE" ]] ||
    die "CASE_FAN_RAD_CPU_CURVE が空です（ラジエーターのファンは CPU のクーラーなので、CPU の曲線なしでは操らない）"
  check_temp_source CASE_FAN_RAD_CPU "$CASE_FAN_RAD_CPU_HWMON" "$CASE_FAN_RAD_CPU_TEMP_CHANNEL"
  if [[ -n "$CASE_FAN_RAD_CPU_BACKUP_CURVE" ]]; then
    check_temp_source CASE_FAN_RAD_CPU_BACKUP "$CASE_FAN_RAD_CPU_BACKUP_HWMON" "$CASE_FAN_RAD_CPU_BACKUP_TEMP_CHANNEL"
  elif [[ -n "$CASE_FAN_RAD_CPU_BACKUP_HWMON$CASE_FAN_RAD_CPU_BACKUP_TEMP_CHANNEL" ]]; then
    die "CASE_FAN_RAD_CPU_BACKUP_HWMON・_TEMP_CHANNEL があるのに CASE_FAN_RAD_CPU_BACKUP_CURVE が空です（保険の曲線を使わないなら、3 つとも空にする）"
  fi

  local out pair pwm rpm case_pwms=" " seen=" "
  for pair in "${pairs[@]}"; do
    read -r pwm _ <<<"$pair"
    case_pwms+="$pwm "
  done
  out="$(channel_pairs CASE_FAN_RAD_CHANNELS "$CASE_FAN_RAD_CHANNELS")" || exit 1
  mapfile -t rad_pairs <<<"$out"
  for pair in "${rad_pairs[@]}"; do
    read -r pwm rpm <<<"$pair"
    [[ "$case_pwms" != *" $pwm "* ]] || die "pwm$pwm が CASE_FAN_CHANNELS と CASE_FAN_RAD_CHANNELS の両方にあります（1 つのファンは 1 つの組にだけ入れる）"
    [[ "$seen" != *" $pwm "* ]] || die "CASE_FAN_RAD_CHANNELS に pwm$pwm が2回あります"
    seen+="$pwm "
    [[ -e "$fan_dir/pwm$pwm" && -e "$fan_dir/pwm${pwm}_enable" ]] ||
      die "$CASE_FAN_HWMON に pwm$pwm（と pwm${pwm}_enable）がありません（CASE_FAN_RAD_CHANNELS）"
    [[ -e "$fan_dir/fan${rpm}_input" ]] || die "$CASE_FAN_HWMON に fan${rpm}_input がありません（CASE_FAN_RAD_CHANNELS）"
  done

  out="$(curve_points "$CASE_FAN_RAD_GPU_CURVE" CASE_FAN_RAD_GPU_CURVE)" || exit 1
  mapfile -t rad_gpu_points <<<"$out"
  check_curve_shape rad_gpu_points CASE_FAN_RAD_GPU_CURVE "GPU が読めないとき（${GPU_FAILSAFE_C}℃ を出す）に全開にするため" gpu
  out="$(curve_points "$CASE_FAN_RAD_CPU_CURVE" CASE_FAN_RAD_CPU_CURVE)" || exit 1
  mapfile -t rad_cpu_points <<<"$out"
  check_curve_shape rad_cpu_points CASE_FAN_RAD_CPU_CURVE "CPU が熱いときにラジエーターのファンを全開にするため（BIOS の曲線も最後は全開）"
  if [[ -n "$CASE_FAN_RAD_CPU_BACKUP_CURVE" ]]; then
    out="$(curve_points "$CASE_FAN_RAD_CPU_BACKUP_CURVE" CASE_FAN_RAD_CPU_BACKUP_CURVE)" || exit 1
    mapfile -t rad_backup_points <<<"$out"
    check_curve_shape rad_backup_points CASE_FAN_RAD_CPU_BACKUP_CURVE "主の温度の源が読めなくなったときに、保険の源で全開まで上がるようにするため"
  fi
  rad_min_pwm=$(((CASE_FAN_RAD_MIN_DUTY * 255 + 50) / 100))

  # CPU の冷却を BIOS より弱くしない: BIOS のモードが全開・SmartFan IV でない・分からないなら止まる。SmartFan IV で
  # BIOS と同じ温度の源なら、BIOS の曲線と比べて弱い所があれば止まる。
  # 比べられないとき（源が違う・曲線のファイルがない）は注意だけ（標準エラー。--print-config の出力に混ぜない）
  local rc
  for pair in "${rad_pairs[@]}"; do
    read -r pwm _ <<<"$pair"
    rc=0
    rad_bios_compare "$fan_dir" "$pwm" "${rad_cpu_points[@]}" || rc=$?
    case "$rc" in
      0) echo "ラジエーターの pwm$pwm: $cmp_msg" >&2 ;;
      2) warn "ラジエーターの pwm$pwm: $cmp_msg。CPU の曲線が BIOS より弱くないかは、自分で確かめる" >&2 ;;
      4) die "ラジエーターの pwm$pwm: $cmp_msg（CPU の冷却を BIOS より弱くしないため）" ;;
      *) die "ラジエーターの pwm$pwm: $cmp_msg。CPU の冷却を BIOS より弱くしないため、止めます（CASE_FAN_RAD_CPU_CURVE を BIOS の曲線以上にする）" ;;
    esac
  done
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
  # 期待の枚数が 0 なら case-fan-gpu-temp は枚数を確かめないので、コメントもそう書く（1 以上のときの文は変えない）
  local gpu_comment="読めないとき・枚数が $expected 枚でないときは ${GPU_FAILSAFE_C}℃ を出す（全開）"
  if ((expected == 0)); then
    gpu_comment="読めないときは ${GPU_FAILSAFE_C}℃ を出す（全開）。枚数は確かめない（NVIDIA_EXPECTED_GPUS=0）"
  fi
  # ファンが指す曲線。fan2go 0.15.0 の function の曲線は 2 本以上が要るので、CPU の曲線がなければ GPU の曲線を直に指す
  local fan_curve=gpu_curve how="GPU の曲線（CPU の曲線なし）"
  if [[ ${#cpu_points[@]} -gt 0 ]]; then
    fan_curve=case_fans
    how="max(GPU の曲線, CPU の曲線)"
  fi
  # ラジエーターの組があるときだけ、頭のコメントにその回し方を足す（組がないときの行は変えない）
  if [[ ${#rad_pairs[@]} -gt 0 ]]; then
    local rad_how="ラジエーターのファン = max(GPU の曲線, CPU の曲線"
    [[ ${#rad_backup_points[@]} -eq 0 ]] || rad_how+=", CPU の保険の曲線"
    how+="、$rad_how)"
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
    render_fan "case_pwm$pwm" "$pwm" "$rpm" "$fan_curve" "$min_pwm" \
      "止めない。最低は CASE_FAN_MIN_DUTY（$CASE_FAN_MIN_DUTY%）。初回の解析（PWM と RPM の関係を測る）の結果より、ここの値が勝つ"
  done
  for pair in "${rad_pairs[@]}"; do
    read -r pwm rpm <<<"$pair"
    render_fan "rad_pwm$pwm" "$pwm" "$rpm" rad_fans "$rad_min_pwm" \
      "CPU の簡易水冷のラジエーターのファン。止めない。最低は CASE_FAN_RAD_MIN_DUTY（$CASE_FAN_RAD_MIN_DUTY%）。初回の解析の結果より、ここの値が勝つ"
  done
  cat <<EOF

sensors:
  # NVIDIA の GPU の温度の最大（ミリ度）。$gpu_comment
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
  if [[ ${#rad_pairs[@]} -gt 0 ]]; then
    cat <<EOF
  # ラジエーターのファンの CPU の温度（CASE_FAN_RAD_CPU_*。BIOS と同じ源を指せるように、ケースファンの cpu とは別）
  - id: rad_cpu
    hwmon:
      platform: $CASE_FAN_RAD_CPU_HWMON
      channel: $CASE_FAN_RAD_CPU_TEMP_CHANNEL
EOF
    if [[ ${#rad_backup_points[@]} -gt 0 ]]; then
      cat <<EOF
  # 保険（CASE_FAN_RAD_CPU_BACKUP_*）: 主の源が固まる・0 を返すようになっても、この温度でファンが上がる
  - id: rad_cpu_backup
    hwmon:
      platform: $CASE_FAN_RAD_CPU_BACKUP_HWMON
      channel: $CASE_FAN_RAD_CPU_BACKUP_TEMP_CHANNEL
EOF
    fi
  fi
  printf '\ncurves:\n'
  render_curve gpu_curve gpu_max "${gpu_points[@]}"
  if [[ ${#cpu_points[@]} -gt 0 ]]; then
    render_curve cpu_curve cpu "${cpu_points[@]}"
    printf '  - id: case_fans\n    function:\n      type: maximum\n      curves:\n        - gpu_curve\n        - cpu_curve\n'
  fi
  if [[ ${#rad_pairs[@]} -gt 0 ]]; then
    render_curve rad_gpu_curve gpu_max "${rad_gpu_points[@]}"
    render_curve rad_cpu_curve rad_cpu "${rad_cpu_points[@]}"
    if [[ ${#rad_backup_points[@]} -gt 0 ]]; then
      render_curve rad_cpu_backup_curve rad_cpu_backup "${rad_backup_points[@]}"
    fi
    printf '  - id: rad_fans\n    function:\n      type: maximum\n      curves:\n        - rad_gpu_curve\n        - rad_cpu_curve\n'
    if [[ ${#rad_backup_points[@]} -gt 0 ]]; then
      printf '        - rad_cpu_backup_curve\n'
    fi
  fi
  cat <<EOF

statistics:
  enabled: false
api:
  enabled: false
EOF
}

# fans の 1 つ。$1 id、$2 pwm、$3 rpm、$4 曲線、$5 最低の PWM、$6 コメント
render_fan() {
  cat <<EOF
  - id: $1
    hwmon:
      platform: $CASE_FAN_HWMON
      rpmChannel: $3
      pwmChannel: $2
    curve: $4
    # $6
    neverStop: true
    minPwm: $5
    startPwm: $5
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
  echo "  ホストの設定: hosts/ubuntu/$UBUNTU_HOST.env（CASE_FAN_CONTROL=$CASE_FAN_CONTROL CASE_FAN_MODULE=$CASE_FAN_MODULE CASE_FAN_HWMON=${CASE_FAN_HWMON:-空} CASE_FAN_CHANNELS=${CASE_FAN_CHANNELS:-空} CASE_FAN_RAD_CHANNELS=${CASE_FAN_RAD_CHANNELS:-空} CASE_FAN_ACPI_LAX=$CASE_FAN_ACPI_LAX）"

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
    # 調べる道具なので、nvidia-smi が失敗しても（ドライバの不一致など）先へ進む
    local smi_out smi_rc=0
    smi_out="$(nvidia-smi --query-gpu=index,pci.bus_id,name,temperature.gpu,fan.speed,power.draw --format=csv,noheader 2>&1)" || smi_rc=$?
    # shellcheck disable=SC2001
    [[ -z "$smi_out" ]] || sed 's/^/  /' <<<"$smi_out"
    ((smi_rc == 0)) || ng "nvidia-smi が失敗しました（終了コード $smi_rc。ドライバの不一致など。上の行がその出力）"
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
      echo "      （--identify は env に書く前から使える。CASE_FAN_HWMON が空なら、pwm のある Super I/O が 1 つのときそれを操る。下の「--identify が使う hwmon」）"
      echo "      決まったら hosts/ubuntu/$UBUNTU_HOST.env に CASE_FAN_HWMON=${superio[0]}、CASE_FAN_CHANNELS=\"<ケースファンの番号>\" を書く"
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
  if pick_identify_hwmon; then
    echo "  --identify が使う hwmon: $id_name（$(basename "$id_dir")。$id_how）"
    local f c refused=() nocurve=()
    for f in "$id_dir"/pwm[0-9]*; do
      [[ "$f" =~ /pwm([0-9]+)$ ]] || continue
      c=${BASH_REMATCH[1]}
      if stop_guard "$id_dir" "$c"; then
        refused+=("pwm$c（$guard_short）")
      elif "$guard_nocurve"; then
        nocurve+=("pwm$c")
      fi
    done
    echo "  --identify --stop が断るチャネル（ポンプなど、止めてはいけないものと見られる。止めるなら --allow-pump）: ${refused[*]:-なし}"
    if [[ ${#nocurve[@]} -gt 0 ]]; then
      echo "    BIOS の曲線（pwmN_auto_point*_pwm）がなく判定できないチャネル（--stop は注意を出して進める）: ${nocurve[*]}"
    fi
  else
    echo "  --identify が使う hwmon: 決まらない（$id_why）"
  fi
  [[ -z "$CASE_FAN_RAD_CHANNELS" ]] || probe_rad_bios
}

# --probe の見立て: ラジエーターの組の BIOS のモードと、CPU の曲線と BIOS の曲線の比べ（入れるときの守りと同じ。読むだけ）
probe_rad_bios() {
  local dir out pts=() pwm rc
  if ! dir="$(find_hwmon "${CASE_FAN_HWMON:-?}" 2>/dev/null)"; then
    echo "  ラジエーターの組（CASE_FAN_RAD_CHANNELS=$CASE_FAN_RAD_CHANNELS）: CASE_FAN_HWMON（${CASE_FAN_HWMON:-空}）が1つに決まらないので、BIOS の曲線とは比べられない"
    return 0
  fi
  if ! out="$(curve_points "$CASE_FAN_RAD_CPU_CURVE" CASE_FAN_RAD_CPU_CURVE 2>&1)" || [[ -z "$out" ]]; then
    warn "ラジエーターの組: CASE_FAN_RAD_CPU_CURVE が空か読めない（${out:-空}）。入れるスクリプトは止まる"
    return 0
  fi
  mapfile -t pts <<<"$out"
  out="$(channel_pairs CASE_FAN_RAD_CHANNELS "$CASE_FAN_RAD_CHANNELS" 2>&1)" || { warn "ラジエーターの組: $out"; return 0; }
  while read -r pwm _; do
    rc=0
    rad_bios_compare "$dir" "$pwm" "${pts[@]}" || rc=$?
    case "$rc" in
      0) ok "ラジエーターの pwm$pwm: $cmp_msg" ;;
      2) warn "ラジエーターの pwm$pwm: $cmp_msg" ;;
      # 4（BIOS のモード）も含め、入れるときに止まるもの
    *) ng "ラジエーターの pwm$pwm: $cmp_msg。入れるスクリプトは止まる" ;;
    esac
  done <<<"$out"
}

# --- 変更する ---------------------------------------------------------------

# --identify が変えた pwm を元へ戻す（EXIT の trap から呼ぶ）。途中で失敗しても、pwm と enable の両方を書きに行く。
# 戻ったか: 書き込みが 2 つとも通り、enable を読み戻して元と同じ。元が手動（enable=1）なら pwm も読み戻して元と同じ
# （BIOS の自動なら pwm は BIOS が決めるので比べない）。戻らなければ、何が戻っていないかと手で戻すコマンドを
# 標準エラーに出し、0 でない終了コードで終わる（もとの終了コードが 0 でなければ、INT の 130 などそれを保つ）
restore_identify() {
  local rc=$? pwm_f="$id_dir/pwm$id_ch" enable_f="$id_dir/pwm${id_ch}_enable" now_pwm now_enable why=()
  set +e
  # 2>/dev/null を先に書く（開けないときのシェルのメッセージも捨て、下で自分の文を出す）
  printf '%s\n' "$id_old_pwm" 2>/dev/null >"$pwm_f" || why+=("pwm$id_ch への書き込みが失敗")
  printf '%s\n' "$id_old_enable" 2>/dev/null >"$enable_f" || why+=("pwm${id_ch}_enable への書き込みが失敗")
  now_pwm="$(cat "$pwm_f" 2>/dev/null)" || now_pwm="?"
  now_enable="$(cat "$enable_f" 2>/dev/null)" || now_enable="?"
  [[ "$now_enable" == "$id_old_enable" ]] || why+=("enable を読み戻すと ${now_enable:-空}")
  if [[ "$id_old_enable" == 1 && "$now_pwm" != "$id_old_pwm" ]]; then
    why+=("元が手動（enable=1）なのに pwm を読み戻すと ${now_pwm:-空}")
  fi
  if [[ ${#why[@]} -eq 0 ]]; then
    echo "pwm$id_ch を元（enable=$id_old_enable pwm=$id_old_pwm）へ戻しました" 2>/dev/null
    exit "$rc"
  fi
  local i reasons=${why[0]}
  for ((i = 1; i < ${#why[@]}; i++)); do reasons+="、${why[i]}"; done
  echo "pwm$id_ch を元へ戻せませんでした（戻したい値: enable=$id_old_enable pwm=$id_old_pwm。いま: enable=$now_enable pwm=$now_pwm。$reasons）。"$'\n'"  手で戻す: sudo sh -c 'echo $id_old_pwm > $pwm_f; echo $id_old_enable > $enable_f'（再起動でも BIOS の制御に戻る）" >&2 2>/dev/null
  ((rc != 0)) || rc=1
  exit "$rc"
}

identify() {
  local ch="$identify_channel" dir i n seconds=10 target
  pick_identify_hwmon || die "$id_why"
  dir=$id_dir
  if "$fake_hwmon_root"; then
    # 試験の入口でも、本物の sysfs には書きに行かない。待つ秒数は試験のときだけ縮められる
    [[ "$(realpath -e -- "$dir")" != /sys/* ]] || die "にせの hwmon の木の中に /sys を指すものがあります: $dir"
    if [[ -n "${CASE_FAN_TEST_IDENTIFY_SECONDS:-}" ]]; then
      [[ "$CASE_FAN_TEST_IDENTIFY_SECONDS" =~ ^[1-9][0-9]*$ ]] || die "CASE_FAN_TEST_IDENTIFY_SECONDS は 1 以上の整数"
      seconds=$CASE_FAN_TEST_IDENTIFY_SECONDS
    fi
  fi
  [[ -n "$CASE_FAN_HWMON" ]] || echo "CASE_FAN_HWMON が空なので、Super I/O の hwmon $id_name（$dir）を使います"
  [[ -e "$dir/pwm$ch" && -e "$dir/pwm${ch}_enable" ]] || die "$id_name に pwm$ch がありません"
  if systemctl is-active --quiet fan2go 2>/dev/null; then
    die "fan2go が動いています。先に sudo systemctl stop fan2go（止めると BIOS の制御に戻る）"
  fi
  if "$identify_stop"; then
    if stop_guard "$dir" "$ch"; then
      local msg="pwm$ch: $guard_why。ポンプなら、止めると CPU が冷えなくなる"
      if "$allow_pump"; then
        warn "$msg。--allow-pump があるので止めます（$seconds 秒で戻します）"
      else
        die "$msg。止めません。それでも止めるなら: $0 --identify $ch --stop --allow-pump"
      fi
    elif "$guard_nocurve"; then
      warn "$pump_why。ポンプかどうか判定できないので、確かめずに止めます（ポンプなら CPU が冷えなくなる。止めたら CPU の温度に気をつける）"
    fi
  fi
  # 戻す値を先に読む。読めなければ何も変えずに止まる
  id_ch=$ch
  id_old_enable="$(cat "$dir/pwm${ch}_enable")"
  id_old_pwm="$(cat "$dir/pwm$ch")"
  [[ "$id_old_enable" =~ ^[0-9]+$ && "$id_old_pwm" =~ ^[0-9]+$ ]] ||
    die "pwm$ch の今の値が読めません（enable=$id_old_enable pwm=$id_old_pwm）。何も変えていません"
  # 何があっても元へ戻す。INT・TERM・HUP では明示に exit して EXIT の trap を走らせる
  # （bash は trap のない INT を、前面の子が INT で死ななければ無視して続けることがある）。
  # SIGPIPE は無視して、出力先が閉じたら書き込みの失敗（set -e）で EXIT の trap へ行く
  trap restore_identify EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
  trap '' PIPE
  if "$identify_stop"; then
    target=0
    echo "pwm$ch を $seconds 秒だけ止めます（pwm=0。元: enable=$id_old_enable pwm=$id_old_pwm）。どのファンが止まったかと、どの fan の RPM が下がったかを見る"
    echo "  pwm=0 でも止まらないファンがある（最低回転で回り続ける PWM ファン、3pin のポンプなど）。止まらなければ、回転が下がるかを見る"
    echo "  fanN がいつも 0 のチャネル（回転を返さないハブ越し）は、目で見て止まるかを見る"
  else
    target=255
    echo "pwm$ch を $seconds 秒だけ全開にします（元: enable=$id_old_enable pwm=$id_old_pwm）。どのファンの音が変わったかと、どの fan の RPM が上がったかを見る"
  fi
  echo 1 > "$dir/pwm${ch}_enable"
  echo "$target" > "$dir/pwm$ch"
  for i in $(seq 1 "$seconds"); do
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
  # active だけでなく、落ちて起動し直しを待っている（activating (auto-restart)）・起動中・止まりかけも止める。
  # 待っているのを止めないと、記録（case-fan-restore.conf）を書き直すあいだに古い設定で起動し、組から外したチャネルを操りうる
  local state
  state="$(systemctl is-active fan2go 2>/dev/null || true)"
  case "$state" in
    active | activating | deactivating | reloading | refreshing)
      echo "fan2go を止めます（$state。BIOS の制御に戻る）"
      systemctl stop fan2go
      ;;
  esac
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

# 前の記録（case-fan-restore.conf）にあって、新しい記録（引数の「<name> <チャネル> <enable>」）にないチャネルを確かめる。
# 組から外したチャネル（例: ラジエーターの組をやめた pwm2）は、記録を書き直すと case-fan-restore-bios が戻さなくなる。
# ふつうは直前の stop_fan2go で fan2go 自身（onExit: restore）と ExecStopPost が前の記録の値へ戻している。
# それでも手動（enable=1）のまま残っていれば、ここで前の記録の値へ戻し、読み戻して確かめる。戻せなければ、
# 記録を書き直さずに止まる（前の記録が残るので、次に fan2go が止まるときにも戻しに行く）
restore_dropped_channels() {
  local keep=" " item name ch enable _rest dir now
  for item in "$@"; do
    read -r name ch _rest <<<"$item"
    keep+="$name:$ch "
  done
  [[ -r "$RESTORE_CONF" ]] || return 0
  while read -r name ch enable _rest; do
    [[ -n "${name:-}" && "${name:0:1}" != "#" ]] || continue
    [[ "$keep" != *" $name:$ch "* ]] || continue
    dir="$(find_hwmon "$name" 2>/dev/null)" || {
      warn "前の記録の $name pwm$ch は、組から外したチャネルですが、hwmon $name が1つに決まらないので確かめられません" >&2
      continue
    }
    now="$(cat "$dir/pwm${ch}_enable" 2>/dev/null)" || now="?"
    if [[ "$now" != 1 ]]; then
      echo "組から外した $name pwm$ch は BIOS の制御（pwm${ch}_enable=$now）です。記録から外します"
      continue
    fi
    [[ "$enable" =~ ^[0-9]+$ && "$enable" != 1 ]] ||
      die "組から外した $name pwm$ch が手動（enable=1）のままで、前の記録の値（${enable:-空}）では BIOS の制御へ戻せません。記録は書き直していません。再起動して BIOS の制御に戻してから入れ直す"
    if [[ "$mode" != install ]] && ! "$fake_hwmon_root"; then
      die "組から外した $name pwm$ch が手動（enable=1）のままです（試験の入口なので本物の sysfs には書きません）"
    fi
    if printf '%s\n' "$enable" 2>/dev/null >"$dir/pwm${ch}_enable" &&
      [[ "$(cat "$dir/pwm${ch}_enable" 2>/dev/null)" == "$enable" ]]; then
      echo "組から外した $name pwm$ch が手動（enable=1）のままだったので、前の記録の pwm${ch}_enable=$enable（BIOS の制御）へ戻しました"
    else
      die "組から外した $name pwm$ch を pwm${ch}_enable=$enable（BIOS の制御）へ戻せませんでした。記録は書き直していません。手で戻す: sudo sh -c 'echo $enable > $dir/pwm${ch}_enable'（再起動でも BIOS の制御に戻る）"
    fi
  done <"$RESTORE_CONF"
}

# 今の pwmN_enable を「BIOS の制御」として記録する。fan2go が止まっている状態で読む
write_restore_conf() {
  local pair pwm enable old lines=()
  # ケースファンとラジエーターのファンの両方（強制終了のときに ExecStopPost の case-fan-restore-bios が行ごとに戻す）
  for pair in "${pairs[@]}" "${rad_pairs[@]}"; do
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
  restore_dropped_channels "${lines[@]}"
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
  if [[ ${#rad_pairs[@]} -gt 0 ]]; then
    # 解析済みかどうかは fan2go の DB を読まないと分からないので、組があるときはいつも出す
    warn "ラジエーターのファン（CASE_FAN_RAD_CHANNELS=$CASE_FAN_RAD_CHANNELS）を初めて入れるときは、fan2go の初回の解析で、そのファンが止まる時間があります（止まる所の探索で pwm=0 まで下げる。見込み 30 秒〜1 分、最悪 3 分前後。ポンプは BIOS の制御のまま回り続ける）。CPU と GPU の負荷が低いときに入れるのがよい"
  fi

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
  for pair in "${pairs[@]}" "${rad_pairs[@]}"; do
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
  test-write-restore-conf) check_settings; write_restore_conf ;;
  identify) identify ;;
  install) do_install ;;
  uninstall) do_uninstall ;;
esac
