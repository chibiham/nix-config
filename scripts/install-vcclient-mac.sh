#!/usr/bin/env bash
# VCClient（w-okada製リアルタイム音声変換）をMacへ導入する。
#
# Homebrewにcaskが無く、Nixでも配布されていないため明示スクリプトで管理する。
# Apple Silicon版はonnxエディションで、ONNX Runtime経由でCoreMLを使うため
# RVCモデルをMacローカルで実用的な速度で動かせる。
#
# なぜMacローカルか: Applioの realtime は rvc/configs/config.py が
#   self.device = "cuda:0" if torch.cuda.is_available() else "cpu"
# とだけ書いていてMPSの分岐が無く、MacではCPU推論に落ちる。
# 一方VCClientのonnxエディションはCoreMLを使えるので、推論をMacへ寄せると
# Ubuntu機のRTX 3090を学習や他用途に空けられる。
set -euo pipefail

VERSION="${VCCLIENT_VERSION:-2.1.4-alpha}"
ARCHIVE="vcclient_mac_${VERSION}.zip"
BASE_URL="https://huggingface.co/wok000/vcclient000/resolve/main"
INSTALL_DIR="${VCCLIENT_DIR:-$HOME/Applications/vcclient}"
CACHE_DIR="${VCCLIENT_CACHE_DIR:-$HOME/Library/Caches/vcclient}"
PORT="${VCCLIENT_PORT:-18000}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "このスクリプトはmacOS専用です" >&2
  exit 1
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  warn "Apple Silicon以外では、このビルドは動作しません"
fi

for command in curl unzip xattr; do
  if ! command -v "$command" >/dev/null; then
    echo "必要なコマンドがありません: $command" >&2
    exit 1
  fi
done

step "アーカイブ取得"
mkdir -p "$CACHE_DIR"
if [[ -s "$CACHE_DIR/$ARCHIVE" ]]; then
  ok "$CACHE_DIR/$ARCHIVE は取得済みです"
else
  # 500MB超あるので中断しても再開できるようにする。
  curl -fL --retry 5 --retry-delay 5 -C - \
    -o "$CACHE_DIR/$ARCHIVE.part" "$BASE_URL/$ARCHIVE"
  mv "$CACHE_DIR/$ARCHIVE.part" "$CACHE_DIR/$ARCHIVE"
  ok "$ARCHIVE を取得しました"
fi

step "展開"
# zipは dist/ 配下に main・web_front・.app を含む。dist/ の中身を
# INSTALL_DIR 直下へ移すので、アップグレード時は作り直す。
rm -rf "$INSTALL_DIR"
mkdir -p "$(dirname "$INSTALL_DIR")"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
unzip -q "$CACHE_DIR/$ARCHIVE" -d "$TMP_DIR"
mv "$TMP_DIR/dist" "$INSTALL_DIR"
ok "$INSTALL_DIR へ展開しました"

step "quarantine属性の除去"
# 開発元の署名が無いため、これをしないとGatekeeperが実行を拒否する。
# 配布物のstart_http.commandも同じことをしているので、上流の想定動作。
xattr -rc "$INSTALL_DIR/main" "$INSTALL_DIR/voice-changer-native-client.app"
ok "除去しました"

step "起動確認"
if "$INSTALL_DIR/main" start --help >/dev/null 2>&1; then
  ok "バイナリが実行できました"
else
  echo "バイナリを実行できません。Gatekeeperの設定を確認してください" >&2
  exit 1
fi

cat <<EOF

起動:
  $INSTALL_DIR/main start --host 127.0.0.1 --port $PORT

  localhostはセキュアコンテキスト扱いなので、HTTPSなしでもブラウザが
  マイクを使える。外部からアクセスしないなら --https は不要。

  同梱の $INSTALL_DIR/start_http.command をFinderから開いてもよい。

モデル:
  RVCの .pth と .index はWeb UIからアップロードする。
  Ubuntu機(Applio)で学習したものは ~/voice-models/ に置いてある。

学習はUbuntu機の3090で行う:
  ai-mode applio
EOF
