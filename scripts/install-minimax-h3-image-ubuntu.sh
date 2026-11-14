#!/usr/bin/env bash
# MiniMax H3 Image（画像生成）の重みを、revision と sha256 を固定して ComfyUI の models/ に置く（issue 5）。
#
#   install-minimax-h3-image-ubuntu.sh [--verify] [--with-expander] [int8|w4a8|gguf-q5|gguf-q4 ...]
#
# - いつも置く: VAE、テキストエンコーダー（Qwen3-VL 32B NVFP4。H3 の動画と同じファイル）
# - DiT の版は引数（なければ hosts/ubuntu/<ホスト名>.env の H3_IMAGE_MODELS、空白区切り）で選ぶ。
#   どちらも空なら使い方を出して止まる（chibihamuntu で流しても何もしない）
# - --with-expander: 任意のプロンプト拡張（Qwen3.5 9B W4A8）も置く
# - --verify: すでにあるファイルの sha256 も確かめる（既定は大きさだけ）。合わなければ消さずに失敗する
#
# 取り方は install-qwen38-ubuntu.sh の download_model と同じ（aria2c で <名前>.part に落とし、sha256 を確かめてから mv）。
# sudo は要らない。ComfyUI は止めない・起動し直さない。
# 終わりに、置いたファイルを ~/ai の models.lock.toml と同じ形で出す（chibiham-ai#74 で台帳に写す）。
#
# 出どころ:
# - 公式（Comfy-Org）: https://huggingface.co/Comfy-Org/MiniMax-H3-Image
#   revision 0bb149f5（ファイルの upload は 2026-11-10、最後の commit は 2026-11-11T12:10Z の README）
# - 第三者の GGUF（Abiray、Comfy-Org・MiniMax のものではない）: https://huggingface.co/Abiray/MiniMax-H3-Image-GGUF
#   revision fec7ec77（2026-11-11T14:28Z）
# - 第三者の拡張 ComfyUI-GGUF（city96）: GGUF の DiT を読むのに要る。commit 6ea2651e（2026-01-12）。
#   requirements.txt は gguf>=0.13.0、sentencepiece、protobuf
# このリポジトリの方針で、公開から72時間たっていないものは使わない（どれも 2026-11-14 の時点で72時間を過ぎている）。
# 版を上げるときも、revision の日付が72時間より前であることを確かめてから、revision・大きさ・sha256 を書き換える。
set -euo pipefail

# shellcheck source=lib/ubuntu-host.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/ubuntu-host.sh"

COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
MODELS_DIR="$COMFY_DIR/models"

H3_REPO="Comfy-Org/MiniMax-H3-Image"
H3_REVISION="0bb149f51e3156ed4b90dd45d5620346bfe1df8f"
GGUF_REPO="Abiray/MiniMax-H3-Image-GGUF"
GGUF_REVISION="fec7ec774db49d0c785bdc2174a488576b7396dd"
GGUF_NODE_REPO="https://github.com/city96/ComfyUI-GGUF.git"
GGUF_NODE_COMMIT="6ea2651e7df66d7585f6ffee804b20e92fb38b8a"
GGUF_NODE_DIR="$COMFY_DIR/custom_nodes/ComfyUI-GGUF"

# ファイル: 「名前|HFのリポジトリ|revision|リポジトリの中のパス|置く models/ の下のディレクトリ|大きさ|sha256」
# GGUF は diffusion_models/ に置く（ComfyUI-GGUF の Unet Loader (GGUF) は unet と diffusion_models の両方を読む）
FILES=(
  "vae|$H3_REPO|$H3_REVISION|vae/minimax_h3_image_vae_fp16.safetensors|vae|1168505312|d80e9c2e5cfc9844869961ff5a58c9a9e52182df6bfb30b26018dd7f348721af"
  "text-encoder|$H3_REPO|$H3_REVISION|text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors|text_encoders|15687142551|35a88d51044231fe332301d7a62aa81e3f2cba62febeb446e2c1e3e0ef76f2c6"
  "expander|$H3_REPO|$H3_REVISION|text_encoders/qwen3.5_9b_w4a8_gptq.safetensors|text_encoders|7343591088|4cc6a1543ad2061806da46f35f90cadb4801dcba246c44782cf42ec0feb6407c"
  "int8|$H3_REPO|$H3_REVISION|diffusion_models/minimax_h3_image_pruned_int8_convrot.safetensors|diffusion_models|20979314802|83eb140f1ff95c068f8a6886e6d3f3d0d4ab2e07bb2fe6d2ef992a51146ee622"
  "w4a8|$H3_REPO|$H3_REVISION|diffusion_models/minimax_h3_image_pruned_w4a8.safetensors|diffusion_models|12549794530|517cc19b85348386f4df7c806dce80d839d0899e7cdaa3e1dbb09de964381dbb"
  "gguf-q5|$GGUF_REPO|$GGUF_REVISION|MiniMax-H3-Image-Pruned-Q5_K_M.gguf|diffusion_models|14077892224|f4e139d7aa5cd67727b6645a5b1c17d1c931f7289d46a3b1ea183d7a9b8ce44b"
  "gguf-q4|$GGUF_REPO|$GGUF_REVISION|MiniMax-H3-Image-Pruned-Q4_K_M.gguf|diffusion_models|11573106304|e545379320e533f9d60e2d831a9489d94889158e88cd681ea7940da47882015f"
)

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

usage() {
  cat >&2 <<'EOF'
usage: install-minimax-h3-image-ubuntu.sh [--verify] [--with-expander] [int8|w4a8|gguf-q5|gguf-q4 ...]
  DiT の版（ひとつ以上）:
    int8      公式 pruned int8 convrot（20.9GB）
    w4a8      公式 pruned W4A8（12.5GB）
    gguf-q5   第三者 GGUF Q5_K_M（14.1GB。ComfyUI-GGUF も置く）
    gguf-q4   第三者 GGUF Q4_K_M（11.6GB。ComfyUI-GGUF も置く）
  引数がなければ H3_IMAGE_MODELS（hosts/ubuntu/<ホスト名>.env）を使う。どちらも空なら何もしない
  VAE とテキストエンコーダー（NVFP4、15.7GB）はいつも置く
  --with-expander  プロンプト拡張（Qwen3.5 9B W4A8、7.3GB）も置く
  --verify         すでにあるファイルの sha256 も確かめる
EOF
  exit 2
}

verify=0
with_expander=0
variants=()
while (($# > 0)); do
  case "$1" in
    --verify) verify=1 ;;
    --with-expander) with_expander=1 ;;
    -h | --help) usage ;;
    int8 | w4a8 | gguf-q5 | gguf-q4) variants+=("$1") ;;
    *) echo "知らない引数です: $1" >&2; usage ;;
  esac
  shift
done
if ((${#variants[@]} == 0)); then
  read -r -a variants <<<"$H3_IMAGE_MODELS"
fi
if ((${#variants[@]} == 0)); then
  echo "DiT の版が選ばれていません（引数も H3_IMAGE_MODELS も空）。何もしません" >&2
  usage
fi
for v in "${variants[@]}"; do
  case "$v" in
    int8 | w4a8 | gguf-q5 | gguf-q4) ;;
    *) echo "H3_IMAGE_MODELS に知らない版があります: $v" >&2; exit 1 ;;
  esac
done

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "このスクリプトはLinux専用です" >&2
  exit 1
fi
for command in aria2c sha256sum; do
  if ! command -v "$command" >/dev/null; then
    echo "必要なコマンドがありません: $command" >&2
    exit 1
  fi
done
if [[ ! -d "$MODELS_DIR" ]]; then
  echo "$MODELS_DIR がありません。先に install-comfyui-ubuntu.sh を実行してください" >&2
  exit 1
fi

want_gguf=0
names=(vae text-encoder)
if ((with_expander == 1)); then
  names+=(expander)
fi
for v in "${variants[@]}"; do
  # 同じ版を2回書いても1回だけ取る
  if [[ " ${names[*]} " != *" $v "* ]]; then
    names+=("$v")
  fi
  if [[ "$v" == gguf-* ]]; then
    want_gguf=1
  fi
done
if ((want_gguf == 1)); then
  for command in git uv; do
    if ! command -v "$command" >/dev/null; then
      echo "GGUF の版には $command が要ります（ComfyUI-GGUF を置くため）" >&2
      exit 1
    fi
  done
  if [[ ! -x "$COMFY_DIR/.venv/bin/python" ]]; then
    echo "$COMFY_DIR/.venv がありません（ComfyUI-GGUF の依存を入れる先）" >&2
    exit 1
  fi
fi

file_size() { stat -c %s "$1"; }
file_sha256() { sha256sum "$1" | awk '{ print $1 }'; }

# fetch_file <名前>: 大きさと sha256 を確かめて置く。置いたファイルを placed に足す
placed=()
fetch_file() {
  local name="$1" entry repo revision remote subdir size sha256 dir base path part actual
  for entry in "${FILES[@]}"; do
    if [[ "${entry%%|*}" == "$name" ]]; then
      break
    fi
    entry=""
  done
  [[ -n "$entry" ]] || { echo "内部の誤り: $name がありません" >&2; exit 1; }
  IFS='|' read -r _ repo revision remote subdir size sha256 <<<"$entry"
  dir="$MODELS_DIR/$subdir"
  base="${remote##*/}"
  path="$dir/$base"
  part="$path.part"
  mkdir -p "$dir"

  if [[ -e "$path" ]]; then
    actual="$(file_size "$path")"
    if [[ "$actual" != "$size" ]]; then
      echo "$path の大きさが違います（$actual、期待 $size）。消さずに止めます。確かめてから消して流し直してください" >&2
      exit 1
    fi
    if ((verify == 1)); then
      echo "sha256 を確かめています: $path"
      actual="$(file_sha256 "$path")"
      if [[ "$actual" != "$sha256" ]]; then
        echo "$path の sha256 が違います（$actual、期待 $sha256）。消さずに止めます" >&2
        exit 1
      fi
      ok "$path は取得済みです（sha256 も一致）"
    else
      ok "$path は取得済みです（大きさが一致。sha256 は --verify で確かめる）"
    fi
  else
    aria2c --continue=true --max-connection-per-server=16 --split=16 \
      --min-split-size=16M --max-tries=0 --retry-wait=5 \
      --dir="$dir" --out="$base.part" \
      "https://huggingface.co/$repo/resolve/$revision/$remote"
    actual="$(file_size "$part")"
    if [[ "$actual" != "$size" ]]; then
      echo "$part の大きさが違います（$actual、期待 $size）。.part を残して止めます（流し直せば続きから取ります）" >&2
      exit 1
    fi
    echo "sha256 を確かめています: $part"
    actual="$(file_sha256 "$part")"
    if [[ "$actual" != "$sha256" ]]; then
      echo "$part の sha256 が違います（$actual、期待 $sha256）。" >&2
      echo ".part を残して止めます。消してから流し直してください: rm '$part'" >&2
      exit 1
    fi
    mv "$part" "$path"
    ok "$path を取得しました"
  fi
  placed+=("$path|$size|$sha256|https://huggingface.co/$repo/resolve/$revision/$remote")
}

step "MiniMax H3 Image（${names[*]}）"
for name in "${names[@]}"; do
  fetch_file "$name"
done

if ((want_gguf == 1)); then
  step "ComfyUI-GGUF（第三者の拡張、$GGUF_NODE_COMMIT）"
  gguf_ready=0
  if [[ -d "$GGUF_NODE_DIR/.git" ]]; then
    head="$(git -C "$GGUF_NODE_DIR" rev-parse HEAD)"
    if [[ "$head" == "$GGUF_NODE_COMMIT" ]]; then
      ok "$GGUF_NODE_DIR は $GGUF_NODE_COMMIT です"
      gguf_ready=1
    else
      warn "$GGUF_NODE_DIR は別の commit（$head）です。触りません（依存も入れません）"
    fi
  elif [[ -e "$GGUF_NODE_DIR" ]]; then
    warn "$GGUF_NODE_DIR はありますが git のリポジトリではありません。触りません"
  else
    git clone "$GGUF_NODE_REPO" "$GGUF_NODE_DIR"
    git -C "$GGUF_NODE_DIR" checkout --detach "$GGUF_NODE_COMMIT"
    ok "$GGUF_NODE_DIR を $GGUF_NODE_COMMIT で置きました"
    gguf_ready=1
  fi
  if ((gguf_ready == 1)); then
    # uv は Safe Chain の shim を通る（公開72時間未満の版は拒まれる）
    uv pip install --python "$COMFY_DIR/.venv/bin/python" -r "$GGUF_NODE_DIR/requirements.txt"
  fi
  warn "ComfyUI-GGUF を読み込むには ComfyUI の起動し直しが要ります（このスクリプトは起動し直しません）"
fi

echo
ok "MiniMax H3 Image のファイルを置きました。台帳（~/ai の models.lock.toml）に写す行:"
echo
for p in "${placed[@]}"; do
  IFS='|' read -r path size sha256 source <<<"$p"
  rel="${path#"$HOME"/}"
  if [[ "$rel" == "$path" ]]; then
    warn "$path は \$HOME の下にないので、そのままのパスで出します"
  fi
  cat <<EOF
[[model]]
path = "$rel"
size = $size
sha256 = "$sha256"
source = "$source"

EOF
done
