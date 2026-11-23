#!/usr/bin/env bash
# Ubuntu Serverの初期セットアップ。何度実行しても安全な範囲だけを扱う。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# ホストごとの設定（hosts/ubuntu/<ホスト名>.env）。chibihamuntu は ubuntu-server
# shellcheck source=lib/ubuntu-host.sh
source "$REPO_DIR/scripts/lib/ubuntu-host.sh"
FLAKE_TARGET="${USER}@${FLAKE_HOST}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

if [[ "$(uname -s)" != "Linux" ]] || ! command -v apt-get >/dev/null; then
  echo "このスクリプトはUbuntu/Debian系Linux専用です" >&2
  exit 1
fi

# ホストの設定がないまま進むと、chibihamuntuの既定（ubuntu-server・chibihamuntu Vault）で入ってしまう。
# 先に hosts/ubuntu/<ホスト名>.env があり、必要な値が埋まっていることを確かめる。
host_error() {
  printf '\033[1;31m✗ %s\033[0m\n' "$1" >&2
  shift
  printf '  %s\n' "$@" >&2
  exit 1
}
if [[ ! -f "$UBUNTU_HOST_FILE" ]]; then
  known=""
  for env_file in "$REPO_DIR"/hosts/ubuntu/*.env; do
    [[ -e "$env_file" ]] && known+="$(basename "$env_file" .env) "
  done
  host_error "ホスト「$UBUNTU_HOST」の設定がありません: $UBUNTU_HOST_FILE" \
    "登録済み: ${known:-なし}" \
    "ホスト名が違うなら: sudo hostnamectl set-hostname <名前>（または UBUNTU_HOST=<名前> $0）" \
    "新しいホストなら hosts/ubuntu/README.md に従って <名前>.env を作り、flake.nix に homeConfigurations を足す"
fi
for var in FLAKE_HOST OP_VAULT UBUNTU_USER; do
  value="${!var:-}"
  if [[ -z "$value" || "$value" == *TODO* ]]; then
    host_error "$UBUNTU_HOST_FILE の $var が未設定です（値: ${value:-空}）" "決めてから書いて、再実行してください"
  fi
done
if [[ "$USER" != "$UBUNTU_USER" ]]; then
  host_error "このホストのユーザーは $UBUNTU_USER の想定ですが、$USER で実行しています" \
    "flake.nix の homeConfigurations.\"$UBUNTU_USER@$FLAKE_HOST\" は /home/$UBUNTU_USER を前提にしています"
fi
echo "ホスト: $UBUNTU_HOST（$UBUNTU_HOST_FILE）/ Home Manager: $FLAKE_TARGET / 1Password Vault: $OP_VAULT"

step "Ubuntuの基礎パッケージ"
sudo apt-get update
# sqlite3: art-studio などの SQLite の DB を、動いたまま写す（.backup）・確かめる（integrity_check）のに使う
sudo apt-get install -y ca-certificates curl git openssh-server sqlite3 xz-utils
sudo systemctl enable --now ssh

if ! command -v nix >/dev/null; then
  cat >&2 <<'EOF'
Nixが未導入です。Determinate Nix Installer等でNixを導入し、いったんログインし直してから再実行してください:
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
EOF
  exit 1
fi

step "Home Manager ($FLAKE_TARGET)"
if [[ "$(nix eval --json "$REPO_DIR#homeConfigurations" --apply "c: builtins.hasAttr \"$FLAKE_TARGET\" c")" != true ]]; then
  host_error "flake.nix に homeConfigurations.\"$FLAKE_TARGET\" がありません" "flake.nix の mkLinuxHome のエントリを足してから再実行してください"
fi
nix run "$REPO_DIR#home-manager" -- switch -b backup --flake "$REPO_DIR#$FLAKE_TARGET"
export PATH="$HOME/.nix-profile/bin:$PATH"
# env.tpl（home/linux.nix の chibiham.ubuntu.opVault）とホストの設定のVaultが揃っているか
if ! grep -qs "op://$OP_VAULT/" "$HOME/.secrets/env.tpl"; then
  host_error "$HOME/.secrets/env.tpl が $OP_VAULT Vault を参照していません" \
    "home/hosts/<ホスト>.nix の chibiham.ubuntu.opVault と $UBUNTU_HOST_FILE の OP_VAULT を揃えてください"
fi

# このマシン専用のService Account（$OP_VAULT Vaultのみ読み取り可）を使う
step "1Password Service Account Token"
mkdir -p "$HOME/.secrets"
chmod 700 "$HOME/.secrets"
if ! grep -q '^export OP_SERVICE_ACCOUNT_TOKEN=' "$HOME/.secrets/.env" 2>/dev/null; then
  echo "$OP_VAULT Vault を読めるService Accountのトークンを入力してください"
  read -rsp "OP_SERVICE_ACCOUNT_TOKEN: " token
  echo
  printf 'export OP_SERVICE_ACCOUNT_TOKEN="%s"\n' "$token" >> "$HOME/.secrets/.env"
  chmod 600 "$HOME/.secrets/.env"
  ok "~/.secrets/.env にトークンを保存しました"
else
  ok "トークンは設定済み"
fi

step "シークレットの展開"
update-secrets

step "miseランタイム"
mise install --yes
export PATH="$HOME/.local/share/safe-chain-shims:$HOME/.local/share/mise/shims:$PATH"
# npm/pnpmは必ずAikido Safe Chainのshim経由にする（HM switch済みが前提）。
# mise execはnodeのbinをPATH先頭に足すので、shimを絶対パスで呼ぶ。
SAFE_CHAIN_SHIMS="$HOME/.local/share/safe-chain-shims"
if [ ! -x "$SAFE_CHAIN_SHIMS/npm" ]; then
  printf 'safe-chainのshimがありません: %s（home-manager switchを先に実行）\n' "$SAFE_CHAIN_SHIMS" >&2
  exit 1
fi
safe_npm() { mise exec -- "$SAFE_CHAIN_SHIMS/npm" "$@"; }

step "pnpm"
# safe-chainのshimでcommand -vは常に成功するため、実体が動くかで判定
if ! pnpm --version >/dev/null 2>&1; then
  safe_npm install -g pnpm@latest
  mise reshim
fi

step "Qwen Code"
if ! command -v qwen >/dev/null; then
  safe_npm install -g @qwen-code/qwen-code@latest
  mise reshim
fi

step "Pi"
if ! command -v pi >/dev/null; then
  safe_npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
  mise reshim
fi

step "Codex CLI"
curl -fsSL https://chatgpt.com/codex/install.sh | sh

step "Claude Code"
curl -fsSL https://claude.ai/install.sh | bash

ok "Ubuntuの基礎セットアップが完了しました"
echo "次: $REPO_DIR/scripts/install-tailscale-ubuntu.sh"
echo "GPUドライバ・カーネル・ComfyUIなどは第2段（docs/ubuntu-server.md）で別途セットアップします"
