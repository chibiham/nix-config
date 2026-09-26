#!/usr/bin/env bash
# Qwen3.8-27Bの通常版・Uncensored版とQwen3.8-Flash-Nextを取得し、切替可能なuser serviceを構成する。
set -euo pipefail

MODEL_REPO="unsloth/Qwen3.8-27B-GGUF"
MODEL_REVISION="4ca720788d1e01f1bff70c033e0d0028fd02e502"
MODEL_FILE="Qwen3.8-27B-UD-Q4_K_M.gguf"
MODEL_XL_FILE="Qwen3.8-27B-UD-Q4_K_XL.gguf"
MODEL_VISION_FILE="mmproj-BF16.gguf"
UNCENSORED_MODEL_REPO="JonathanColetti/Qwen3.8-27B-Uncensored-GGUF"
UNCENSORED_MODEL_REVISION="b7ff25715ee2ae49c9ff32159bc73de864648aef"
UNCENSORED_MODEL_FILE="Qwen3.8-27B-Uncensored-Q4_K_M.gguf"
UNCENSORED_MODEL_VISION_FILE="Qwen3.8-27B-Uncensored-vision-bf16.gguf"
HERETIC_MODEL_REPO="OS-Software/Qwen3.8-27B-Uncensored-Heretic-v2-GGUF"
HERETIC_MODEL_REVISION="f4dc8fb5115f21b55b0d093660ef32bb7303369a"
HERETIC_MODEL_FILE="Qwen3.8-27B-Uncensored-Heretic-v2-UD-Q4_K_XL.gguf"
HERETIC_MODEL_VISION_REMOTE_FILE="mmproj-BF16.gguf"
HERETIC_MODEL_VISION_FILE="Qwen3.8-27B-Uncensored-Heretic-v2-mmproj-BF16.gguf"
# Qwen3.8-Flash-Next（125B-A6B MoE + 51B n-gram埋め込み）。llama.cpp v0.5.0以降が必要。
# Q3_K_XLはエキスパートの一部をGPU、残りをRAMに置いて62GB RAM + 24GB VRAMに収まる上限。
# n-gram埋め込み（per_layer_token_embd）は1トークンあたり数行しか読まないのでmmapのままでよい。
FLASH_MODEL_REPO="unsloth/Qwen3.8-Flash-Next-GGUF"
FLASH_MODEL_REVISION="38bb39ee97821de2c9009abb7e93950eec396e66"
FLASH_MODEL_QUANT="UD-Q3_K_XL"
FLASH_MODEL_SHARDS=3
FLASH_MODEL_VISION_FILE="mmproj-BF16.gguf"
# エキスパートをRAMへ置く層数（48層中）。ubatch 2048の計算バッファ（約4GB）と128K ctxを含めて
# VRAM 24GBに収まる実測値。ubatchを512から上げるとprompt処理が約100→480 tok/sになる（生成は約21 tok/s）。
FLASH_N_CPU_MOE="${QWEN_FLASH_N_CPU_MOE:-38}"
FLASH_UBATCH_SIZE="${QWEN_FLASH_UBATCH_SIZE:-2048}"
MODEL_DIR="${QWEN_MODEL_DIR:-$HOME/models/qwen3.8-27b}"
FLASH_MODEL_DIR="${QWEN_FLASH_MODEL_DIR:-$HOME/models/qwen3.8-flash-next}"
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
  local repo="$1" revision="$2" file="$3" output="${4:-$3}" dir="${5:-$MODEL_DIR}"
  local path="$dir/$output"
  if [[ -s "$path" ]]; then
    ok "$path は取得済みです"
    return
  fi

  aria2c --continue=true --max-connection-per-server=16 --split=16 \
    --min-split-size=16M --max-tries=0 --retry-wait=5 \
    --dir="$dir" --out="$output.part" \
    "https://huggingface.co/$repo/resolve/$revision/$file"
  mv "$path.part" "$path"
  ok "$path を取得しました"
}

step "ComfyUIとQwenを停止"
systemctl --user stop comfyui.service 2>/dev/null || true
systemctl --user stop qwen38.service 2>/dev/null || true

step "通常版Q4_K_M・Q4_K_XL、Uncensored 2種とVision Projectorを取得"
mkdir -p "$MODEL_DIR"
download_model "$MODEL_REPO" "$MODEL_REVISION" "$MODEL_FILE"
download_model "$MODEL_REPO" "$MODEL_REVISION" "$MODEL_XL_FILE"
download_model "$MODEL_REPO" "$MODEL_REVISION" "$MODEL_VISION_FILE"
download_model "$UNCENSORED_MODEL_REPO" "$UNCENSORED_MODEL_REVISION" "$UNCENSORED_MODEL_FILE"
download_model "$UNCENSORED_MODEL_REPO" "$UNCENSORED_MODEL_REVISION" "$UNCENSORED_MODEL_VISION_FILE"
download_model "$HERETIC_MODEL_REPO" "$HERETIC_MODEL_REVISION" "$HERETIC_MODEL_FILE"
download_model "$HERETIC_MODEL_REPO" "$HERETIC_MODEL_REVISION" "$HERETIC_MODEL_VISION_REMOTE_FILE" "$HERETIC_MODEL_VISION_FILE"

step "Qwen3.8-Flash-Next $FLASH_MODEL_QUANT とVision Projectorを取得"
mkdir -p "$FLASH_MODEL_DIR"
flash_shard() { printf 'Qwen3.8-Flash-Next-%s-%05d-of-%05d.gguf' "$FLASH_MODEL_QUANT" "$1" "$FLASH_MODEL_SHARDS"; }
for ((i = 1; i <= FLASH_MODEL_SHARDS; i++)); do
  shard="$(flash_shard "$i")"
  download_model "$FLASH_MODEL_REPO" "$FLASH_MODEL_REVISION" "$FLASH_MODEL_QUANT/$shard" "$shard" "$FLASH_MODEL_DIR"
done
download_model "$FLASH_MODEL_REPO" "$FLASH_MODEL_REVISION" "$FLASH_MODEL_VISION_FILE" "$FLASH_MODEL_VISION_FILE" "$FLASH_MODEL_DIR"

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

[Qwen3.8-27B-UD-Q4_K_XL]
model = $MODEL_DIR/$MODEL_XL_FILE
mmproj = $MODEL_DIR/$MODEL_VISION_FILE

[Qwen3.8-27B-Uncensored-Q4_K_M]
model = $MODEL_DIR/$UNCENSORED_MODEL_FILE
mmproj = $MODEL_DIR/$UNCENSORED_MODEL_VISION_FILE
chat-template-file = $CHAT_TEMPLATE_FILE

[Qwen3.8-27B-Uncensored-Heretic-v2-UD-Q4_K_XL]
model = $MODEL_DIR/$HERETIC_MODEL_FILE
mmproj = $MODEL_DIR/$HERETIC_MODEL_VISION_FILE

[Qwen3.8-Flash-Next-$FLASH_MODEL_QUANT]
model = $FLASH_MODEL_DIR/$(flash_shard 1)
mmproj = $FLASH_MODEL_DIR/$FLASH_MODEL_VISION_FILE
n-cpu-moe = $FLASH_N_CPU_MOE
batch-size = $FLASH_UBATCH_SIZE
ubatch-size = $FLASH_UBATCH_SIZE
EOF

step "systemd user service"
mkdir -p "$SERVICE_DIR"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Qwen3.8 model router (llama.cpp)
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
