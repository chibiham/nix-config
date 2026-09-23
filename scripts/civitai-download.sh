#!/usr/bin/env bash
# Civitaiのモデルを取得し、種別に応じてComfyUIのmodels/以下へ保存する。
# Nix（home/linux.nix）が civitai-download コマンドとして配布する。
# トークンはプロセス引数に出さないよう、curlへはヘッダファイル経由で渡す。
set -euo pipefail

API="https://civitai.com/api/v1"
COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
SECRETS_FILE="$HOME/.secrets/.env.secrets"

usage() {
  cat >&2 <<'EOF'
usage: civitai-download [options] <URL | modelVersionId>

  URL例: https://civitai.com/models/12345/name?modelVersionId=67890
         https://civitai.com/models/12345            （最新バージョン）
         https://civitai.com/api/download/models/67890

options:
  -d, --dir DIR    保存先ディレクトリ（既定: モデル種別から $COMFY_DIR/models/<種別>）
  -f, --file NAME  取得するファイル名（既定: primaryファイル）
  -n, --dry-run    解決結果をJSONで表示するだけでダウンロードしない
  -h, --help
EOF
  exit 2
}

die() {
  echo "✗ $*" >&2
  exit 1
}

# 対話シェル以外（systemd、古いtmux等）から呼ばれても動くよう、
# 環境変数が無ければ update-secrets の出力から CIVITAI_TOKEN だけを読む
load_token() {
  if [[ -z "${CIVITAI_TOKEN:-}" && -f "$SECRETS_FILE" ]]; then
    CIVITAI_TOKEN="$(sed -n 's/^export CIVITAI_TOKEN="\(.*\)"$/\1/p' "$SECRETS_FILE")"
  fi
  [[ -n "${CIVITAI_TOKEN:-}" ]] ||
    die "CIVITAI_TOKEN が未設定です（1Passwordの chibihamuntu Vault に CIVITAI_TOKEN を作成し update-secrets を実行してください）"
}

civitai_curl() {
  curl -fL --retry 3 -H @<(printf 'Authorization: Bearer %s\n' "$CIVITAI_TOKEN") "$@"
}

api() {
  civitai_curl -sS "$API/$1"
}

resolve_version_id() {
  local target="$1" model_id
  if [[ "$target" =~ ^[0-9]+$ ]]; then
    echo "$target"
  elif [[ "$target" =~ [?\&]modelVersionId=([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$target" =~ /api/download/models/([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$target" =~ /models/([0-9]+) ]]; then
    model_id="${BASH_REMATCH[1]}"
    api "models/$model_id" | jq -er '.modelVersions[0].id' ||
      die "モデル $model_id のバージョンを取得できませんでした"
  else
    die "URLまたはmodelVersionIdを解釈できません: $target"
  fi
}

# Civitaiのモデル種別 → ComfyUIのmodels/サブディレクトリ
comfy_subdir() {
  case "$1" in
    Checkpoint) echo checkpoints ;;
    LORA | LoCon | DoRA) echo loras ;;
    TextualInversion) echo embeddings ;;
    VAE) echo vae ;;
    Controlnet) echo controlnet ;;
    Upscaler) echo upscale_models ;;
    Hypernetwork) echo hypernetworks ;;
    MotionModule) echo animatediff_models ;;
    *) return 1 ;;
  esac
}

dir=""
file_name=""
dry_run=0
target=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d | --dir) dir="${2:?}"; shift 2 ;;
    -f | --file) file_name="${2:?}"; shift 2 ;;
    -n | --dry-run) dry_run=1; shift ;;
    -h | --help) usage ;;
    -*) usage ;;
    *) [[ -z "$target" ]] || usage; target="$1"; shift ;;
  esac
done
[[ -n "$target" ]] || usage

load_token
version_id="$(resolve_version_id "$target")"
version_json="$(api "model-versions/$version_id")" ||
  die "modelVersion $version_id の情報を取得できませんでした"

if [[ -n "$file_name" ]]; then
  file_json="$(jq -e --arg n "$file_name" '.files | map(select(.name == $n)) | first' <<<"$version_json")" ||
    die "ファイル $file_name が見つかりません（--dry-run で一覧を確認してください）"
else
  file_json="$(jq -e '.files | (map(select(.primary == true)) + .) | first' <<<"$version_json")" ||
    die "modelVersion $version_id にファイルがありません"
fi

model_type="$(jq -r '.model.type' <<<"$version_json")"
if [[ -z "$dir" ]]; then
  subdir="$(comfy_subdir "$model_type")" ||
    die "種別 $model_type の保存先が決められません。--dir で指定してください"
  dir="$COMFY_DIR/models/$subdir"
fi
name="$(jq -r '.name' <<<"$file_json")"
name="${name##*/}"
dest="$dir/$name"
sha256="$(jq -r '.hashes.SHA256 // empty' <<<"$file_json" | tr 'A-F' 'a-f')"

if [[ "$dry_run" == 1 ]]; then
  jq --arg dest "$dest" --argjson file "$file_json" '{
    model: .model.name,
    type: .model.type,
    baseModel,
    version: .name,
    versionId: .id,
    trainedWords: (.trainedWords // []),
    selected: {name: $file.name, sizeKB: $file.sizeKB, dest: $dest},
    files: [.files[] | {name, type, primary, sizeKB, format: .metadata.format, fp: .metadata.fp}]
  }' <<<"$version_json"
  exit 0
fi

verify() {
  [[ -z "$sha256" ]] || [[ "$(sha256sum "$1" | cut -d' ' -f1)" == "$sha256" ]]
}

if [[ -e "$dest" ]]; then
  verify "$dest" || die "$dest は既に存在し、SHA256が一致しません"
  echo "✓ 取得済み: $dest"
  exit 0
fi

mkdir -p "$dir"
download_url="$(jq -r '.downloadUrl' <<<"$file_json")"
echo "==> $name ($model_type) → $dir" >&2
# 大きなファイルの中断に備えて .part に追記再開する
civitai_curl -C - --progress-bar -o "$dest.part" "$download_url" ||
  die "ダウンロードに失敗しました（401/403ならトークンか早期アクセス制限を確認してください）"
verify "$dest.part" || die "SHA256が一致しません: $dest.part"
mv "$dest.part" "$dest"
echo "✓ $dest"
