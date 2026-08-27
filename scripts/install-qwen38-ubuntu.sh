#!/usr/bin/env bash
# Qwen3.8-27B UD-Q4_K_Mを取得し、ComfyUIと排他的なuser serviceを構成する。
set -euo pipefail

MODEL_REPO="unsloth/Qwen3.8-27B-GGUF"
MODEL_REVISION="4ca720788d1e01f1bff70c033e0d0028fd02e502"
MODEL_FILE="Qwen3.8-27B-UD-Q4_K_M.gguf"
MODEL_DIR="${QWEN_MODEL_DIR:-$HOME/models/qwen3.8-27b}"
MODEL_PATH="$MODEL_DIR/$MODEL_FILE"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/qwen38.service"
PORT="${QWEN_PORT:-8080}"
CONTEXT_SIZE="${QWEN_CONTEXT_SIZE:-131072}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Linux" ]] || ! command -v systemctl >/dev/null; then
  echo "このスクリプトはsystemdを使うLinux専用です" >&2
  exit 1
fi

for command in aria2c llama-server nvidia-smi; do
  if ! command -v "$command" >/dev/null; then
    echo "必要なコマンドがありません: $command" >&2
    echo "先にUbuntu用Home Manager設定を適用してください" >&2
    exit 1
  fi
done

if ! nvidia-smi >/dev/null 2>&1; then
  echo "NVIDIAドライバが動作していません" >&2
  exit 1
fi

step "ComfyUIを停止"
systemctl --user stop comfyui.service 2>/dev/null || true

step "モデルを取得"
mkdir -p "$MODEL_DIR"
if [[ -s "$MODEL_PATH" ]]; then
  ok "$MODEL_PATH は取得済みです"
else
  tmp_path="$MODEL_PATH.part"
  model_url="https://huggingface.co/$MODEL_REPO/resolve/$MODEL_REVISION/$MODEL_FILE"
  aria2c --continue=true --max-connection-per-server=16 --split=16 \
    --min-split-size=16M --max-tries=0 --retry-wait=5 \
    --dir="$MODEL_DIR" --out="$MODEL_FILE.part" "$model_url"
  mv "$tmp_path" "$MODEL_PATH"
  ok "$MODEL_PATH を取得しました"
fi

step "systemd user service"
mkdir -p "$SERVICE_DIR"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Qwen3.8-27B UD-Q4_K_M (llama.cpp)
After=network-online.target
Wants=network-online.target
Conflicts=comfyui.service

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=$HOME/.local/lib/nvidia
ExecStart=$HOME/.nix-profile/bin/llama-server \\
  --model $MODEL_PATH \\
  --alias qwen3.8-27b \\
  --host 127.0.0.1 \\
  --port $PORT \\
  --ctx-size $CONTEXT_SIZE \\
  --n-gpu-layers 99 \\
  --flash-attn on \\
  --cache-type-k q8_0 \\
  --cache-type-v q8_0 \\
  --parallel 1 \\
  --jinja
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
# 再起動後は既存のComfyUIを既定とする。Qwenはai-mode qwenで明示起動する。
systemctl --user disable qwen38.service >/dev/null 2>&1 || true
systemctl --user start qwen38.service

ok "Qwen3.8を起動しました: http://127.0.0.1:$PORT"
echo "状態: ai-mode status"
echo "Qwenへ切替: ai-mode qwen"
echo "ComfyUIへ切替: ai-mode comfy"
echo "ログ: journalctl --user -u qwen38 -f"
