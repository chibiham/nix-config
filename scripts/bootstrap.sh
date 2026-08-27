#!/usr/bin/env bash
# 新しいMacの初期セットアップスクリプト
#
# home-manager switch 自体は認証・ネットワーク不要で冪等。
# 認証やネットワークに依存する命令的な処理はすべてこのスクリプトに集約する。
# 何度実行しても安全（冪等）。
#
# 使い方:
#   git clone https://github.com/chibiham/nix-config.git ~/.config/nix-config
#   ~/.config/nix-config/scripts/bootstrap.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "${HOST_PROFILE:-}" ]; then
  case "$(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Model Name/ { print $2; exit }')" in
    *"Mac mini"*) HOST_PROFILE="mac-mini" ;;
    *"MacBook"*)  HOST_PROFILE="macbook" ;;
    *)
      echo "Macの種類を判別できませんでした。HOST_PROFILE=macbook または mac-mini を指定してください。"
      exit 1
      ;;
  esac
fi

case "$HOST_PROFILE" in
  macbook|mac-mini) ;;
  *)
    echo "HOST_PROFILEは macbook または mac-mini を指定してください。"
    exit 1
    ;;
esac
FLAKE_TARGET="${USER}@${HOST_PROFILE}"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$1"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$1"; }

# -------------------------------------------------
# 0. 前提チェック
# -------------------------------------------------
if ! command -v nix &>/dev/null; then
  echo "Nixがインストールされていません。先に以下を実行してください:"
  echo "  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install"
  exit 1
fi

# -------------------------------------------------
# 1. Home Manager適用（認証不要）
#    flake.lockでピン留めされたHM CLIを使用。
#    初回は既存dotfileと衝突するため -b backup で退避。
# -------------------------------------------------
step "Home Manager switch（初回は既存dotfileを *.backup に退避）"
nix run "$REPO_DIR#home-manager" -- switch -b backup --flake "$REPO_DIR#$FLAKE_TARGET"

# switch直後のシェルにはまだPATHが通っていないため明示的に追加
export PATH="$HOME/.nix-profile/bin:$PATH"

# -------------------------------------------------
# 2. 1Password Service Account Token
# -------------------------------------------------
step "1Password Service Account Token の設定"
mkdir -p "$HOME/.secrets"
chmod 700 "$HOME/.secrets"
if ! grep -q '^export OP_SERVICE_ACCOUNT_TOKEN=' "$HOME/.secrets/.env" 2>/dev/null; then
  echo "https://my.1password.com/developer/serviceaccounts で取得したトークンを入力してください"
  read -rsp "OP_SERVICE_ACCOUNT_TOKEN: " token
  echo
  printf 'export OP_SERVICE_ACCOUNT_TOKEN="%s"\n' "$token" >> "$HOME/.secrets/.env"
  chmod 600 "$HOME/.secrets/.env"
  ok "~/.secrets/.env にトークンを保存しました"
else
  ok "トークンは設定済み"
fi
# shellcheck disable=SC1091
source "$HOME/.secrets/.env"

# -------------------------------------------------
# 3. SSH鍵を1Passwordから取得（Git認証・SSH署名共通のマシン鍵）
# -------------------------------------------------
step "SSH鍵の取得（op://MyMachine/chibiham_machine_key）"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"
if [ ! -s "$HOME/.ssh/id_ed25519" ]; then
  op read "op://MyMachine/chibiham_machine_key/private_key" > "$HOME/.ssh/id_ed25519"
  chmod 600 "$HOME/.ssh/id_ed25519"
  ok "SSH秘密鍵を取得しました (~/.ssh/id_ed25519)"
else
  ok "SSH秘密鍵は取得済み"
fi
# 公開鍵を秘密鍵から再生成（常に整合する）
ssh-keygen -y -f "$HOME/.ssh/id_ed25519" > "$HOME/.ssh/id_ed25519.pub"
# macOS Keychainに登録（ssh-add等での利用のため。Git認証は鍵ファイル直接参照）
ssh-add --apple-use-keychain "$HOME/.ssh/id_ed25519" 2>/dev/null || true

# -------------------------------------------------
# 4. シークレット展開（~/.secrets/.env.secrets）
# -------------------------------------------------
step "シークレットの展開"
update-secrets

# -------------------------------------------------
# 5. プライベートリポジトリのクローン
#    (github.comはssh_configで StrictHostKeyChecking accept-new 済み)
# -------------------------------------------------
step "プライベートリポジトリのクローン"
clone_repo() {
  local repo="$1" dest="$2"
  if [ -d "$dest" ]; then
    ok "$dest は取得済み"
  else
    git clone "git@github.com:$repo.git" "$dest" && ok "$repo → $dest"
  fi
}
clone_repo "chibiham/chibiham-memos" "$HOME/memo"
clone_repo "chibiham/clawd" "$HOME/clawd"
clone_repo "chibiham/affairs" "$HOME/affairs"
clone_repo "chibiham/skills" "$HOME/.agents/skills"

# skillsのシンボリックリンク等を反映するためもう一度switch（差分なしなら一瞬）
nix run "$REPO_DIR#home-manager" -- switch --flake "$REPO_DIR#$FLAKE_TARGET"

# -------------------------------------------------
# 6. mise ランタイム（node/python、config.tomlで宣言済み）
# -------------------------------------------------
step "mise ランタイムのインストール"
mise install --yes || warn "miseランタイムのインストールに失敗（後で 'mise install' を実行してください）"

# pnpmはmise/Aqua経由だと配布assetの変更で壊れやすいため、npmから導入
export PATH="$HOME/.local/share/mise/shims:$PATH"
if ! command -v pnpm &>/dev/null; then
  mise exec -- npm install -g pnpm@latest
  mise reshim
fi

# -------------------------------------------------
# 7. pnpm グローバルパッケージ
# -------------------------------------------------
step "pnpm グローバルパッケージ"
export PNPM_HOME="$HOME/.local/share/pnpm"
export PATH="$HOME/.local/share/mise/shims:$PNPM_HOME:$PATH"
mkdir -p "$PNPM_HOME"
if command -v pnpm &>/dev/null; then
  if [ ! -e "$PNPM_HOME/clawdbot" ]; then
    pnpm add -g clawdbot@latest && ok "clawdbot をインストールしました"
  else
    ok "clawdbot はインストール済み"
  fi
else
  warn "pnpmが見つかりません。'mise install' 後に再実行してください"
fi

# -------------------------------------------------
# 8. Homebrew + GUIアプリ（Brewfile）
#    CLIツールはNix管理。casks/masのGUIアプリのみHomebrewで導入
# -------------------------------------------------
step "Homebrew と GUIアプリ（Brewfile）"
if ! command -v brew &>/dev/null && [ ! -x /opt/homebrew/bin/brew ]; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
# インストール直後のシェルにはまだPATHが通っていない
if ! command -v brew &>/dev/null && [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
if command -v brew &>/dev/null; then
  brew bundle --file="$REPO_DIR/Brewfile" || warn "brew bundle が一部失敗しました（後で再実行してください）"
  ok "Brewfile を適用しました"
else
  warn "Homebrewが見つかりません。手動でインストール後、'brew bundle --file=$REPO_DIR/Brewfile' を実行してください"
fi

# -------------------------------------------------
# 9. macOSシステム設定（sudoが必要なため対話的に確認）
# -------------------------------------------------
step "macOSシステム設定"
read -rp "macOSのシステム設定（defaults / sshd / pmset等）を適用しますか？ [y/N] " apply_defaults
if [[ "$apply_defaults" =~ ^[Yy]$ ]]; then
  "$REPO_DIR/scripts/macos-defaults.sh"
else
  echo "スキップしました。後で実行: $REPO_DIR/scripts/macos-defaults.sh"
fi

echo
ok "セットアップ完了！新しいシェルを開いて利用を開始してください"
echo "  - 手動作業の残り: Ghosttyへのフルディスクアクセス付与（システム設定 > プライバシーとセキュリティ）"
echo "  - 以降の設定反映: nix run ~/.config/nix-config#home-manager -- switch --flake ~/.config/nix-config#$FLAKE_TARGET"
