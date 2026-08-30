#!/usr/bin/env bash
# Qwen3.8-27Bの通常版・Uncensored版を取得し、切替可能なuser serviceを構成する。
set -euo pipefail

MODEL_REPO="unsloth/Qwen3.8-27B-GGUF"
MODEL_REVISION="4ca720788d1e01f1bff70c033e0d0028fd02e502"
MODEL_FILE="Qwen3.8-27B-UD-Q4_K_M.gguf"
MODEL_VISION_FILE="mmproj-BF16.gguf"
UNCENSORED_MODEL_REPO="JonathanColetti/Qwen3.8-27B-Uncensored-GGUF"
UNCENSORED_MODEL_REVISION="b7ff25715ee2ae49c9ff32159bc73de864648aef"
UNCENSORED_MODEL_FILE="Qwen3.8-27B-Uncensored-Q4_K_M.gguf"
UNCENSORED_MODEL_VISION_FILE="Qwen3.8-27B-Uncensored-vision-bf16.gguf"
MODEL_DIR="${QWEN_MODEL_DIR:-$HOME/models/qwen3.8-27b}"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/qwen38.service"
PRESET_DIR="$HOME/.config/llama.cpp"
PRESET_FILE="$PRESET_DIR/qwen38-models.ini"
CHAT_TEMPLATE_FILE="$PRESET_DIR/qwen38-chat-template.jinja"
PORT="${QWEN_PORT:-8080}"
CONTEXT_SIZE="${QWEN_CONTEXT_SIZE:-131072}"
TAILSCALE_HTTPS_PORT="${QWEN_TAILSCALE_HTTPS_PORT:-8443}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Linux" ]] || ! command -v systemctl >/dev/null; then
  echo "このスクリプトはsystemdを使うLinux専用です" >&2
  exit 1
fi

for command in aria2c llama-server nvidia-smi uv; do
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

download_model() {
  local repo="$1" revision="$2" file="$3"
  local path="$MODEL_DIR/$file"
  if [[ -s "$path" ]]; then
    ok "$path は取得済みです"
    return
  fi

  aria2c --continue=true --max-connection-per-server=16 --split=16 \
    --min-split-size=16M --max-tries=0 --retry-wait=5 \
    --dir="$MODEL_DIR" --out="$file.part" \
    "https://huggingface.co/$repo/resolve/$revision/$file"
  mv "$path.part" "$path"
  ok "$path を取得しました"
}

step "ComfyUIとQwenを停止"
systemctl --user stop comfyui.service 2>/dev/null || true
systemctl --user stop qwen38.service 2>/dev/null || true

step "通常版・Uncensored版とVision Projectorを取得"
mkdir -p "$MODEL_DIR"
download_model "$MODEL_REPO" "$MODEL_REVISION" "$MODEL_FILE"
download_model "$MODEL_REPO" "$MODEL_REVISION" "$MODEL_VISION_FILE"
download_model "$UNCENSORED_MODEL_REPO" "$UNCENSORED_MODEL_REVISION" "$UNCENSORED_MODEL_FILE"
download_model "$UNCENSORED_MODEL_REPO" "$UNCENSORED_MODEL_REVISION" "$UNCENSORED_MODEL_VISION_FILE"

step "Router model presets"
mkdir -p "$PRESET_DIR"

# Uncensored版の埋め込みテンプレートは複数system messageを拒否するため、
# Codexで動作する通常版GGUFのテンプレートを共用する。
uvx --from gguf python -c '
import sys
from gguf import GGUFReader

field = GGUFReader(sys.argv[1]).fields["tokenizer.chat_template"]
sys.stdout.write(bytes(field.parts[-1]).decode("utf-8"))
' "$MODEL_DIR/$MODEL_FILE" > "$CHAT_TEMPLATE_FILE.tmp"
mv "$CHAT_TEMPLATE_FILE.tmp" "$CHAT_TEMPLATE_FILE"

cat > "$PRESET_FILE" <<EOF
version = 1

[Qwen3.8-27B-UD-Q4_K_M]
model = $MODEL_DIR/$MODEL_FILE
mmproj = $MODEL_DIR/$MODEL_VISION_FILE

[Qwen3.8-27B-Uncensored-Q4_K_M]
model = $MODEL_DIR/$UNCENSORED_MODEL_FILE
mmproj = $MODEL_DIR/$UNCENSORED_MODEL_VISION_FILE
chat-template-file = $CHAT_TEMPLATE_FILE
EOF

step "systemd user service"
mkdir -p "$SERVICE_DIR"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Qwen3.8-27B model router (llama.cpp)
After=network-online.target
Wants=network-online.target
Conflicts=comfyui.service

[Service]
Type=simple
Environment=LD_LIBRARY_PATH=$HOME/.local/lib/nvidia
ExecStart=$HOME/.nix-profile/bin/llama-server \\
  --models-preset $PRESET_FILE \\
  --models-max 1 \\
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

ok "Qwen3.8 model routerを起動しました: http://127.0.0.1:$PORT"

if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
  step "Qwen Web UIをTailscale Serveで公開"
  tailscale serve --bg --https="$TAILSCALE_HTTPS_PORT" "http://127.0.0.1:$PORT"
  ok "tailnet内のHTTPS $TAILSCALE_HTTPS_PORT 番で公開しました"
else
  echo "Tailscaleが未接続のため、Web UIのtailnet公開はスキップしました" >&2
fi

echo "状態: ai-mode status"
echo "Qwenへ切替: ai-mode qwen"
echo "ComfyUIへ切替: ai-mode comfy"
echo "ログ: journalctl --user -u qwen38 -f"
