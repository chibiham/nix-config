#!/usr/bin/env bash
# カーネルを更新・再起動する前に、各カーネルに同じ版の linux-modules-nvidia-<世代> があるかを確かめる。
# 読むだけ（aptの更新・導入・再起動はしない）。足りなければ非0で終わる。
#
# 背景: 2026-10-23、chibihamuntuでカーネルだけが上がり、メタパッケージ
# linux-modules-nvidia-595-open-generic-hwe-24.04 が古い版のまま止まって、再起動後にGPUが見えなくなった。
#
#   sudo apt-get update                                    # 先に一覧を新しくする（この確認自体はしない）
#   scripts/check-nvidia-kernel-modules-ubuntu.sh          # 導入済みと、更新で入る予定のカーネル
set -euo pipefail

# shellcheck source=lib/ubuntu-host.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/ubuntu-host.sh"

ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }
ng()   { printf '\033[1;31m✗ %s\033[0m\n' "$1"; failed=1; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
failed=0

if ! command -v dpkg-query >/dev/null || ! command -v apt-get >/dev/null; then
  echo "このスクリプトはUbuntu専用です" >&2
  exit 1
fi

installed() { [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null || true)" == "ii " ]]; }
version_of() { dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true; }
candidate_of() { apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { print $2 }'; }
# 7.0.0-42.42~24.04.1+1 → 7.0.0-42.42~24.04.1（NVIDIAのモジュールは +N が付くことがある）
base_version() { printf '%s\n' "${1%%+*}"; }

mapfile -t drivers < <(
  dpkg-query -W -f='${binary:Package} ${db:Status-Abbrev}\n' 'nvidia-driver-*' 2>/dev/null |
    awk '$2 == "ii" { sub(/:amd64$/, "", $1); print $1 }'
)
if [[ ${#drivers[@]} -ne 1 ]]; then
  echo "nvidia-driver-* が${#drivers[@]}個入っています（1個のはず）: ${drivers[*]:-なし}" >&2
  exit 1
fi
suffix="${drivers[0]#nvidia-driver-}"
echo "NVIDIAドライバ: ${drivers[0]}"
if [[ "$NVIDIA_REQUIRE_OPEN" == 1 && "$suffix" != *-open ]]; then
  ng "このホストは *-open が必須です（${drivers[0]}）"
fi

echo
echo "導入済みのカーネル:"
mapfile -t kernels < <(
  dpkg-query -W -f='${binary:Package} ${db:Status-Abbrev}\n' 'linux-image-[0-9]*-generic' 2>/dev/null |
    awk '$2 == "ii" { sub(/^linux-image-/, "", $1); print $1 }' | sort -V
)
for kernel in "${kernels[@]}"; do
  module="linux-modules-nvidia-${suffix}-${kernel}"
  mark=""
  [[ "$kernel" == "$(uname -r)" ]] && mark="（稼働中）"
  if installed "$module"; then
    ok "$kernel$mark: $module"
  elif [[ "$(printf '%s\n%s\n' "$kernel" "$(uname -r)" | sort -V | tail -1)" == "$(uname -r)" && "$kernel" != "$(uname -r)" ]]; then
    # 稼働中より古いカーネルは、GRUBで選ばない限り起動しない（復旧用に残したもの）
    warn "$kernel: $module がありません（稼働中より古い。GRUBでこれを選ぶとGPUが見えません）"
  else
    ng "$kernel$mark: $module がありません。このカーネルで起動するとGPUが見えません"
  fi
done

echo
echo "メタパッケージ（カーネルとNVIDIAモジュールが同じ版を指すか）:"
for flavour in generic-hwe-24.04 generic; do
  image_meta="linux-image-${flavour}"
  nvidia_meta="linux-modules-nvidia-${suffix}-${flavour}"
  installed "$image_meta" || continue
  image_now="$(version_of "$image_meta")"
  image_next="$(candidate_of "$image_meta")"
  if ! installed "$nvidia_meta"; then
    ng "$nvidia_meta が入っていません（$image_meta $image_now に追従するもの）"
    continue
  fi
  nvidia_now="$(version_of "$nvidia_meta")"
  nvidia_next="$(candidate_of "$nvidia_meta")"
  if [[ "$(base_version "$image_now")" == "$(base_version "$nvidia_now")" ]]; then
    ok "導入済み: $image_meta $image_now / $nvidia_meta $nvidia_now"
  else
    ng "導入済みの版がずれています: $image_meta $image_now / $nvidia_meta $nvidia_now"
  fi
  if [[ -n "$image_next" && "$image_next" != "(none)" ]]; then
    if [[ "$(base_version "$image_next")" == "$(base_version "$nvidia_next")" ]]; then
      ok "更新の候補: $image_meta $image_next / $nvidia_meta $nvidia_next"
    else
      ng "更新の候補がずれています: $image_meta $image_next / $nvidia_meta ${nvidia_next:-なし}（モジュールが届くまでカーネルを上げない）"
    fi
  fi
done

echo
echo "full-upgrade で入る予定のカーネル（シミュレーション。今のAPTの一覧を使う）:"
simulation="$(apt-get -s -o Debug::NoLocking=1 full-upgrade 2>/dev/null || true)"
mapfile -t pending < <(sed -nE 's/^Inst linux-image-([0-9][^ ]*-generic) .*/\1/p' <<<"$simulation" | sort -uV)
if [[ ${#pending[@]} -eq 0 ]]; then
  ok "新しいカーネルは入りません"
fi
for kernel in "${pending[@]}"; do
  module="linux-modules-nvidia-${suffix}-${kernel}"
  if grep -qE "^Inst ${module//./\\.} " <<<"$simulation"; then
    ok "$kernel: $module も一緒に入ります"
  else
    ng "$kernel: $module が一緒に入りません。モジュールが届くまで full-upgrade（と再起動）を待つ"
  fi
done

echo
if [[ "$failed" -ne 0 ]]; then
  echo "足りないものがあります。再起動の前に直してください（例: sudo apt-get install linux-modules-nvidia-${suffix}-<カーネル>）" >&2
  exit 1
fi
ok "すべてのカーネルに同じ版のNVIDIAモジュールがあります"
