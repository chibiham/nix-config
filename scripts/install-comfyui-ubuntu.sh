#!/usr/bin/env bash
# NVIDIA GPU（chibihamuntu: RTX 3090、dekahamuntu: RTX 5060 Ti ×2）向けComfyUIを専用uv環境へ導入し、
# localhost限定で自動起動する。使うGPUは hosts/ubuntu/<ホスト名>.env の COMFY_CUDA_DEVICES。
#
#   install-comfyui-ubuntu.sh               apt・clone・venv・PyTorch・依存・unit・linger（sudo が要る）
#   install-comfyui-ubuntu.sh --unit-only [--force]
#       CUDA動作確認と unit の書き出しだけ（sudo なし）。unit が変わったとき・前回の適用が途中で終わったとき
#       （~/.local/state/comfyui-update/unit-apply-pending が残っている）・comfyui.service が動いていないときだけ、
#       daemon-reload・restart・起動の待ちをする。途中で失敗したら終了コード 1 で、流し直せば続きから適用する。
#       restart の前に ComfyUI のキューが空かを確かめる（--force で飛ばす）。
#
# 新しく clone するときだけ、COMFY_REF（空でなければ）の版を checkout する。取得済みなら触らない（更新は update-comfyui-ubuntu.sh）。
set -euo pipefail

# shellcheck source=lib/ubuntu-host.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/ubuntu-host.sh"
# shellcheck source=lib/comfyui.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/comfyui.sh"

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

unit_only=0
force=0
while (($# > 0)); do
  case "$1" in
    --unit-only) unit_only=1; shift ;;
    --force) force=1; shift ;;
    *)
      echo "usage: install-comfyui-ubuntu.sh [--unit-only [--force]]" >&2
      exit 2
      ;;
  esac
done
if [[ "$force" == 1 && "$unit_only" == 0 ]]; then
  echo "--force は --unit-only と一緒に使います" >&2
  exit 2
fi

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

if [[ "$unit_only" == 1 ]]; then
  if [[ ! -x "$COMFY_DIR/.venv/bin/python" ]]; then
    echo "$COMFY_DIR/.venv がありません。--unit-only は導入済みのComfyUIにだけ使えます" >&2
    exit 1
  fi
  warn "--unit-only: apt・clone・venv・PyTorch・依存・linger は飛ばします"
else
  step "OS依存パッケージ"
  sudo apt-get update
  # Animaなどで使われるTritonは、初回実行時にホスト側のCコードを
  # コンパイルする。systemdサービスからも確実に利用できるよう、
  # OS標準のコンパイラ一式とPython開発ヘッダを導入する。
  sudo apt-get install -y build-essential ffmpeg git-lfs libgl1 libglib2.0-0 python3.12-dev
  git lfs install --skip-repo

  step "ComfyUIソース"
  if [[ -d "$COMFY_DIR/.git" ]]; then
    ok "$COMFY_DIR は取得済みです（自動更新はしません）"
  elif [[ -e "$COMFY_DIR" ]]; then
    echo "$COMFY_DIR は存在しますがGitリポジトリではありません" >&2
    exit 1
  else
    git clone "$COMFY_REPO" "$COMFY_DIR"
    if [[ -n "$COMFY_REF" ]]; then
      git -C "$COMFY_DIR" checkout --detach "$COMFY_REF^{commit}"
      ok "ComfyUI: $(git -C "$COMFY_DIR" describe --tags --always)（COMFY_REF=$COMFY_REF）"
    fi
  fi

  step "Python 3.12専用環境"
  if [[ ! -x "$COMFY_DIR/.venv/bin/python" ]]; then
    uv venv --python 3.12 "$COMFY_DIR/.venv"
  fi

  # cu130のwheelはsm_86（3090）とsm_120（Blackwell、RTX 50）の両方を含む。
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
fi

step "CUDA動作確認"
cuda_env=()
if [[ -n "$COMFY_CUDA_DEVICES" ]]; then
  cuda_env=(CUDA_DEVICE_ORDER=PCI_BUS_ID "CUDA_VISIBLE_DEVICES=$COMFY_CUDA_DEVICES")
  echo "ComfyUIに見せるGPU: $COMFY_CUDA_DEVICES"
fi
env "${cuda_env[@]}" "$COMFY_DIR/.venv/bin/python" - <<'PY'
import torch

if not torch.cuda.is_available():
    raise SystemExit("PyTorchからCUDAを利用できません")
print(f"PyTorch: {torch.__version__}")
print(f"CUDA runtime: {torch.version.cuda}")
for i in range(torch.cuda.device_count()):
    props = torch.cuda.get_device_properties(i)
    print(f"GPU {i}: {props.name} sm_{props.major}{props.minor}")
    print(f"VRAM: {props.total_memory / 1024**3:.1f} GiB")
# ComfyUIは、ノードで指定しない限り既定のデバイスだけを使う（CUDA_VISIBLE_DEVICES の最初のGPU）
default = torch.cuda.current_device()
print(f"既定のデバイス: cuda:{default} = {torch.cuda.get_device_name(default)}")
PY

# 同じGPUを別のサービスと分けるときだけ書く（chibihamuntuでは書かない）
cuda_unit_lines=""
if [[ -n "$COMFY_CUDA_DEVICES" ]]; then
  cuda_unit_lines="Environment=CUDA_DEVICE_ORDER=PCI_BUS_ID
Environment=CUDA_VISIBLE_DEVICES=$COMFY_CUDA_DEVICES
"
fi

step "systemd user service"
mkdir -p "$SERVICE_DIR"
# 起動オプションの追加は hosts/ubuntu/<ホスト名>.env の COMFY_EXTRA_ARGS（既定は空）。
# 例: --fast fp16_accumulation（fp16の行列積・畳み込みをfp16で累積する。RTX 3090では約2倍のスループット、
# Blackwellでは未計測。絵がわずかに変わることがあるので、chibihamuntu・dekahamuntu とも付けていない）。
# https://blog.comfy.org/p/making-the-minimax-h3-video-vae-2x
# unit の中身を標準出力に書く（--unit-only は今のファイルと比べる）
write_unit() {
  cat <<EOF
[Unit]
Description=ComfyUI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$COMFY_DIR
Environment=CC=/usr/bin/cc
Environment=CXX=/usr/bin/c++
${cuda_unit_lines}ExecStart=$COMFY_DIR/.venv/bin/python $COMFY_DIR/main.py --listen 127.0.0.1 --port 8188 --enable-manager${COMFY_EXTRA_ARGS:+ $COMFY_EXTRA_ARGS}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
}

if [[ "$unit_only" == 1 ]]; then
  # 適用の途中であることの印。unit を書く直前に置き、daemon-reload・restart・起動の待ちが全部通ったら消す。
  # 途中で失敗すると残り、流し直したときにファイルが同じでも続きから適用する
  pending_file="${XDG_STATE_HOME:-$HOME/.local/state}/comfyui-update/unit-apply-pending"
  unit_same=0
  if [[ -f "$SERVICE_FILE" ]] && cmp -s <(write_unit) "$SERVICE_FILE"; then
    unit_same=1
  fi
  service_active=0
  if systemctl --user is-active --quiet comfyui.service; then
    service_active=1
  fi
  if [[ "$unit_same" == 1 && ! -e "$pending_file" && "$service_active" == 1 ]]; then
    ok "$SERVICE_FILE は変わらず、comfyui.service は動いています。何もしません"
    exit 0
  fi
  if [[ "$unit_same" == 0 && -f "$SERVICE_FILE" ]]; then
    diff -u "$SERVICE_FILE" <(write_unit) || true
  fi
  if [[ -e "$pending_file" ]]; then
    warn "前回の適用が途中で終わっています（$pending_file、$(cat "$pending_file" 2>/dev/null)）。続きから適用します"
  fi
  if [[ "$service_active" == 0 ]]; then
    warn "comfyui.service が動いていません。起動し直します"
  fi
  # 書き換える前に確かめる
  if [[ "$force" == 1 ]]; then
    warn "ComfyUI のキューを確かめません（--force）"
  else
    comfy_queue_is_idle 8188 || exit 1
  fi
  unit_apply_failed() {
    echo "失敗した段: $1。原因を直して同じコマンドを流し直せば、続きから適用します（印: $pending_file）" >&2
    exit 1
  }
  mkdir -p "$(dirname "$pending_file")"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$pending_file"
  if [[ "$unit_same" == 0 ]]; then
    write_unit > "$SERVICE_FILE" || unit_apply_failed "unit の書き出し"
  fi
  systemctl --user daemon-reload || unit_apply_failed "systemctl --user daemon-reload"
  systemctl --user restart comfyui.service || unit_apply_failed "systemctl --user restart comfyui.service"
  comfy_wait_ready 8188 "${COMFY_READY_TIMEOUT:-180}" || unit_apply_failed "起動の待ち"
  rm -f "$pending_file"
  ok "unit を適用して ComfyUI を起動し直しました"
  exit 0
fi

write_unit > "$SERVICE_FILE"

systemctl --user daemon-reload
systemctl --user enable --now comfyui.service

# ログイン前からuser serviceを起動できるようにする。再実行しても同じ状態へ収束する。
sudo loginctl enable-linger "$USER"

echo
ok "ComfyUIをインストールして起動しました"
echo "状態: systemctl --user status comfyui --no-pager"
echo "ログ: journalctl --user -u comfyui -f"
echo
echo "同じtailnetの全端末から利用する設定:"
echo "  ~/.config/nix-config/scripts/configure-comfyui-tailscale-serve.sh"
echo
warn "モデルは自動ダウンロードしていません。$COMFY_DIR/models/ 以下へ配置してください"
