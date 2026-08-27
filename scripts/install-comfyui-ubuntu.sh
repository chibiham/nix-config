#!/usr/bin/env bash
# RTX 3090向けComfyUIを専用uv環境へ導入し、localhost限定で自動起動する。
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
COMFY_REPO="https://github.com/comfy-org/ComfyUI.git"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/comfyui.service"

# NVIDIA/PyTorchのwheelは数百MBになるため、低速・不安定な回線でも完走できる値にする。
# 呼び出し側で環境変数を指定すれば上書き可能。
export UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-300}"
export UV_HTTP_RETRIES="${UV_HTTP_RETRIES:-5}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Linux" ]] || ! command -v apt-get >/dev/null; then
  echo "このスクリプトはUbuntu/Debian系Linux専用です" >&2
  exit 1
fi

for command in git uv nvidia-smi; do
  if ! command -v "$command" >/dev/null; then
    echo "必要なコマンドがありません: $command" >&2
    exit 1
  fi
done

if ! nvidia-smi >/dev/null 2>&1; then
  echo "NVIDIAドライバが動作していません。先にinstall-nvidia-driver-ubuntu.shを実行し、再起動してください" >&2
  exit 1
fi

step "OS依存パッケージ"
sudo apt-get update
sudo apt-get install -y ffmpeg git-lfs libgl1 libglib2.0-0
git lfs install --skip-repo

step "ComfyUIソース"
if [[ -d "$COMFY_DIR/.git" ]]; then
  ok "$COMFY_DIR は取得済みです（自動更新はしません）"
elif [[ -e "$COMFY_DIR" ]]; then
  echo "$COMFY_DIR は存在しますがGitリポジトリではありません" >&2
  exit 1
else
  git clone "$COMFY_REPO" "$COMFY_DIR"
fi

step "Python 3.12専用環境"
if [[ ! -x "$COMFY_DIR/.venv/bin/python" ]]; then
  uv venv --python 3.12 "$COMFY_DIR/.venv"
fi

step "PyTorch（NVIDIA CUDA 13.0）"
uv pip install \
  --python "$COMFY_DIR/.venv/bin/python" \
  torch torchvision torchaudio \
  --extra-index-url https://download.pytorch.org/whl/cu130

step "ComfyUI依存パッケージ"
uv pip install \
  --python "$COMFY_DIR/.venv/bin/python" \
  -r "$COMFY_DIR/requirements.txt"
if [[ -f "$COMFY_DIR/manager_requirements.txt" ]]; then
  uv pip install \
    --python "$COMFY_DIR/.venv/bin/python" \
    -r "$COMFY_DIR/manager_requirements.txt"
fi

step "CUDA動作確認"
"$COMFY_DIR/.venv/bin/python" - <<'PY'
import torch

if not torch.cuda.is_available():
    raise SystemExit("PyTorchからCUDAを利用できません")
print(f"PyTorch: {torch.__version__}")
print(f"CUDA runtime: {torch.version.cuda}")
print(f"GPU: {torch.cuda.get_device_name(0)}")
print(f"VRAM: {torch.cuda.get_device_properties(0).total_memory / 1024**3:.1f} GiB")
PY

step "systemd user service"
mkdir -p "$SERVICE_DIR"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=ComfyUI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$COMFY_DIR
ExecStart=$COMFY_DIR/.venv/bin/python $COMFY_DIR/main.py --listen 127.0.0.1 --port 8188 --enable-manager
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now comfyui.service

# ログイン前からuser serviceを起動できるようにする。再実行しても同じ状態へ収束する。
sudo loginctl enable-linger "$USER"

echo
ok "ComfyUIをインストールして起動しました"
echo "状態: systemctl --user status comfyui --no-pager"
echo "ログ: journalctl --user -u comfyui -f"
echo
echo "MacからTailscale経由でSSHトンネルを作成:"
echo "  ssh -N -L 8188:127.0.0.1:8188 $USER@<TAILSCALE_IP>"
echo "ブラウザ: http://127.0.0.1:8188"
echo
warn "モデルは自動ダウンロードしていません。$COMFY_DIR/models/ 以下へ配置してください"
