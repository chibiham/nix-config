#!/usr/bin/env bash
# ComfyUI本体とPython依存を明示的に更新する。
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"

if [[ ! -d "$COMFY_DIR/.git" ]] || [[ ! -x "$COMFY_DIR/.venv/bin/python" ]]; then
  echo "ComfyUIが未導入です。先にinstall-comfyui-ubuntu.shを実行してください" >&2
  exit 1
fi

if [[ -n "$(git -C "$COMFY_DIR" status --porcelain)" ]]; then
  echo "$COMFY_DIR に未コミットの変更があります。更新を中止します" >&2
  exit 1
fi

git -C "$COMFY_DIR" pull --ff-only
uv pip install --python "$COMFY_DIR/.venv/bin/python" -r "$COMFY_DIR/requirements.txt"
if [[ -f "$COMFY_DIR/manager_requirements.txt" ]]; then
  uv pip install --python "$COMFY_DIR/.venv/bin/python" -r "$COMFY_DIR/manager_requirements.txt"
fi
systemctl --user restart comfyui.service
systemctl --user status comfyui.service --no-pager
