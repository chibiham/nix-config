#!/usr/bin/env bash
# RTX 3090向けApplio（RVCの学習・推論・リアルタイム音声変換）を専用uv環境へ
# 導入し、tailnet内だけにHTTPS公開する。
#
# HTTPSが必須な理由: リアルタイム変換はブラウザのgetUserMediaでマイクを取得し
# WebSocketでサーバへ送る。getUserMediaはセキュアコンテキストでしか動かないため、
# 別マシン（Mac等）から使う場合はTailscale ServeのHTTPSが事実上の前提になる。
# localhost以外の平文HTTPではマイクの許可ダイアログすら出ない。
set -euo pipefail

APPLIO_DIR="${APPLIO_DIR:-$HOME/Applio}"
APPLIO_REPO="https://github.com/IAHispano/Applio.git"
SERVICE_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SERVICE_DIR/applio.service"
PORT="${APPLIO_PORT:-6969}"
TAILSCALE_HTTPS_PORT="${APPLIO_TAILSCALE_HTTPS_PORT:-8444}"

# PyTorchのwheelは数GBになるため、低速・不安定な回線でも完走できる値にする。
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
    echo "先にUbuntu用Home Manager設定を適用してください" >&2
    exit 1
  fi
done

if ! nvidia-smi >/dev/null 2>&1; then
  echo "NVIDIAドライバが動作していません。先にinstall-nvidia-driver-ubuntu.shを実行し、再起動してください" >&2
  exit 1
fi

step "OS依存パッケージ"
# libsndfile1はsoundfile、libportaudio2はsounddeviceのimportに必要。
# このサーバ自身は音を鳴らさないが、Applioが起動時に無条件でimportする。
# sounddeviceはCFFIでlibportaudio.so.2をdlopenするだけなので、
# ヘッダを含むportaudio19-devではなくランタイムだけで足りる。
APT_PACKAGES=(
  build-essential ffmpeg libgl1 libglib2.0-0
  python3.12-dev libsndfile1 libportaudio2
)
# 既に満たされていればsudoを要求しない。再実行を非対話で完走させるため。
# noble以降のlibglib2.0-0はt64版が提供するので、dpkg -sではなくaptに解決させる。
if apt-get install -s "${APT_PACKAGES[@]}" 2>/dev/null | grep -q '^Inst '; then
  sudo apt-get update
  sudo apt-get install -y "${APT_PACKAGES[@]}"
else
  ok "OS依存パッケージは導入済みです"
fi

step "Applioソース"
if [[ -d "$APPLIO_DIR/.git" ]]; then
  ok "$APPLIO_DIR は取得済みです（自動更新はしません）"
elif [[ -e "$APPLIO_DIR" ]]; then
  echo "$APPLIO_DIR は存在しますがGitリポジトリではありません" >&2
  exit 1
else
  git clone "$APPLIO_REPO" "$APPLIO_DIR"
fi

step "Python 3.12専用環境"
if [[ ! -x "$APPLIO_DIR/.venv/bin/python" ]]; then
  uv venv --python 3.12 "$APPLIO_DIR/.venv"
fi

step "PyTorchとApplio依存パッケージ（NVIDIA CUDA 12.8）"
# requirements.txtがtorch==2.11.0を固定しているので、cu128のextra indexから
# +cu128ビルドを解決させる。ComfyUIのcu130とは別venvなので混ざらない。
# 3090はsm_86で、cu128・cu130のどちらでも動く。ここは上流が検証している
# 組み合わせに合わせる。
uv pip install \
  --python "$APPLIO_DIR/.venv/bin/python" \
  -r "$APPLIO_DIR/requirements.txt" \
  --extra-index-url https://download.pytorch.org/whl/cu128 \
  --index-strategy unsafe-best-match

step "WebSocketドライバ"
# Applioのrequirements.txtにはwebsockets/wsprotoが入っていない。
# uvicornはws="auto"で実装を探し、どちらも無いとws="none"に落ちて
# upgradeを拒否する。するとリアルタイム変換の /api/ws-audio が
# WebSocketルートとして登録されているのにHTTP 404を返し、
# 「UIは開くのに変換だけ無言で動かない」状態になる。
# gradioの依存にも含まれないため、ここで明示的に入れる。
uv pip install --python "$APPLIO_DIR/.venv/bin/python" websockets

step "事前学習モデル（HiFi-GAN pretrained・contentvec・rmvpe）"
# --no-exe はWindows用ffmpeg/ffprobeバイナリの取得を抑止する。Linuxではapt版を使う。
(cd "$APPLIO_DIR" && .venv/bin/python core.py prerequisites \
  --pretraineds-hifigan --models --no-exe)

step "systemd user service"
mkdir -p "$SERVICE_DIR"
# ConflictsでComfyUI・Qwenと排他にする。3090の24GBを取り合うと、
# 学習が起動時にOOMで落ちるため、同時起動を許さない。
# --client はリアルタイム変換のAPI(/api)とブラウザ用JSを有効化するフラグで、
# サーバ側に付ける（名前に反してクライアント専用モードではない）。
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Applio (RVC training / realtime voice conversion)
After=network-online.target
Wants=network-online.target
Conflicts=comfyui.service qwen38.service

[Service]
Type=simple
WorkingDirectory=$APPLIO_DIR
Environment=PYTHONUNBUFFERED=1
ExecStart=$APPLIO_DIR/.venv/bin/python $APPLIO_DIR/app.py \\
  --client \\
  --server-name 127.0.0.1 \\
  --port $PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
# 再起動後の既定はComfyUIのまま。Applioはai-mode applioで明示起動する。
systemctl --user disable applio.service >/dev/null 2>&1 || true
systemctl --user start applio.service

step "起動待ち"
for _ in $(seq 1 60); do
  if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
if ! curl -fsS --max-time 2 "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
  echo "Applioが127.0.0.1:$PORT で応答していません" >&2
  echo "確認: journalctl --user -u applio -n 50 --no-pager" >&2
  exit 1
fi
ok "Applioを起動しました: http://127.0.0.1:$PORT"

if command -v tailscale >/dev/null && tailscale status >/dev/null 2>&1; then
  step "Applioをtailnet内だけにHTTPS公開"
  # 環境によってserveの設定にrootが要る。まず非特権で試し、駄目ならsudoに落とす。
  if ! tailscale serve --bg --https="$TAILSCALE_HTTPS_PORT" "http://127.0.0.1:$PORT" 2>/dev/null; then
    sudo tailscale serve --bg --https="$TAILSCALE_HTTPS_PORT" "http://127.0.0.1:$PORT"
  fi
  ok "tailnet内のHTTPS $TAILSCALE_HTTPS_PORT 番で公開しました"
else
  warn "Tailscaleが未接続のため、tailnet公開はスキップしました"
  warn "平文HTTPではブラウザがマイクを許可しないため、リアルタイム変換は使えません"
fi

echo
echo "状態:            ai-mode status"
echo "Applioへ切替:    ai-mode applio"
echo "ComfyUIへ切替:   ai-mode comfy"
echo "ログ:            journalctl --user -u applio -f"
