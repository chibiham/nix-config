# ちびはむ's Nix Config

Nix + Home Manager による環境構築。

## 構成

```
├── flake.nix           # エントリーポイント
├── flake.lock          # 依存関係ロック（自動生成）
└── home/
    ├── common.nix      # 共通設定
    ├── darwin.nix      # macOS固有
    └── wsl.nix         # WSL固有
```

## 前提条件

### Nix

Nixパッケージマネージャが必要です：

```bash
# macOS / Linux
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

### Homebrew（macOS のみ）

GUIアプリケーション管理のため、Homebrewが必要です：

```bash
# 1. Homebrewインストール
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. .zprofile を設定（Nix競合回避のため手動設定）
cat > ~/.zprofile << 'EOF'
#
# Homebrew環境設定
#
# Note: その他の環境変数・エイリアスはNix (common.nix) で管理
#

eval "$(/opt/homebrew/bin/brew shellenv)"
EOF
```

**重要:** Homebrewインストール時に `.zprofile` への自動追記を提案されますが、上記の最小構成を手動で設定することでNixとの競合を回避します。

## 使い方

### 初回セットアップ

```bash
# 1. Nix管理のパッケージ・設定を適用
cd ~/.config/nix-config
nix run home-manager -- switch --flake .#chibimaru@darwin

# 2. Homebrew GUIアプリケーションをインストール
brew bundle  # HOMEBREW_BREWFILE環境変数により自動的にBrewfileを使用
```

**Note:** `brew bundle` はmacOS専用。Brewfileは `~/.config/nix-config/Brewfile` で管理。

### 設定変更後の適用

```bash
cd ~/.config/nix-config
home-manager switch --flake .#chibimaru@darwin

# Brewfileを変更した場合は別途実行
brew bundle
```

### WSLの場合

```bash
home-manager switch --flake .#chibimaru@wsl
```

## Unfreeパッケージについて

Nixpkgsではライセンスによりパッケージが分類されています。

| 分類 | 説明 | 例 |
|------|------|-----|
| **Free** | OSS / 自由に再配布可能 | git, nodejs, zsh |
| **Unfree** | プロプライエタリ / 制限あり | 1password-cli, vscode |

Nixは再現性を重視し、ライセンス的に自由でないパッケージはデフォルトでブロックされます。
このリポジトリでは `flake.nix` で `allowUnfree = true` を設定し、unfreeパッケージも使用可能にしています。

## 1Password連携

シークレット管理に1Password CLIを使用。シェル起動時に自動的に1Passwordからシークレットを取得します。

### 方針

- **1Password CLIのみNix管理**（GUIはHomebrew等で別途インストール）
- **Service Account Token**を使用してシークレットを自動取得
- シェル起動時に環境変数が自動設定され、通常のコマンドがそのまま使える
- GPG鍵も1Passwordから自動インポート

### 初期構築フロー

```bash
# 1. 1Password Service Account Token を取得
# https://my.1password.com/developer/serviceaccounts からトークンを作成
# MyMachine Vault への read 権限を付与

# 2. ~/.secrets/.env にトークンを保存
cp ~/.secrets/.env.template ~/.secrets/.env
# エディタで OP_SERVICE_ACCOUNT_TOKEN を設定

# 3. Home Manager適用
nix run home-manager -- switch --flake .#chibiham@darwin

# 4. 新しいシェルを開く → 自動的にシークレットが読み込まれる！
```

### 自動取得されるシークレット

MyMachine Vault から以下のシークレットが自動的に環境変数に設定されます：

- `OPENAI_API_KEY` - OpenAI APIキー
- `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` - AWS認証情報
- `CLOUDFLARE_API_TOKEN` - Cloudflare APIトークン
- `GEMINI_API_KEY` - Google Gemini APIキー
- `CLAUDE_CODE_OAUTH_TOKEN` - Claude Code OAuth トークン
- `ANTHROPIC_API_KEY` - Anthropic APIキー
- `BRAVE_API_KEY` - Brave Search APIキー

### GPG鍵の自動インポート

`home-manager switch` 時に、1PasswordのMyMachine Vault内の `gpg-key-chibiham` アイテムからGPG秘密鍵を自動的にインポートします。

詳細は [docs/1password-cli.md](docs/1password-cli.md) を参照。

### SSH Agent連携

1Password SSH Agentを使用してSSHキーを管理。git clone/pushなどがパスワードなしで可能に。

#### メリット

- SSHキーを1Passwordで一元管理
- 複数マシンで同じSSHキーを使用可能
- 1Passwordのロック解除だけで認証完了
- キーのローテーションが容易

#### セットアップ

**1. 1Password側の設定**

1. 1Password デスクトップアプリを開く
2. 設定 → Developer → SSH Agent を有効化
3. SSHキーを1Passwordに保存（既存キーのインポートまたは新規作成）

**2. Nix設定（自動適用済み）**

```nix
# darwin.nix
home.sessionVariables = {
  SSH_AUTH_SOCK = "$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock";
};

# wsl.nix（別途 npiperelay + socat 設定が必要）
home.sessionVariables = {
  SSH_AUTH_SOCK = "$HOME/.1password/agent.sock";
};
```

**3. 動作確認**

```bash
# 新しいシェルを開いて確認
ssh-add -l              # 1Passwordのキーが表示される
ssh -T git@github.com   # GitHub接続テスト
```

#### WSLでの追加設定

WSLでは Windows側の1Password SSH Agentと連携するため、npiperelay が必要:

```bash
# Windows側: 1Password設定でSSH Agentを有効化
# WSL側: socat + npiperelay でソケット転送
# 詳細: https://developer.1password.com/docs/ssh/integrations/wsl/
```

## Spotlight統合（macOS）

NixでインストールしたアプリケーションをSpotlightで検索可能にするため、**[mac-app-util](https://github.com/hraban/mac-app-util)** を使用。

### 仕組み

- トランポリンアプリを`~/Applications/Home Manager Trampolines/`に作成
- `home-manager switch`時に自動実行
- Spotlightが認識できる形式でアプリを配置

### 対象アプリケーション

- WezTerm
- 今後Nixで追加するすべてのGUIアプリ

詳細は flake.nix の `mac-app-util.homeManagerModules.default` を参照。

## Homebrew管理（macOS）

macOSでは **Homebrew** と **Nix** を併用。役割分担は以下の通り：

### 棲み分け

| 管理ツール | 管理対象 | 理由 |
|-----------|---------|------|
| **Nix** | CLIツール、LSPサーバー、シェル環境 | 宣言的・再現可能・クロスプラットフォーム |
| **Homebrew** | GUIアプリケーション、フォント | macOS統合・CaskのCLIツール（code, dockerコマンド等） |

### Brewfile管理

- **場所**: `~/.config/nix-config/Brewfile`（Git管理）
- **環境変数**: `HOMEBREW_BREWFILE` で自動的にBrewfileを参照
- **更新**: `brew bundle dump --force --describe` で現在の状態を保存

### GUIアプリのCLIツール

Homebrewでインストールしたアプリが提供するCLIツールは `/opt/homebrew/bin/` に自動配置される：

- Visual Studio Code → `code` コマンド
- Docker Desktop → `docker`, `docker-compose` コマンド
- GitHub Desktop → `github` コマンド
- ngrok → `ngrok` コマンド

このため、GUIアプリのみの場合でも `.zprofile` で `brew shellenv` の実行が必要。

### PATH優先順位

PATH の優先順位は以下の通り（先頭ほど優先）：

1. **Nix管理のパッケージ** - Home Managerが `~/.nix-profile/bin` を先頭に配置
2. **Homebrewのパッケージ** - `.zprofile` の `brew shellenv` で `/opt/homebrew/bin` を追加
3. **システムコマンド** - `/usr/bin`, `/bin` 等

**設計意図:**
- 同名のコマンドがある場合、Nix版を優先（再現性重視）
- HomebrewはGUIアプリ付属のCLIツール用（`code`, `docker`等）
- `.zprofile` で `brew shellenv` のみを実行し、NixとHomebrew のPATH設定を明確に分離

## バージョン管理（mise）

プログラミング言語のバージョン管理には **mise** を使用。プロジェクトごとに異なるバージョンを自動的に切り替え可能。

### 特徴

- **対応言語**: Node.js, Python, Go, Rust, Ruby等
- **自動検出**: `.node-version`, `.python-version`等を自動検出
- **自動切り替え**: direnv連携により、プロジェクトディレクトリに入ると自動的にバージョンが切り替わる
- **Nix統合**: mise本体はNix管理、ランタイムはmise管理

### 基本的な使い方

```bash
# プロジェクトでバージョン指定
cd ~/projects/my-app
mise use node@20  # .node-version ファイルが作成される

# グローバルバージョン設定
mise use --global node@22
mise use --global python@3.12

# バージョン確認
mise ls
mise ls-remote node
```

### Nix vs mise の役割分担

| 管理ツール | 管理対象 | 理由 |
|-----------|---------|------|
| **Nix** | LSPサーバー、フォーマッター、システムツール、mise本体 | 安定性・一貫性重視 |
| **mise** | Node.js, Python, Go, Rust等のランタイム | 柔軟なバージョン切り替え |

詳細は [docs/mise-setup.md](docs/mise-setup.md) を参照。

## 手動設定が必要な項目

以下はNix管理外のため、新しいマシンでは手動設定が必要。

### 1Password Service Account Token（~/.secrets/.env）

1Password CLIの認証に**Service Account Token**を使用します。

**セットアップ:**

```bash
# 1. テンプレートからコピー
cp ~/.secrets/.env.template ~/.secrets/.env

# 2. 1Password Service Account Token を設定
# https://my.1password.com/developer/serviceaccounts から取得
vim ~/.secrets/.env
```

**設定内容:**

```bash
# 必須: 1Password Service Account Token
export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"
```

このトークンがあれば、他のシークレット（OpenAI, AWS等）は自動的に1Passwordから取得されます。

**注意:**
- このファイルはNix管理外、`.gitignore` 済み
- マシン移行時は新しいトークンを発行して設定
- シェル起動時に自動で `source` される

### Clawdbot

LaunchAgentで動作するため、シェル経由の環境変数読み込みが使えない。
環境変数は `~/.clawdbot/.env` に別途記述する。

```bash
# ~/.clawdbot/.env
OPENAI_API_KEY=sk-xxx
ANTHROPIC_API_KEY=sk-ant-xxx
```

**注意:** `~/.secrets/.env` と同じ値を設定すること。
