#!/usr/bin/env bash
# Qwen3.8-27B-Uncensored Q4_K_MをMac miniへ取得する。
# 実行環境とlaunchd jobはhome/hosts/mac-mini.nixで宣言する。
set -euo pipefail

MODEL_REPO="JonathanColetti/Qwen3.8-27B-Uncensored-GGUF"
MODEL_REVISION="b7ff25715ee2ae49c9ff32159bc73de864648aef"
MODEL_FILE="Qwen3.8-27B-Uncensored-Q4_K_M.gguf"
MODEL_SHA256="4c5e2db039e9325ac7724c8846c71356a24ad1cdfa28002d73ecb6be645f9675"
MODEL_DIR="${QWEN_MODEL_DIR:-$HOME/models/qwen3.8-27b}"
MODEL_PATH="$MODEL_DIR/$MODEL_FILE"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "このスクリプトはmacOS専用です" >&2
  exit 1
fi

model_name="$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ { print $2; exit }')"
if [[ "$model_name" != *"Mac mini"* ]]; then
  echo "このスクリプトはMac mini専用です（検出: ${model_name:-不明}）" >&2
  exit 1
fi

for command in aria2c llama-server shasum; do
  if ! command -v "$command" >/dev/null; then
    echo "必要なコマンドがありません: $command" >&2
    echo "先にMac mini用Home Manager設定を適用してください" >&2
    exit 1
  fi
done

mkdir -p "$MODEL_DIR"

if [[ -s "$MODEL_PATH" ]] && echo "$MODEL_SHA256  $MODEL_PATH" | shasum -a 256 -c - >/dev/null 2>&1; then
  ok "$MODEL_PATH は取得・検証済みです"
else
  step "Qwen3.8-27B-Uncensored Q4_K_Mを取得（約16.8GB）"
  aria2c --continue=true --max-connection-per-server=16 --split=16 \
    --min-split-size=16M --max-tries=0 --retry-wait=5 \
    --dir="$MODEL_DIR" --out="$MODEL_FILE.part" \
    "https://huggingface.co/$MODEL_REPO/resolve/$MODEL_REVISION/$MODEL_FILE"

  step "SHA-256を検証"
  echo "$MODEL_SHA256  $MODEL_PATH.part" | shasum -a 256 -c -
  mv "$MODEL_PATH.part" "$MODEL_PATH"
  ok "$MODEL_PATH へ配置しました"
fi

echo
echo "起動: qwen38 start"
echo "状態: qwen38 status"
echo "停止: qwen38 stop"
