# 1Password CLI 連携ガイド

このプロジェクトでは1Password CLIを使用してシークレット管理を自動化しています。

## 概要

### 特徴

- **自動シークレット取得**: シェル起動時に1Passwordからシークレットを自動的に環境変数に設定
- **GPG鍵自動インポート**: `home-manager switch` 時にGPG秘密鍵を自動インポート
- **`op run` 不要**: 通常のコマンドがそのまま使える（ラッパー不要）
- **マシン間同期**: Service Account Token 1つで全シークレットにアクセス可能

### アーキテクチャ

```
┌─────────────────────────┐
│ 1Password MyMachine     │
│ Vault                   │
│                         │
│ - OPENAI_API_KEY        │
│ - AWS_CREDENTIALS       │
│ - GEMINI_API_KEY        │
│ - gpg-key-chibiham      │
│ ...                     │
└───────────┬─────────────┘
            │
            │ Service Account Token
            │ (OP_SERVICE_ACCOUNT_TOKEN)
            ↓
┌─────────────────────────┐
│ ~/.secrets/.env         │
│                         │
│ export OP_SERVICE_      │
│ ACCOUNT_TOKEN="ops..."  │
└───────────┬─────────────┘
            │
            │ シェル起動時に source
            ↓
┌─────────────────────────┐
│ ~/.zshrc                │
│ (Nix管理)               │
│                         │
│ op read で各シークレット │
│ を取得して export        │
└───────────┬─────────────┘
            │
            ↓
┌─────────────────────────┐
│ 環境変数が自動設定される │
│                         │
│ $OPENAI_API_KEY         │
│ $AWS_ACCESS_KEY_ID      │
│ $GEMINI_API_KEY         │
│ ...                     │
└─────────────────────────┘
```

## 初期セットアップ

### 1. Service Account の作成

1. **1Password.com にログイン**
   - https://my.1password.com/developer/serviceaccounts にアクセス

2. **Create Service Account をクリック**

3. **Service Account の設定**
   - **Name**: `nix-config-chibiham`（分かりやすい名前）
   - **Vault Access**: `MyMachine` Vault に **Read** 権限を付与
   - 他のVaultへのアクセスは不要

4. **トークンをコピー**
   - `ops_` で始まる長いトークンが表示される
   - **これは一度しか表示されないので必ずコピーする**

### 2. トークンの保存

```bash
# テンプレートをコピー
cp ~/.secrets/.env.template ~/.secrets/.env

# エディタで編集
vim ~/.secrets/.env
```

```bash
# ~/.secrets/.env
export OP_SERVICE_ACCOUNT_TOKEN="ops_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### 3. 必要なシークレットを1Passwordに登録

MyMachine Vault に以下のアイテムを登録します：

| アイテム名 | タイプ | フィールド | 用途 |
|-----------|--------|-----------|------|
| `OPEN_AI_API_KEY` | API Credential | `credential` | OpenAI API |
| `AWS_CREDENTIALS` | Login | `username`, `password` | AWS CLI |
| `CLOUDFLARE_API_TOKEN` | API Credential | `credential` | Cloudflare API |
| `GEMINI_API_KEY` | API Credential | `credential` | Google Gemini |
| `CLAUDE_CODE_AUTH_TOKEN` | API Credential | `credential` | Claude Code |
| `ANTHROPIC_API_KEY` | API Credential | `credential` | Anthropic API |
| `BRAVE_API_KEY` | API Credential | `credential` | Brave Search |
| `gpg-key-chibiham` | Secure Note | `private_key` (file) | GPG署名用 |

### 4. 動作確認

```bash
# 新しいシェルを開く
exec zsh

# 環境変数が設定されているか確認
echo $OPENAI_API_KEY
# => sk-proj-... （実際の値が表示される）

echo $AWS_ACCESS_KEY_ID
# => AKIA... （実際の値が表示される）

# GPG鍵が自動インポートされているか確認
gpg --list-secret-keys
# => sec   rsa4096/... chibiham (zzz...) <ryuto.chiba@chibiham.com>
```

## 仕組みの詳細

### シェル起動時の動作

`~/.zshrc`（Nix管理）で以下の処理が実行されます：

```bash
# 1. ~/.secrets/.env を読み込み（OP_SERVICE_ACCOUNT_TOKEN取得）
[[ -f ~/.secrets/.env ]] && source ~/.secrets/.env

# 2. 1Password からシークレットを取得
if command -v op &> /dev/null && [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
  export OPENAI_API_KEY=$(op read "op://MyMachine/OPEN_AI_API_KEY/credential" 2>/dev/null || echo "")
  export AWS_ACCESS_KEY_ID=$(op read "op://MyMachine/AWS_CREDENTIALS/username" 2>/dev/null || echo "")
  export AWS_SECRET_ACCESS_KEY=$(op read "op://MyMachine/AWS_CREDENTIALS/password" 2>/dev/null || echo "")
  # ... 他のシークレット
fi
```

### home-manager switch 時の動作

`home/common.nix` の activation hook で以下が実行されます：

```nix
home.activation.setupGPG = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  # GPG鍵がまだインポートされていない場合のみ
  if command -v op &> /dev/null && [ -n "$OP_SERVICE_ACCOUNT_TOKEN" ]; then
    if ! gpg --list-secret-keys 973655571CACBD16FB1DD4E1455F463BA021E7D9 &>/dev/null; then
      echo "Importing GPG key from 1Password..."
      op read "op://MyMachine/gpg-key-chibiham/private_key" | gpg --import
      echo "973655571CACBD16FB1DD4E1455F463BA021E7D9:6:" | gpg --import-ownertrust
    fi
  fi
'';
```

## トラブルシューティング

### シークレットが取得できない

```bash
# 1Password CLI が動作しているか確認
op whoami
# => Account: ...
# => User: ...

# 手動でシークレットを取得してみる
op read "op://MyMachine/OPEN_AI_API_KEY/credential"
# => エラーが出る場合、アイテム名やフィールド名を確認
```

**よくある原因:**
- Service Account の Vault アクセス権限が不足
- アイテム名やフィールド名のスペルミス
- `OP_SERVICE_ACCOUNT_TOKEN` が正しく設定されていない

### GPG鍵がインポートされない

```bash
# 1Passwordから手動でインポートしてみる
op read "op://MyMachine/gpg-key-chibiham/private_key" | gpg --import

# エラーが出る場合、ファイル名を確認
op item get "gpg-key-chibiham" --vault MyMachine --format json
```

**確認ポイント:**
- 1Passwordのアイテム名が `gpg-key-chibiham` であること
- ファイルフィールド名が `private key` であること（大文字小文字区別あり）
- ファイルがアスキーアーマー形式（`.asc`）であること

### 環境変数が空になる

```bash
# zshrc を再読み込み
source ~/.zshrc

# エラーメッセージを確認（stderr を表示）
op read "op://MyMachine/OPEN_AI_API_KEY/credential"
```

**よくある原因:**
- 1Passwordのアイテムが存在しない
- フィールド名が間違っている（`credential` vs `password`）
- Service Account の権限が不足

## 新しいマシンでのセットアップ

1. **Nixインストール**
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
   ```

2. **リポジトリクローン**
   ```bash
   git clone <repo-url> ~/.config/nix-config
   cd ~/.config/nix-config
   ```

3. **Service Account Token を設定**
   ```bash
   mkdir -p ~/.secrets
   echo 'export OP_SERVICE_ACCOUNT_TOKEN="ops_your_token_here"' > ~/.secrets/.env
   chmod 600 ~/.secrets/.env
   ```

4. **home-manager 適用**
   ```bash
   nix run home-manager -- switch --flake .#chibiham@darwin
   ```

5. **新しいシェルを開いて確認**
   ```bash
   exec zsh
   echo $OPENAI_API_KEY  # シークレットが表示される
   gpg --list-secret-keys  # GPG鍵がインポートされている
   ```

## セキュリティ考察

### Service Account Token のセキュリティ

**メリット:**
- 1つのトークンで複数のシークレットを管理
- トークンのローテーションが容易
- きめ細かい権限設定（Vault単位、Read/Write）

**デメリット:**
- トークンが漏洩すると、全シークレットにアクセス可能
- シェルセッションに環境変数が常駐（メモリダンプのリスク）

### リスク軽減策

1. **権限の最小化**
   - Service Account には MyMachine Vault の Read 権限のみ付与
   - 他のVaultへのアクセスは許可しない

2. **トークンの保護**
   - `~/.secrets/.env` のパーミッションを `600` に設定
   - Git に含めない（`.gitignore` 済み）

3. **定期的なローテーション**
   - Service Account Token を定期的に再発行
   - 古いトークンを無効化

4. **別の選択肢（より高セキュリティ）**
   - 1Password Desktop App Integration を使用（トークン不要）
   - ただし、コマンドごとに `op run` が必要

## FAQ

### Q: `op run` を使わなくて良いの？

A: はい。シェル起動時に環境変数が設定されるため、`op run` は不要です。

```bash
# これが動く（op run 不要）
npm publish
aws s3 ls
git commit -S
```

### Q: デスクトップアプリ統合との違いは？

| 方式 | メリット | デメリット |
|------|---------|-----------|
| **Service Account Token** | シェル起動時に自動設定、コマンドがそのまま使える | トークン管理が必要 |
| **Desktop App Integration** | トークン不要、より安全 | 毎回 `op run` が必要 |

個人の開発マシンでは **Service Account Token** 方式が便利です。

### Q: シークレットを追加したい場合は？

1. **1Passwordに新しいアイテムを追加**
2. **`home/common.nix` を編集**
   ```nix
   export NEW_SECRET=$(op read "op://MyMachine/NEW_ITEM/credential" 2>/dev/null || echo "")
   ```
3. **home-manager switch**
   ```bash
   home-manager switch --flake .#chibiham@darwin
   ```

### Q: 別のマシンで同じ設定を使いたい

同じ Service Account Token を使えば、複数のマシンで同じシークレットにアクセスできます。ただし、セキュリティ上は**マシンごとに別のService Accountを作成**することを推奨します。

## 参考リンク

- [1Password CLI Documentation](https://developer.1password.com/docs/cli/)
- [Service Accounts](https://developer.1password.com/docs/service-accounts/)
- [Secret References](https://developer.1password.com/docs/cli/secret-references/)
