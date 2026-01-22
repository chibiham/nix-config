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

## 使い方

### 初回セットアップ

```bash
cd ~/.config/nix-config
nix run home-manager -- switch --flake .#chibimaru@darwin
```

### 設定変更後の適用

```bash
cd ~/.config/nix-config
home-manager switch --flake .#chibimaru@darwin
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

シークレット管理に1Password CLIを使用。

### 方針

- **1Password CLIのみNix管理**（GUIはHomebrew等で別途インストール）
- シークレット参照は `op://vault/item/field` 形式で環境変数に設定
- `home-manager switch` 自体は1Password認証不要
- シークレットが必要なコマンドは `op run` で実行

### 初期構築フロー

```bash
# 1. Home Manager適用（認証不要）
nix run home-manager -- switch --flake .#chibimaru@darwin

# 2. 1Password認証（初回のみ）
op signin

# 3. シークレットを使うコマンドは op run 経由
op run -- some-command
```

### シークレット参照の例

```nix
# home/common.nix
home.sessionVariables = {
  GITHUB_TOKEN = "op://Development/GitHub/credential";
};
```

```bash
# 実行時にシークレットが解決される
op run -- gh pr create
```

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

## 手動設定が必要な項目

以下はNix管理外のため、新しいマシンでは手動設定が必要。

### シークレット環境変数（~/.secrets/.env）

APIキー等のシークレットは `~/.secrets/.env` に平文で保存し、シェル起動時に読み込む。

**セットアップ:**

```bash
# 1. テンプレートからコピー
cp ~/.secrets/.env.template ~/.secrets/.env

# 2. 1Password（MyMachine Vault）から値をコピーして設定
vim ~/.secrets/.env
```

**テンプレート内容:**

```bash
export OPENAI_API_KEY=""
export ANTHROPIC_API_KEY=""
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export CLOUDFLARE_API_TOKEN=""
export GEMINI_API_KEY=""
export CLAUDE_CODE_OAUTH_TOKEN=""
```

**注意:**
- このファイルはNix管理外、`.gitignore` 済み
- マシン移行時は1Passwordから値をコピーして再設定
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
