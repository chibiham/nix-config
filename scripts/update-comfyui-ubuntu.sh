#!/usr/bin/env bash
# ComfyUI本体とPython依存を明示的に更新する（戻す手順つき）。
#
#   update-comfyui-ubuntu.sh [--ref <タグ|commit>] [--force] [--no-restart]
#   update-comfyui-ubuntu.sh --restore <控えのディレクトリ> [--force] [--no-restart]
#
# 版は hosts/ubuntu/<ホスト名>.env の COMFY_REF（--ref が優先）。空なら git pull --ff-only（master に追従）、
# 値があれば git fetch --tags origin のあと、その commit を git checkout --detach する。
#
# 変える前に、いまの commit・git describe・uv pip freeze・対象の ComfyUI の場所（comfy_dir）を
# ${COMFY_SNAPSHOT_DIR:-~/.local/state/comfyui-update}/<UTC時刻>-<短いcommit>/ に控え、終わりに戻すコマンドを表示する。
# 戻すコマンドには、今回の対象と方針を引き継ぐ（COMFY_DIR・COMFY_PORT が既定でなければ頭に付け、--no-restart なら付ける）。
# --restore は控えの commit に戻し、freeze.txt で依存を入れ直す（戻す前にも控えを取るので、戻しを戻せる）。
# 控えの comfy_dir がいまの COMFY_DIR と違えば、何も変えずに止まる（写しの控えで本番を戻さない）。
#
# 起動し直す前に ComfyUI のキュー（/queue）が空かを確かめ、空でなければ何も変えずに止まる（--force で飛ばす）。
# 進むのは、つながらない（止まっている）ときだけ。タイムアウトや HTTP の誤りでは止まる。
# 起動し直したあと /system_stats が返るまで待ち（既定 180 秒）、comfyui_version を表示する。
# --no-restart は git と venv だけを変え、systemctl を呼ばない（キューも確かめない。サービスでない写しで試す用）。
#
# chibihamuntu（COMFY_REF が空）での変化（issue 5）: git pull --ff-only → 依存 → restart は今までどおり。
#   足したのは、控えを取ること・キューの確かめ・起動の待ち。
#   また、未追跡のファイルでは止まらなくなった（追跡しているファイルの変更があれば今までどおり止まる）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/ubuntu-host.sh
source "$SCRIPT_DIR/lib/ubuntu-host.sh"
# shellcheck source=lib/comfyui.sh
source "$SCRIPT_DIR/lib/comfyui.sh"

COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"
COMFY_PORT="${COMFY_PORT:-8188}"
COMFY_READY_TIMEOUT="${COMFY_READY_TIMEOUT:-180}"
SNAPSHOT_ROOT="${COMFY_SNAPSHOT_DIR:-$HOME/.local/state/comfyui-update}"
PYTHON="$COMFY_DIR/.venv/bin/python"
# install-comfyui-ubuntu.sh と同じ PyTorch の index（torch は +cu130 の版）
TORCH_INDEX_URL="https://download.pytorch.org/whl/cu130"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

usage() {
  cat >&2 <<'EOF'
usage: update-comfyui-ubuntu.sh [--ref <タグ|commit>] [--force] [--no-restart]
       update-comfyui-ubuntu.sh --restore <控えのディレクトリ> [--force] [--no-restart]
  --ref <ref>       この版に checkout --detach する（COMFY_REF より優先）
  --restore <dir>   控え（commit・freeze.txt）の状態に戻す
  --force           ComfyUI のキューを確かめない
  --no-restart      git と venv だけ変え、systemctl を呼ばない（キューも確かめない）
EOF
  exit 2
}

ref="$COMFY_REF"
restore_dir=""
force=0
restart=1
while (($# > 0)); do
  case "$1" in
    --ref) [[ $# -ge 2 && -n "$2" ]] || usage; ref="$2"; shift 2 ;;
    --restore) [[ $# -ge 2 && -n "$2" ]] || usage; restore_dir="$2"; shift 2 ;;
    --force) force=1; shift ;;
    --no-restart) restart=0; shift ;;
    -h | --help) usage ;;
    *) echo "知らない引数です: $1" >&2; usage ;;
  esac
done

if [[ ! -d "$COMFY_DIR/.git" ]] || [[ ! -x "$PYTHON" ]]; then
  echo "ComfyUIが未導入です。先にinstall-comfyui-ubuntu.shを実行してください" >&2
  exit 1
fi
if ! command -v uv >/dev/null; then
  echo "必要なコマンドがありません: uv" >&2
  exit 1
fi

# 対象の ComfyUI の場所（symlink を解いた絶対パス）。控えに残し、--restore で照らす
COMFY_DIR_REAL="$(cd "$COMFY_DIR" && pwd -P)"
DEFAULT_COMFY_DIR_REAL="$(cd "$HOME/ComfyUI" 2>/dev/null && pwd -P || true)"

if [[ -n "$restore_dir" ]]; then
  restore_dir="$(cd "$restore_dir" 2>/dev/null && pwd)" || { echo "控えのディレクトリがありません: $restore_dir" >&2; exit 1; }
  for f in commit freeze.txt; do
    if [[ ! -s "$restore_dir/$f" ]]; then
      echo "控えに $f がありません: $restore_dir" >&2
      exit 1
    fi
  done
  # git・キュー・新しい控えより前に照らす（別の場所の控えで、いまの COMFY_DIR を変えない）
  if [[ -s "$restore_dir/comfy_dir" ]]; then
    snapshot_comfy_dir="$(cat "$restore_dir/comfy_dir")"
    if [[ "$snapshot_comfy_dir" != "$COMFY_DIR_REAL" ]]; then
      echo "この控えは $snapshot_comfy_dir のものです。いまの COMFY_DIR は $COMFY_DIR_REAL です。何も変えずに止めます" >&2
      echo "その場所を戻すなら、COMFY_DIR=$(printf %q "$snapshot_comfy_dir") を付けて流してください" >&2
      exit 1
    fi
  else
    warn "控えに comfy_dir がありません（この確かめを足す前の控え）。$COMFY_DIR_REAL のものとして戻します"
  fi
fi

# 未追跡のファイル（例: dekahamuntu の .chibihamuntu-freeze.txt）は checkout の邪魔にならないので見ない
if [[ -n "$(git -C "$COMFY_DIR" status --porcelain --untracked-files=no)" ]]; then
  echo "$COMFY_DIR に未コミットの変更があります。更新を中止します" >&2
  git -C "$COMFY_DIR" status --short --untracked-files=no >&2
  exit 1
fi

# git を動かす前に確かめる（実行中の生成を起動し直しで落とさない）
if [[ "$restart" == 1 ]]; then
  if [[ "$force" == 1 ]]; then
    warn "ComfyUI のキューを確かめません（--force）"
  else
    step "ComfyUI のキュー"
    comfy_queue_is_idle "$COMFY_PORT" || exit 1
  fi
fi

# take_snapshot: いまの状態を控え、控えのディレクトリを snapshot_dir に入れる
take_snapshot() {
  local commit short base n=1
  commit="$(git -C "$COMFY_DIR" rev-parse HEAD)"
  short="$(git -C "$COMFY_DIR" rev-parse --short HEAD)"
  base="$SNAPSHOT_ROOT/$(date -u +%Y%m%dT%H%M%SZ)-$short"
  mkdir -p "$SNAPSHOT_ROOT"
  # 同じ秒に同じ commit で2回流しても上書きしない（-2、-3 … を付ける）
  snapshot_dir="$base"
  while ! mkdir "$snapshot_dir" 2>/dev/null; do
    n=$((n + 1))
    snapshot_dir="$base-$n"
    if ((n > 100)); then
      echo "控えのディレクトリを作れません: $base" >&2
      exit 1
    fi
  done
  printf '%s\n' "$commit" > "$snapshot_dir/commit"
  printf '%s\n' "$COMFY_DIR_REAL" > "$snapshot_dir/comfy_dir"
  git -C "$COMFY_DIR" describe --tags --always > "$snapshot_dir/describe"
  uv pip freeze --python "$PYTHON" > "$snapshot_dir/freeze.txt"
  ok "控え: $snapshot_dir（$(cat "$snapshot_dir/describe")）"
}

install_requirements() {
  uv pip install --python "$PYTHON" -r "$COMFY_DIR/requirements.txt"
  if [[ -f "$COMFY_DIR/manager_requirements.txt" ]]; then
    uv pip install --python "$PYTHON" -r "$COMFY_DIR/manager_requirements.txt"
  fi
}

step "いまの状態を控える"
snapshot_dir=""
take_snapshot

# 戻すコマンド（シェルに貼って安全なように %q で引用する）。今回の対象と方針を引き継ぐ
restore_cmd=""
if [[ "$COMFY_DIR_REAL" != "$DEFAULT_COMFY_DIR_REAL" ]]; then
  restore_cmd+="COMFY_DIR=$(printf %q "$COMFY_DIR_REAL") "
fi
if [[ "$COMFY_PORT" != 8188 ]]; then
  restore_cmd+="COMFY_PORT=$(printf %q "$COMFY_PORT") "
fi
restore_cmd+="$(printf %q "$SCRIPT_DIR/update-comfyui-ubuntu.sh") --restore $(printf %q "$snapshot_dir")"
if [[ "$restart" == 0 ]]; then
  restore_cmd+=" --no-restart"
fi

if [[ -n "$restore_dir" ]]; then
  step "控えに戻す: $restore_dir（$(cat "$restore_dir/describe" 2>/dev/null || echo '?')）"
  target="$(tr -d '[:space:]' < "$restore_dir/commit")"
  if ! git -C "$COMFY_DIR" cat-file -e "$target^{commit}" 2>/dev/null; then
    git -C "$COMFY_DIR" fetch --tags origin
  fi
  git -C "$COMFY_DIR" checkout --detach "$target"
  # freeze.txt には PyTorch の index にしかない torch==…+cu130 と、PyPI にしかない版（numpy など）が混ざる。
  # uv は既定（first-index）で、パッケージの名前が最初に見つかった index の版しか見ない。
  # --extra-index-url の index が PyPI より先に引かれるので、pytorch の index に同名で版がないものが解けずに失敗する
  # （dekahamuntu で確かめた: 「certifi was found on .../whl/cu130, but not at the requested version (certifi==2026.7.22)」）。
  # unsafe-best-match は全部の index から版を探す
  # （同じ版が両方にあれば先の index = pytorch のものを使う）。
  # 「unsafe」は依存の取り違え攻撃への備えを外すという意味で、ここでは PyTorch 公式の index だけを足しているので許す。
  # freeze.txt の `sam-2 @ git+https://...@<commit>` のような行は、uv がその commit を git で取る。
  # freeze.txt にない（新しい版で足された）パッケージは消さずに残る。
  uv pip install --python "$PYTHON" -r "$restore_dir/freeze.txt" \
    --extra-index-url "$TORCH_INDEX_URL" \
    --index-strategy unsafe-best-match
  ok "$(git -C "$COMFY_DIR" describe --tags --always) に戻しました"
else
  if [[ -z "$ref" ]]; then
    step "ComfyUI を更新（git pull --ff-only）"
    if ! git -C "$COMFY_DIR" symbolic-ref -q HEAD >/dev/null; then
      echo "HEAD がブランチから外れています（COMFY_REF・--ref・--restore で固定した版）。" >&2
      echo "master に追従し直すなら: git -C $COMFY_DIR checkout master" >&2
      exit 1
    fi
    git -C "$COMFY_DIR" pull --ff-only
  else
    step "ComfyUI を $ref にする"
    git -C "$COMFY_DIR" fetch --tags origin
    target="$(git -C "$COMFY_DIR" rev-parse --verify "$ref^{commit}")"
    git -C "$COMFY_DIR" checkout --detach "$target"
  fi
  ok "ComfyUI: $(git -C "$COMFY_DIR" describe --tags --always)（$(git -C "$COMFY_DIR" rev-parse --short HEAD)）"
  step "Python依存"
  install_requirements
fi

if [[ "$restart" == 1 ]]; then
  step "ComfyUI を起動し直す"
  systemctl --user restart comfyui.service
  if ! comfy_wait_ready "$COMFY_PORT" "$COMFY_READY_TIMEOUT"; then
    echo "戻すなら: $restore_cmd" >&2
    exit 1
  fi
  systemctl --user status comfyui.service --no-pager || true
else
  warn "ComfyUI は起動し直していません（--no-restart）"
fi

echo
ok "終わりました"
echo "戻すなら: $restore_cmd"
