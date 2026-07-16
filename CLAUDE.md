# Nix Configuration

Nix + Home Managerによる環境構築プロジェクト（macOS用）。
複数のMacで同じ開発環境を再現可能にする。

## 設計方針

- **`home-manager switch` は認証・ネットワーク不要で常に冪等**
  （宣言的なファイル配置・パッケージ導入のみ。ローカル完結しない処理はactivationに書かない）
- **命令的な初期構築は `scripts/bootstrap.sh` に集約**
  （1PasswordからのSSH鍵取得、プライベートリポジトリclone、mise/pnpmの初期導入、macOS設定）
- **Home Manager CLIはflake.lockでピン留め**
  （`nix run home-manager` はregistry経由でmaster追従になるため使わない。必ず `nix run .#home-manager` を使う）
- **Git認証・署名・authorized_keysは1Password管理の共通マシン鍵 `~/.ssh/id_ed25519` に一本化**

## ディレクトリ構成

```
.
├── flake.nix          # エントリーポイント（mkDarwinHomeでユーザー定義）
├── flake.lock
├── home/
│   ├── common.nix     # 共通設定
│   └── darwin.nix     # macOS固有設定
└── scripts/
    ├── bootstrap.sh       # 新マシン初期セットアップ（冪等、再実行可）
    └── macos-defaults.sh  # macOSシステム設定（sudo必要、冪等）
```

## 使い方

### 新しいMacの初期構築

```bash
# 1. Nixインストール（未導入なら）
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# 2. このリポジトリをclone（初回はHTTPSで）
git clone https://github.com/chibiham/nix-config.git ~/.config/nix-config

# 3. ブートストラップ実行（対話的にOP_SERVICE_ACCOUNT_TOKENを聞かれる）
~/.config/nix-config/scripts/bootstrap.sh
```

bootstrap.shがやること（すべて冪等、途中失敗しても再実行すればよい）:
1. `home-manager switch -b backup`（既存dotfileは `*.backup` に退避）
2. 1Password Service Account Token を `~/.secrets/.env` に保存
3. SSH鍵を1Passwordから取得（`op://MyMachine/chibiham_machine_key`）
4. `update-secrets` でシークレット展開
5. プライベートリポジトリのclone（memo, clawd, affairs, skills）
6. mise ランタイム（node/python/pnpm）と pnpm グローバルパッケージ導入
7. Homebrew導入 + `brew bundle`（GUIアプリ）
8. macOSシステム設定（任意、sudo必要）

### 日常の設定反映

```bash
nix run ~/.config/nix-config#home-manager -- switch --flake ~/.config/nix-config#$USER@darwin
```

**注意**: `$USER` のflake.nix該当エントリが必要（`mkDarwinHome` で追加）。

### 変更時の検証

```bash
# 全構成が評価できるか確認（switchする前に）
nix eval --raw '.#homeConfigurations."chibiham@darwin".activationPackage.drvPath'
```

push/PR時はGitHub Actions CI（`.github/workflows/ci.yml`）が全ユーザー分の評価を実行。
`flake.lock` は毎週月曜に自動更新PRが作られる（`update-flake-lock.yml`）。
`.nix` の整形は `nix fmt`（nixfmt-rfc-style）。

### unstableパッケージ

更新の速いツール（gemini-cli, flyctl）は `flake.nix` の `unstableOverlay` で
nixpkgs-unstableから取得。追加するときはoverlayの `inherit` リストに足す。

## 1Password連携

- **1Password CLIのみNix管理**（GUIはHomebrew/手動）
- 認証は **Service Account Token**（`~/.secrets/.env` の `OP_SERVICE_ACCOUNT_TOKEN`、git管理外）
- `home-manager switch` は1Password認証不要
- シークレットの実体は `update-secrets` コマンド（Nixが配布）で
  `~/.secrets/env.tpl` から `~/.secrets/.env.secrets` に展開され、zshrcが読み込む
- シークレットを追加するときは `common.nix` の `env.tpl` にop参照を追記 → switch → `update-secrets`

```bash
# シークレットを更新したいとき
update-secrets
```

## Git / SSH の構成

- **認証**: github.com は `~/.ssh/id_ed25519`（鍵ファイル直接、`IdentityAgent none`）
- **署名**: 同じ鍵でSSH署名（`gpg.format = ssh`、commit/tag常時署名）。
  検証用に `~/.config/git/allowed_signers` もNixが配置
- **その他ホスト**: 1Password SSH Agent（darwin.nixの `Host *`）
- github.com は `StrictHostKeyChecking accept-new` で初回接続も非対話で通る

## 手動設定（Nix管理外）

macOSのセキュリティ制約により自動化できないもの:

- **Ghosttyにフルディスクアクセスを付与**: システム設定 > プライバシーとセキュリティ > フルディスクアクセス > Ghosttyを追加して有効化

## 管理対象

### パッケージ

- 開発ツール: git, gh, jq, ripgrep, fd, fzf, eza, bat, delta
- バージョン管理: mise (Node.js, Python, pnpm等はmise管理)
- LSPサーバー: Nix管理（typescript-language-server, pyright, gopls等 - 全8言語）
- pnpm グローバルパッケージ: clawdbot（bootstrap.shで導入）
- シークレット管理: 1password-cli + update-secretsコマンド
- その他: htop, tree, curl, wget, awscli, terraform, flyctl, cloudflared

### macOS統合

- **Spotlight統合**: mac-app-util（トランポリンアプリ作成、switch時に自動実行）
- **Karabiner-Elements**: karabiner.jsonをNix管理（GUI変更はswitchで上書きされる）
- **Ghostty**: 設定（`~/.config/ghostty/config`）をNix管理。アプリ本体はHomebrew cask
- **GUIアプリ**: Brewfile（bootstrap.shで `brew bundle` 実行）
- **Nix GC**: 週次で30日超の世代を自動削除（`nix.gc`、launchd）

### シェル設定

- Zsh（autosuggestion, syntax-highlighting, completion）
- Starship（プロンプト）
- direnv + nix-direnv + mise
- fzf, tmux, NeoVim
