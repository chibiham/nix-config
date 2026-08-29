#!/usr/bin/env bash
# RTX 3090向けAnima LoRA学習環境を専用uv環境へ導入する。
set -euo pipefail

DIFFUSION_PIPE_DIR="${DIFFUSION_PIPE_DIR:-$HOME/diffusion-pipe}"
DIFFUSION_PIPE_REPO="https://github.com/bluvoll/diffusion-pipe.git"
COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
QWEN_DIR="$DIFFUSION_PIPE_DIR/models/Qwen3-0.6B"
CONFIG_DIR="$DIFFUSION_PIPE_DIR/configs/local"
DATASET_DIR="$DIFFUSION_PIPE_DIR/datasets/anima-lora"
OUTPUT_DIR="$DIFFUSION_PIPE_DIR/output/anima-lora"

export UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-300}"
export UV_HTTP_RETRIES="${UV_HTTP_RETRIES:-5}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "このスクリプトはLinux専用です" >&2
  exit 1
fi

for command in git uv nvidia-smi nvcc; do
  if ! command -v "$command" >/dev/null; then
    echo "必要なコマンドがありません: $command" >&2
    exit 1
  fi
done

if ! nvidia-smi >/dev/null 2>&1; then
  echo "NVIDIAドライバが動作していません" >&2
  exit 1
fi

step "diffusion-pipeソース"
if [[ -d "$DIFFUSION_PIPE_DIR/.git" ]]; then
  git -C "$DIFFUSION_PIPE_DIR" submodule update --init --recursive
  ok "$DIFFUSION_PIPE_DIR は取得済みです（自動更新はしません）"
elif [[ -e "$DIFFUSION_PIPE_DIR" ]]; then
  echo "$DIFFUSION_PIPE_DIR は存在しますがGitリポジトリではありません" >&2
  exit 1
else
  git clone --recurse-submodules "$DIFFUSION_PIPE_REPO" "$DIFFUSION_PIPE_DIR"
fi

step "Python 3.12専用環境"
if [[ ! -x "$DIFFUSION_PIPE_DIR/.venv/bin/python" ]]; then
  uv venv --python 3.12 "$DIFFUSION_PIPE_DIR/.venv"
fi

step "PyTorch（CUDA 12.8）"
uv pip install \
  --python "$DIFFUSION_PIPE_DIR/.venv/bin/python" \
  torch==2.9.1 torchvision \
  --index-url https://download.pytorch.org/whl/cu128

step "diffusion-pipe依存パッケージ"
uv pip install \
  --python "$DIFFUSION_PIPE_DIR/.venv/bin/python" \
  -r "$DIFFUSION_PIPE_DIR/requirements.txt" \
  opencv-python-headless \
  scipy

step "Qwen3-0.6Bテキストエンコーダー"
if [[ -f "$QWEN_DIR/config.json" ]] && [[ -f "$QWEN_DIR/tokenizer.json" ]]; then
  ok "$QWEN_DIR は取得済みです"
else
  "$DIFFUSION_PIPE_DIR/.venv/bin/python" - <<PY
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="Qwen/Qwen3-0.6B",
    local_dir="$QWEN_DIR",
)
PY
fi

TRANSFORMER="$COMFY_DIR/models/diffusion_models/anima/miaomiaoHarem_anima16.safetensors"
VAE="$COMFY_DIR/models/vae/qwen/qwen_image_vae.safetensors"
for model in "$TRANSFORMER" "$VAE"; do
  if [[ ! -f "$model" ]]; then
    echo "必要なモデルがありません: $model" >&2
    exit 1
  fi
done

step "Anima LoRA初期設定"
mkdir -p "$CONFIG_DIR" "$DATASET_DIR/images" "$OUTPUT_DIR"
for pattern in ".venv/" "configs/local/" "datasets/anima-lora/" "models/Qwen3-0.6B/" "output/"; do
  grep -qxF "$pattern" "$DIFFUSION_PIPE_DIR/.git/info/exclude" || printf '%s\n' "$pattern" >> "$DIFFUSION_PIPE_DIR/.git/info/exclude"
done
if [[ ! -f "$DATASET_DIR/dataset.toml" ]]; then
  install -Dm644 /dev/stdin "$DATASET_DIR/dataset.toml" <<PATCH
resolutions = [768]
enable_ar_bucket = true
min_ar = 0.5
max_ar = 2.0
num_ar_buckets = 7

[[directory]]
path = '$DATASET_DIR/images'
num_repeats = 1
PATCH
fi

if [[ ! -f "$CONFIG_DIR/anima-lora.toml" ]]; then
  install -Dm644 /dev/stdin "$CONFIG_DIR/anima-lora.toml" <<PATCH
output_dir = '$OUTPUT_DIR'
dataset = '$DATASET_DIR/dataset.toml'

epochs = 20
micro_batch_size_per_gpu = 1
pipeline_stages = 1
gradient_accumulation_steps = 1
gradient_clipping = 1.0
warmup_steps = 10
activation_checkpointing = 'unsloth'
save_every_n_epochs = 1
checkpoint_every_n_minutes = 60
save_dtype = 'bfloat16'
caching_batch_size = 1

[model]
type = 'anima'
transformer_path = '$TRANSFORMER'
vae_path = '$VAE'
qwen_path = '$QWEN_DIR'
dtype = 'bfloat16'
timestep_sample_method = 'logit_normal'
sigmoid_scale = 1.0
shift = 3.0
cache_text_embeddings = true
shuffle_tags = false
caption_dropout_percent = 0.05
caption_mode = 'tags'
train_self_attn = true
train_cross_attn = true
train_mlp = true
train_adaln = false
train_llm_adapter = false
qwen_nf4 = false

[adapter]
type = 'lora'
rank = 16
dtype = 'bfloat16'

[optimizer]
type = 'AdamW8bitKahan'
lr = 5e-5
betas = [0.9, 0.99]
weight_decay = 0.01
eps = 1e-8

[monitoring]
enable_wandb = false
PATCH
fi

step "CUDA動作確認"
"$DIFFUSION_PIPE_DIR/.venv/bin/python" - <<'PY'
import torch

if not torch.cuda.is_available():
    raise SystemExit("PyTorchからCUDAを利用できません")
print(f"PyTorch: {torch.__version__}")
print(f"CUDA runtime: {torch.version.cuda}")
print(f"GPU: {torch.cuda.get_device_name(0)}")
print(f"VRAM: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GiB")
PY

echo
ok "diffusion-pipeのAnima LoRA学習環境を構築しました"
echo "画像: $DATASET_DIR/images"
echo "設定: $CONFIG_DIR/anima-lora.toml"
echo "実行:"
echo "  cd $DIFFUSION_PIPE_DIR"
echo "  PYTORCH_ALLOC_CONF=expandable_segments:True NCCL_P2P_DISABLE=1 NCCL_IB_DISABLE=1 .venv/bin/deepspeed --num_gpus=1 train.py --deepspeed --config '$CONFIG_DIR/anima-lora.toml'"
