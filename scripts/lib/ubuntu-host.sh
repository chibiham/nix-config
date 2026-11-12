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

# GPUの割り当て（CUDA_VISIBLE_DEVICES）。空ならunitに書かない（すべてのGPUが見える）
: "${COMFY_CUDA_DEVICES:=}"
# comfyui.serviceの main.py に足す起動オプション（例: --fast fp16_accumulation）。空なら足さない
: "${COMFY_EXTRA_ARGS:=}"
: "${LLM_CUDA_DEVICES:=}"
: "${TRAIN_CUDA_DEVICES:=}"
: "${APPLIO_CUDA_DEVICES:=}"

# 2枚以上を束ねてLLMを動かす別unit（qwen38-dual.service）のGPU。空なら作らない
: "${LLM_DUAL_CUDA_DEVICES:=}"
# llama.cppの分割の仕方（layer: 層ごと / row: 行ごと。PCIeだけの構成ではlayerが無難）
: "${LLM_DUAL_SPLIT_MODE:=layer}"
# 各GPUへの配分（例: 1,1）。空ならllama.cppが空きVRAMから決める
: "${LLM_DUAL_TENSOR_SPLIT:=}"

# qwen38.serviceを何と一緒に起動するか（同じGPUならcomfyui.service、別GPUならdefault.target）
: "${QWEN_WANTED_BY:=comfyui.service}"
# 導入時にComfyUIを止めるか（同じGPUを取り合う構成だけ1）
: "${QWEN_STOP_COMFY_ON_INSTALL:=1}"
# Applioを排他にするunit
: "${APPLIO_CONFLICTS:=comfyui.service qwen38.service}"

export UBUNTU_HOST

# CUDA_VISIBLE_DEVICES="0,1" → 2
cuda_device_count() {
  local devices="$1"
  [[ -n "$devices" ]] || { echo 0; return; }
  awk -F, '{ print NF }' <<<"$devices"
}
