# Nix Configuration

Nix + Home Managerによる環境構築プロジェクト。macOSとWSLの両方で同じ開発環境を再現可能にする。

## ディレクトリ構成

```
.
├── flake.nix          # エントリーポイント
├── flake.lock
└── home/
    ├── common.nix     # 共通設定（両OS）
    ├── darwin.nix     # macOS固有設定
    └── wsl.nix        # WSL固有設定
```

## 使い方

```bash
# macOS (Apple Silicon)
nix run home-manager -- switch --flake .#chibimaru@darwin

# WSL
nix run home-manager -- switch --flake .#chibimaru@wsl
```

## 1Password連携

### 方針

- **1Password CLIのみNix管理**（GUIはHomebrew/手動）
- シークレット参照は `op://vault/item/field` 形式で設定
- `home-manager switch` 自体は1Password認証不要
- シークレットが必要なコマンドは `op run` で実行

### 初期構築フロー

```bash
# 1. Home Manager適用（認証不要）
nix run home-manager -- switch --flake .#chibimaru@darwin

# 2. 1Password認証（1回だけ）
op signin

# 3. 以降、シークレットを使うコマンドは op run 経由
op run -- some-command
```

### シークレット参照の例

```nix
home.sessionVariables = {
  # 文字列として設定（この時点では値は解決されない）
  GITHUB_TOKEN = "op://Development/GitHub/credential";
  AWS_ACCESS_KEY_ID = "op://AWS/Production/access_key_id";
};
```

実行時に `op run` でシークレットが解決される：

```bash
op run -- npm publish  # GITHUB_TOKEN が実際の値に置換されて実行
```

## 管理対象

### パッケージ

- 開発ツール: git, gh, jq, ripgrep, fd, fzf, eza, bat, delta
- ターミナル: WezTerm (GPU高速化、クロスプラットフォーム)
- バージョン管理: mise (Node.js, Python, Go, Rust等)
- Node.js: mise管理（プロジェクトごとにバージョン切り替え）
- Python: mise管理（同上）
- LSPサーバー: Nix管理（typescript-language-server, pyright, gopls等 - 全8言語）
- pnpm グローバルパッケージ: clawdbot（home-manager switch時に自動インストール）
- シークレット管理: 1password-cli
- その他: htop, tree, curl, wget

### macOS統合

- **Spotlight統合**: mac-app-util（トランポリンアプリ作成）
  - Nixアプリが CMD+Space で検索可能
  - `home-manager switch`時に自動実行
  - トランポリン配置先: `~/Applications/Home Manager Trampolines/`

### シェル設定

- Zsh（autosuggestion, syntax-highlighting, completion）
- Starship（プロンプト）
- direnv + nix-direnv + mise
- fzf

### Git設定

- ユーザー情報、エイリアス
- GPG署名（macOS: Homebrew gpg, WSL: Nix gpg）
- VS Code連携（editor, diff, merge）
