#!/usr/bin/env bash
# Tailscale Serve（tailnet内だけのHTTPS公開）を、ホストの設定 TAILSCALE_SERVE のとおりにする。
# TAILSCALE_SERVE は hosts/ubuntu/<ホスト名>.env に「HTTPSのポート=127.0.0.1のポート」を空白区切りで書く
# （例: "443=8188 4520=4520"）。何度流してもよい。すでに同じ向きなら何もしない。
#
# 一覧にないServeは消さない（警告だけ出す）。消すときは --prune を付ける。
# --dry-run は、変えるコマンドを表示するだけで何も変えない。
# Funnel（インターネットへの公開）は使わない。tailnet名はスクリプトに書かず、tailscale status から読む。
#
# serveの変更にはrootか、tailscaleのoperator（install-tailscale-ubuntu.sh が設定する）が要る。
# まずsudoなしで試し、断られたらsudoで流す（install-applio-ubuntu.sh と同じ）。
set -euo pipefail

# shellcheck source=lib/ubuntu-host.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/ubuntu-host.sh"

dry_run=0
prune=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    --prune) prune=1 ;;
    *) echo "usage: $0 [--dry-run] [--prune]" >&2; exit 2 ;;
  esac
done

warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "このスクリプトはLinux専用です" >&2
  exit 1
fi
for command in tailscale python3; do
  if ! command -v "$command" >/dev/null; then
    echo "必要なコマンドがありません: $command" >&2
    exit 1
  fi
done
if ! tailscale status >/dev/null 2>&1; then
  echo "Tailscaleへ接続されていません。先に install-tailscale-ubuntu.sh を流してください" >&2
  exit 1
fi

# 一覧を読む（HTTPSのポート → 127.0.0.1のポート）
declare -A want=()
for entry in $TAILSCALE_SERVE; do
  if [[ ! "$entry" =~ ^([0-9]+)=([0-9]+)$ ]]; then
    echo "TAILSCALE_SERVE の書き方が違います: $entry（HTTPSのポート=127.0.0.1のポート）" >&2
    exit 1
  fi
  want[${BASH_REMATCH[1]}]=${BASH_REMATCH[2]}
done

# いまの設定（HTTPSのポート → 向け先。"/" のproxyだけを見る）
declare -A have=()
while read -r port target; do
  [[ -n "$port" ]] && have[$port]=$target
done < <(tailscale serve status --json 2>/dev/null | python3 -I -c '
import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    d = {}
for host, web in (d.get("Web") or {}).items():
    port = host.rsplit(":", 1)[-1]
    proxy = ((web.get("Handlers") or {}).get("/") or {}).get("Proxy") or "(proxy以外)"
    print(port, proxy)
')

dns_name="$(tailscale status --json | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))')"

# 変えるコマンドを流す。operatorでなければsudoに落とす
serve() {
  if (( dry_run )); then
    echo "  (dry-run) tailscale serve $*"
    return
  fi
  if ! tailscale serve "$@" 2>/dev/null; then
    sudo tailscale serve "$@"
  fi
}

if [[ ${#want[@]} -eq 0 ]]; then
  warn "TAILSCALE_SERVE が空です（hosts/ubuntu/$UBUNTU_HOST.env）。追加はしません"
fi

for port in $(printf '%s\n' "${!want[@]}" | sort -n); do
  target="http://127.0.0.1:${want[$port]}"
  if [[ "${have[$port]:-}" == "$target" ]]; then
    ok "https://$dns_name:$port → $target（設定済み）"
    continue
  fi
  if [[ -n "${have[$port]:-}" ]]; then
    warn "https://$dns_name:$port の向き先を ${have[$port]} から $target に変えます"
  fi
  serve --bg --https="$port" "$target"
  ok "https://$dns_name:$port → $target"
done

for port in $(printf '%s\n' "${!have[@]}" | sort -n); do
  [[ -n "${want[$port]:-}" ]] && continue
  if (( prune )); then
    serve --https="$port" off
    ok "https://$dns_name:$port（${have[$port]}）を外しました"
  else
    warn "一覧にないServe: https://$dns_name:$port → ${have[$port]}（残します。外すなら --prune）"
  fi
done

if (( ! dry_run )); then
  echo
  tailscale serve status 2>/dev/null || sudo tailscale serve status
fi
