# shellcheck shell=bash
# Ubuntu機ごとの設定を読む。scripts/*-ubuntu.sh から source する。
#
# ホスト名は UBUNTU_HOST（なければ `hostname -s`）で決め、
# hosts/ubuntu/<ホスト名>.env があれば読む。変数の意味は hosts/ubuntu/README.md。
#
# 既定値は chibihamuntu（RTX 3090 1枚・Intel）の挙動と同じにしてある。
# hosts/ubuntu/ にファイルがないホストでも、これまでどおりに動く。
# 呼び出し側の環境変数で個別に上書きできる（例: COMFY_CUDA_DEVICES=1 install-comfyui-ubuntu.sh）。

_ubuntu_host_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UBUNTU_HOST="${UBUNTU_HOST:-$(hostname -s 2>/dev/null || hostname)}"
UBUNTU_HOST_FILE="$_ubuntu_host_repo/hosts/ubuntu/$UBUNTU_HOST.env"
if [[ -f "$UBUNTU_HOST_FILE" ]]; then
  # ファイルは `: "${VAR:=値}"` の形で書く。呼び出し側で設定済みの変数が優先される。
  # shellcheck source=/dev/null
  source "$UBUNTU_HOST_FILE"
fi
unset _ubuntu_host_repo

# Home Managerの対象（flake.nix の homeConfigurations."<user>@<FLAKE_HOST>"）
: "${FLAKE_HOST:=ubuntu-server}"
# このマシン専用の1Password Vault（home/linux.nix の env.tpl と揃える）
: "${OP_VAULT:=chibihamuntu}"
# このホストのユーザー（bootstrap が $USER と照らす。空なら確かめない）
: "${UBUNTU_USER:=}"
# tailscale up --hostname に渡す名前（空なら渡さない。OSのホスト名が使われる）
: "${TAILSCALE_HOSTNAME:=}"
# Tailscale Serve（tailnet内だけのHTTPS公開）。「HTTPSのポート=127.0.0.1のポート」を空白区切り（例: "443=8188 4520=4520"）。
# configure-tailscale-serve-ubuntu.sh が使う。空なら何も足さない
: "${TAILSCALE_SERVE:=}"

# NVIDIA
# 期待するGPUの枚数（0なら確かめない）
: "${NVIDIA_EXPECTED_GPUS:=0}"
# オープンカーネルモジュール（nvidia-driver-*-open）を必須にする（Blackwell以降は必須）
: "${NVIDIA_REQUIRE_OPEN:=0}"
# 導入するドライバの最小の世代（0なら確かめない）
: "${NVIDIA_MIN_DRIVER:=0}"

# GPU LED（OpenRGB）
: "${GPU_LED_OFF:=1}"
# OpenRGBのデバイス一覧の行（小文字）に当てる正規表現（awk）
: "${GPU_LED_MATCH:=gigabyte.*rtx ?3090}"
# 一致すべき台数。この数と違えば何も変えずに失敗する
: "${GPU_LED_COUNT:=1}"

# CPU消費電力（powercapのenergy_uj）の読み取り権限
: "${CPU_POWER_READ:=1}"

# ケースファンをGPUの温度で回す（install-case-fan-control-ubuntu.sh、fan2go）。既定は切
: "${CASE_FAN_CONTROL:=0}"
# Super I/O のドライバ（/etc/modules-load.d に書いて起動のたびに読み込む）
: "${CASE_FAN_MODULE:=nct6775}"
# 操る hwmon の name（例: nct6799）。--probe の出力から決める
: "${CASE_FAN_HWMON:=}"
# 操る pwm のチャネル（空白区切り。RPM の番号が違えば pwm:rpm）。CPU_FAN は入れない
: "${CASE_FAN_CHANNELS:=}"
# 最低のデューティ（%）。止めない
: "${CASE_FAN_MIN_DUTY:=30}"
# 曲線（「温度:デューティ%」を空白区切り）。ケースファン = max(GPU, CPU)。CPU を空にすると GPU だけ
# GPU の曲線の最後の点は 100%・100℃ 未満（GPU が読めないときに全開にするため。そうでなければ止まる）
: "${CASE_FAN_GPU_CURVE:=45:30 60:45 70:65 78:85 83:100}"
: "${CASE_FAN_CPU_CURVE:=}"
: "${CASE_FAN_CPU_HWMON:=k10temp}"
: "${CASE_FAN_CPU_TEMP_CHANNEL:=1}"
# ラジエーターの組（CPU の簡易水冷のラジエーターのファン）。ケースファンとは別の曲線で、ファン = max(GPU, CPU[, CPU の保険])。
# チャネルが空なら使わない（設定はケースファンだけ）。使うなら GPU の曲線と CPU の曲線（とその温度の源）が必須。
# CPU の曲線は BIOS の曲線より弱くしない（同じ温度の源なら、入れるスクリプトが sysfs の BIOS の曲線と比べて止まる）
: "${CASE_FAN_RAD_CHANNELS:=}"
: "${CASE_FAN_RAD_MIN_DUTY:=20}"
: "${CASE_FAN_RAD_GPU_CURVE:=}"
: "${CASE_FAN_RAD_CPU_CURVE:=}"
: "${CASE_FAN_RAD_CPU_HWMON:=}"
: "${CASE_FAN_RAD_CPU_TEMP_CHANNEL:=}"
: "${CASE_FAN_RAD_CPU_BACKUP_CURVE:=}"
: "${CASE_FAN_RAD_CPU_BACKUP_HWMON:=}"
: "${CASE_FAN_RAD_CPU_BACKUP_TEMP_CHANNEL:=}"
# 1 なら GRUB に acpi_enforce_resources=lax を足す（ACPI が Super I/O を握っていて掴めないときだけ）
: "${CASE_FAN_ACPI_LAX:=0}"

# GPUの割り当て（CUDA_VISIBLE_DEVICES）。空ならunitに書かない（すべてのGPUが見える）。
# 複数を書くと、最初のGPUがComfyUIの既定のデバイス（cuda:0）になる
: "${COMFY_CUDA_DEVICES:=}"
# comfyui.serviceの main.py に足す起動オプション（例: --fast fp16_accumulation）。空なら足さない。
# 2 つ目以降の常駐（COMFY_EXTRA_INSTANCES）にも同じものを足す（同じ絵にするため）
: "${COMFY_EXTRA_ARGS:=}"
# 2 つ目以降の ComfyUI の常駐（install-comfyui-ubuntu.sh が comfyui-<名前>.service を書く）。
# 「名前:ポート:見せるGPU」を空白区切り（例: "gpu1:8189:1"）。置き場（コード・venv・models・custom_nodes・user・input・output）は
# comfyui.service と同じで、temp だけ分ける。ComfyUI-Manager は付けない。127.0.0.1 だけで待ち受ける。空なら作らない（chibihamuntu）
: "${COMFY_EXTRA_INSTANCES:=}"
# ComfyUIの版（タグかcommit）。update-comfyui-ubuntu.sh はこれを checkout --detach する。
# 空なら今までどおり git pull --ff-only（master に追従）。install-comfyui-ubuntu.sh は新しく clone するときだけ使う
: "${COMFY_REF:=}"
# MiniMax H3 Image の DiT の版（install-minimax-h3-image-ubuntu.sh。空白区切り: int8 w4a8 gguf-q5 gguf-q4）。空なら置かない
: "${H3_IMAGE_MODELS:=}"
# art-studio（~/ai）の unit に drop-in で足す値（configure-art-studio-ubuntu.sh）。両方とも空なら drop-in を書かない
: "${ART_STUDIO_COMFYUI_URL:=}"
: "${ART_STUDIO_CUDA_DEVICES:=}"
: "${LLM_CUDA_DEVICES:=}"
: "${TRAIN_CUDA_DEVICES:=}"
: "${APPLIO_CUDA_DEVICES:=}"

# 2枚以上を束ねてLLMを動かす別unit（qwen38-dual.service）のGPU。空なら作らない
: "${LLM_DUAL_CUDA_DEVICES:=}"
# llama.cppの分割の仕方（layer: 層ごと / row: 行ごと。PCIeだけの構成ではlayerが無難）
: "${LLM_DUAL_SPLIT_MODE:=layer}"
# 各GPUへの層の配分（例: 39,10）。空ならllama.cppが空きVRAMから決める。
# n-cpu-moeを使うモデルでは、エキスパートをGPUに置く重い層が後ろに固まるので、半々（1,1）にすると後ろのGPUに寄る
: "${LLM_DUAL_TENSOR_SPLIT:=}"

# qwen38.serviceを何と一緒に起動するか（同じGPUならcomfyui.service、別GPUならdefault.target）
: "${QWEN_WANTED_BY:=comfyui.service}"
# 導入時にComfyUIを止めるか（同じGPUを取り合う構成だけ1）
: "${QWEN_STOP_COMFY_ON_INSTALL:=1}"
# llama-server（Router）の --sleep-idle-seconds。この秒数だけ使われなかったモデルを降ろしてVRAMを空ける
# （次の要求で読み込み直す）。空ならunitに書かない
: "${QWEN_SLEEP_IDLE_SECONDS:=}"
# Applioを排他にするunit
: "${APPLIO_CONFLICTS:=comfyui.service qwen38.service}"

export UBUNTU_HOST

# CUDA_VISIBLE_DEVICES="0,1" → 2
cuda_device_count() {
  local devices="$1"
  [[ -n "$devices" ]] || { echo 0; return; }
  awk -F, '{ print NF }' <<<"$devices"
}

# comfy_extra_instances
# COMFY_EXTRA_INSTANCES を読み、常駐ごとに「名前 ポート GPU」を 1 行ずつ出す（空なら何も出さない）。
# 形が違う・名前やポートが重なる・8188（comfyui.service）を使うときは、理由を出して 1（何も出さない）。
# 名前は unit の名前（comfyui-<名前>.service）と temp の置き場（<ComfyUI>/temp-<名前>）に使う
comfy_extra_instances() {
  local entries entry name port devices rest out="" seen_names=" " seen_ports=" 8188 "
  read -r -a entries <<<"$COMFY_EXTRA_INSTANCES"
  for entry in ${entries[@]+"${entries[@]}"}; do
    IFS=: read -r name port devices rest <<<"$entry"
    if [[ -n "$rest" || ! "$name" =~ ^[a-z0-9][a-z0-9-]*$ || ! "$port" =~ ^[1-9][0-9]*$ || ! "$devices" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
      echo "COMFY_EXTRA_INSTANCES の「${entry}」は「名前:ポート:見せるGPU」（例: gpu1:8189:1。名前は英小文字・数字・-）の形ではありません" >&2
      return 1
    fi
    if ((port < 1024 || port > 65535)); then
      echo "COMFY_EXTRA_INSTANCES の「${entry}」のポートは 1024〜65535 にしてください" >&2
      return 1
    fi
    if [[ "$seen_names" == *" $name "* ]]; then
      echo "COMFY_EXTRA_INSTANCES に名前 $name が 2 度あります" >&2
      return 1
    fi
    if [[ "$seen_ports" == *" $port "* ]]; then
      echo "COMFY_EXTRA_INSTANCES の「${entry}」のポート $port は、ほかの ComfyUI の常駐（comfyui.service は 8188）と重なります" >&2
      return 1
    fi
    seen_names+="$name "
    seen_ports+="$port "
    out+="$name $port $devices"$'\n'
  done
  printf '%s' "$out"
}
