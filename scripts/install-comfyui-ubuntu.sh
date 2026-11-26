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
#   install-comfyui-ubuntu.sh --remove <名前> [--force]
#       設定（COMFY_EXTRA_INSTANCES）から外した 2 つ目以降の常駐（comfyui-<名前>.service）を止め、disable して unit を消す（sudo なし）。
#       止める前にその常駐のキューが空かを確かめる（--force で飛ばす）。このスクリプトが書いた unit だけを消す。
#
# 2 つ目以降の常駐（COMFY_EXTRA_INSTANCES。例: "gpu1:8189:1"）は、comfyui.service と同じ置き場（コード・venv・models・custom_nodes・
# user・input・output）から、見せる GPU・ポート・temp だけを変えて起こす（comfyui-<名前>.service）。ComfyUI-Manager は付けない。
# --unit-only は、2 つ目以降にも comfyui.service と同じ決まり（同じなら何もしない・違えば差を出してキューを確かめて書く）で効く。
# 書かないホスト（chibihamuntu）では、comfyui.service の中身も出力も今までと同じ。
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
# 2 つ目以降の unit の頭に置く印。--remove と「設定にない unit」の警告は、この印のある unit だけを扱う
EXTRA_UNIT_MARK="# install-comfyui-ubuntu.sh が COMFY_EXTRA_INSTANCES から書く"

# NVIDIA/PyTorchのwheelは数百MBになるため、低速・不安定な回線でも完走できる値にする。
# 呼び出し側で環境変数を指定すれば上書き可能。
export UV_HTTP_TIMEOUT="${UV_HTTP_TIMEOUT:-300}"
export UV_HTTP_RETRIES="${UV_HTTP_RETRIES:-5}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

usage() {
  echo "usage: install-comfyui-ubuntu.sh [--unit-only [--force]]" >&2
  echo "       install-comfyui-ubuntu.sh --remove <名前> [--force]" >&2
  exit 2
}

unit_only=0
force=0
remove_name=""
while (($# > 0)); do
  case "$1" in
    --unit-only) unit_only=1; shift ;;
    --force) force=1; shift ;;
    --remove) [[ $# -ge 2 && -n "$2" ]] || usage; remove_name="$2"; shift 2 ;;
    *) usage ;;
  esac
done
if [[ -n "$remove_name" && "$unit_only" == 1 ]]; then
  echo "--remove と --unit-only は一緒に使いません" >&2
  exit 2
fi
if [[ "$force" == 1 && "$unit_only" == 0 && -z "$remove_name" ]]; then
  echo "--force は --unit-only と一緒に使います" >&2
  exit 2
fi

# 常駐の一覧。0 番が comfyui.service（8188）、1 番から COMFY_EXTRA_INSTANCES の順
extra_list="$(comfy_extra_instances)" || exit 1
unit_names=(comfyui.service)
unit_files=("$SERVICE_FILE")
unit_ports=(8188)
unit_extra_names=("")
unit_devices=("$COMFY_CUDA_DEVICES")
while read -r name port devices; do
  [[ -n "$name" ]] || continue
  unit_names+=("comfyui-$name.service")
  unit_files+=("$SERVICE_DIR/comfyui-$name.service")
  unit_ports+=("$port")
  unit_extra_names+=("$name")
  unit_devices+=("$devices")
done <<<"$extra_list"
unit_count=${#unit_names[@]}

# 印のある comfyui-*.service のうち、いまの設定にないものの名前（comfyui-<名前>.service の <名前>）を 1 行ずつ
stale_extra_names() {
  local file base i known
  for file in "$SERVICE_DIR"/comfyui-*.service; do
    [[ -f "$file" ]] || continue
    grep -qxF "$EXTRA_UNIT_MARK" "$file" || continue
    base="$(basename "$file" .service)"
    known=0
    for ((i = 1; i < unit_count; i++)); do
      [[ "${unit_names[$i]}" == "$base.service" ]] && known=1
    done
    ((known)) || printf '%s\n' "${base#comfyui-}"
  done
}
warn_stale_extras() {
  local name
  while read -r name; do
    [[ -n "$name" ]] || continue
    warn "設定（COMFY_EXTRA_INSTANCES）にない常駐の unit があります: $SERVICE_DIR/comfyui-$name.service。止めて消すなら: install-comfyui-ubuntu.sh --remove $name"
  done < <(stale_extra_names)
}

if [[ "$(uname -s)" != "Linux" ]] || ! command -v apt-get >/dev/null; then
  echo "このスクリプトはUbuntu/Debian系Linux専用です" >&2
  exit 1
fi

if [[ -n "$remove_name" ]]; then
  if [[ ! "$remove_name" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "名前は英小文字・数字・- で書きます（comfyui-<名前>.service の <名前>）: $remove_name" >&2
    exit 2
  fi
  remove_unit="comfyui-$remove_name.service"
  remove_file="$SERVICE_DIR/$remove_unit"
  for ((i = 1; i < unit_count; i++)); do
    if [[ "${unit_names[$i]}" == "$remove_unit" ]]; then
      echo "$remove_name はまだ COMFY_EXTRA_INSTANCES（hosts/ubuntu/$UBUNTU_HOST.env）にあります。先に設定から外してください" >&2
      exit 1
    fi
  done
  if [[ ! -f "$remove_file" ]]; then
    ok "$remove_file はありません。何もしません"
    exit 0
  fi
  if ! grep -qxF "$EXTRA_UNIT_MARK" "$remove_file"; then
    echo "$remove_file はこのスクリプトが書いた unit ではありません（印がない）。何も変えずに止めます" >&2
    exit 1
  fi
  if [[ "$force" == 1 ]]; then
    warn "ComfyUI のキューを確かめません（--force）"
  else
    remove_port="$(sed -n 's/^ExecStart=.* --port \([0-9][0-9]*\).*/\1/p' "$remove_file")"
    if [[ ! "$remove_port" =~ ^[0-9]+$ ]]; then
      echo "$remove_file からポートを読めませんでした（確かめずに進めるなら --force）" >&2
      exit 1
    fi
    comfy_queue_is_idle "$remove_port" || exit 1
  fi
  systemctl --user disable --now "$remove_unit"
  rm -f "$remove_file"
  systemctl --user daemon-reload
  ok "$remove_unit を止め、disable して unit を消しました"
  echo "temp の置き場（${COMFY_DIR}/temp-${remove_name}）は残っています。要らなければ消してください"
  exit 0
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
# cuda_check [環境変数=値 ...]: その GPU の見せ方で PyTorch から CUDA を使えるかを確かめる
cuda_check() {
  env "$@" "$COMFY_DIR/.venv/bin/python" - <<'PY'
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
}
cuda_env=()
if [[ -n "$COMFY_CUDA_DEVICES" ]]; then
  cuda_env=(CUDA_DEVICE_ORDER=PCI_BUS_ID "CUDA_VISIBLE_DEVICES=$COMFY_CUDA_DEVICES")
  echo "ComfyUIに見せるGPU: $COMFY_CUDA_DEVICES"
fi
cuda_check ${cuda_env[@]+"${cuda_env[@]}"}
for ((i = 1; i < unit_count; i++)); do
  echo "${unit_names[$i]%.service} に見せるGPU: ${unit_devices[$i]}"
  cuda_check CUDA_DEVICE_ORDER=PCI_BUS_ID "CUDA_VISIBLE_DEVICES=${unit_devices[$i]}"
done

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

# 2 つ目以降の unit（write_extra_unit <名前> <ポート> <見せるGPU>）。
# 置き場は comfyui.service と同じ。temp だけ分ける: ComfyUI（v0.45.2 の main.py の start_comfyui）は
# --temp-directory <D> の <D>/temp を temp にし、assets が切のとき起動のたびにそれを消す（app/assets/lifecycle.py の
# cleanup_temp_filesystem、shutil.rmtree）。<ComfyUI>/temp の外の <ComfyUI>/temp-<名前> を渡すので、
# temp は <ComfyUI>/temp-<名前>/temp になり、comfyui.service の temp（<ComfyUI>/temp）とは互いに消し合わない。
# ComfyUI-Manager（--enable-manager）は付けない（ノードの入れ替えは comfyui.service の画面でする）
write_extra_unit() {
  local name="$1" port="$2" devices="$3"
  cat <<EOF
$EXTRA_UNIT_MARK
# 「${name}:${port}:${devices}」。手で直さず、hosts/ubuntu/<ホスト名>.env を変えて install-comfyui-ubuntu.sh --unit-only を流す
[Unit]
Description=ComfyUI ($name, GPU $devices)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$COMFY_DIR
Environment=CC=/usr/bin/cc
Environment=CXX=/usr/bin/c++
Environment=CUDA_DEVICE_ORDER=PCI_BUS_ID
Environment=CUDA_VISIBLE_DEVICES=$devices
ExecStart=$COMFY_DIR/.venv/bin/python $COMFY_DIR/main.py --listen 127.0.0.1 --port $port --temp-directory $COMFY_DIR/temp-$name${COMFY_EXTRA_ARGS:+ $COMFY_EXTRA_ARGS}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
}

# write_unit_at <番号>: 常駐の一覧の <番号> の unit の中身
write_unit_at() {
  if (($1 == 0)); then
    write_unit
  else
    write_extra_unit "${unit_extra_names[$1]}" "${unit_ports[$1]}" "${unit_devices[$1]}"
  fi
}

if [[ "$unit_only" == 1 ]]; then
  # 適用の途中であることの印。unit を書く直前に置き、daemon-reload・restart・起動の待ちが全部通ったら消す。
  # 途中で失敗すると残り、流し直したときにファイルが同じでも続きから適用する（印があれば全部の常駐に適用し直す）
  pending_file="${XDG_STATE_HOME:-$HOME/.local/state}/comfyui-update/unit-apply-pending"
  pending=0
  [[ -e "$pending_file" ]] && pending=1
  # 常駐ごとに: unit が同じか・動いているか・適用が要るか
  unit_same=()
  unit_active=()
  unit_need=()
  need_any=0
  for ((i = 0; i < unit_count; i++)); do
    unit_same[i]=0
    if [[ -f "${unit_files[$i]}" ]] && cmp -s <(write_unit_at "$i") "${unit_files[$i]}"; then
      unit_same[i]=1
    fi
    unit_active[i]=0
    if systemctl --user is-active --quiet "${unit_names[$i]}"; then
      unit_active[i]=1
    fi
    unit_need[i]=0
    if [[ "${unit_same[$i]}" == 0 || "$pending" == 1 || "${unit_active[$i]}" == 0 ]]; then
      unit_need[i]=1
      need_any=1
    fi
  done
  if [[ "$need_any" == 0 ]]; then
    for ((i = 0; i < unit_count; i++)); do
      ok "${unit_files[$i]} は変わらず、${unit_names[$i]} は動いています。何もしません"
    done
    warn_stale_extras
    exit 0
  fi
  for ((i = 0; i < unit_count; i++)); do
    if [[ "${unit_same[$i]}" == 0 && -f "${unit_files[$i]}" ]]; then
      diff -u "${unit_files[$i]}" <(write_unit_at "$i") || true
    elif [[ "${unit_same[$i]}" == 0 ]] && ((i > 0)); then
      warn "${unit_files[$i]} はまだありません。書いて enable し、起動します"
    fi
  done
  if [[ "$pending" == 1 ]]; then
    warn "前回の適用が途中で終わっています（$pending_file、$(cat "$pending_file" 2>/dev/null)）。続きから適用します"
  fi
  for ((i = 0; i < unit_count; i++)); do
    if [[ "${unit_need[$i]}" == 1 && "${unit_active[$i]}" == 0 ]]; then
      warn "${unit_names[$i]} が動いていません。起動し直します"
    fi
  done
  # 書き換える前に確かめる（起こし直す常駐だけ）
  if [[ "$force" == 1 ]]; then
    warn "ComfyUI のキューを確かめません（--force）"
  else
    for ((i = 0; i < unit_count; i++)); do
      [[ "${unit_need[$i]}" == 1 ]] || continue
      if ((unit_count > 1)); then
        echo "${unit_names[$i]}（127.0.0.1:${unit_ports[$i]}）:"
      fi
      comfy_queue_is_idle "${unit_ports[$i]}" || exit 1
    done
  fi
  # 失敗の段に添える unit の名前（常駐が 1 つのときは添えない。今までと同じ表示）
  unit_label() {
    if ((unit_count > 1)); then
      printf '（%s）' "${unit_names[$1]}"
    fi
  }
  unit_apply_failed() {
    echo "失敗した段: $1。原因を直して同じコマンドを流し直せば、続きから適用します（印: $pending_file）" >&2
    exit 1
  }
  mkdir -p "$(dirname "$pending_file")"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$pending_file"
  for ((i = 0; i < unit_count; i++)); do
    if [[ "${unit_need[$i]}" == 1 && "${unit_same[$i]}" == 0 ]]; then
      write_unit_at "$i" > "${unit_files[$i]}" || unit_apply_failed "unit の書き出し$(unit_label "$i")"
    fi
  done
  systemctl --user daemon-reload || unit_apply_failed "systemctl --user daemon-reload"
  for ((i = 0; i < unit_count; i++)); do
    [[ "${unit_need[$i]}" == 1 ]] || continue
    # 2 つ目以降は、新しく足したときのために enable もする（何度流しても同じ）。comfyui.service は導入のときに enable 済み
    if ((i > 0)); then
      systemctl --user enable "${unit_names[$i]}" || unit_apply_failed "systemctl --user enable ${unit_names[$i]}"
    fi
    systemctl --user restart "${unit_names[$i]}" || unit_apply_failed "systemctl --user restart ${unit_names[$i]}"
  done
  for ((i = 0; i < unit_count; i++)); do
    [[ "${unit_need[$i]}" == 1 ]] || continue
    comfy_wait_ready "${unit_ports[$i]}" "${COMFY_READY_TIMEOUT:-180}" "${unit_names[$i]%.service}" || unit_apply_failed "起動の待ち$(unit_label "$i")"
  done
  rm -f "$pending_file"
  ok "unit を適用して ComfyUI を起動し直しました"
  warn_stale_extras
  exit 0
fi

write_unit > "$SERVICE_FILE"
for ((i = 1; i < unit_count; i++)); do
  write_unit_at "$i" > "${unit_files[$i]}"
done

systemctl --user daemon-reload
systemctl --user enable --now comfyui.service
for ((i = 1; i < unit_count; i++)); do
  systemctl --user enable --now "${unit_names[$i]}"
done

# ログイン前からuser serviceを起動できるようにする。再実行しても同じ状態へ収束する。
sudo loginctl enable-linger "$USER"

echo
ok "ComfyUIをインストールして起動しました"
echo "状態: systemctl --user status comfyui --no-pager"
echo "ログ: journalctl --user -u comfyui -f"
for ((i = 1; i < unit_count; i++)); do
  echo "2 つ目以降の常駐: ${unit_names[$i]}（127.0.0.1:${unit_ports[$i]}、GPU ${unit_devices[$i]}）"
done
warn_stale_extras
echo
echo "同じtailnetの全端末から利用する設定:"
echo "  ~/.config/nix-config/scripts/configure-comfyui-tailscale-serve.sh"
echo
warn "モデルは自動ダウンロードしていません。$COMFY_DIR/models/ 以下へ配置してください"
