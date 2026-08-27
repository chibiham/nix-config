# ちびはむ's Nix Config

Nix + Home Manager によるmacOS / Ubuntu環境構築。
複数のMacとUbuntu Serverで同じ開発環境を再現する。

**設計方針**: `home-manager switch` は認証・ネットワーク不要で常に冪等。
認証やネットワークに依存する命令的な処理は `scripts/` のOS別bootstrapに分離。

```
├── flake.nix              # エントリーポイント（ユーザー定義もここ）
├── flake.lock             # 依存関係ロック（自動生成）
├── Brewfile               # Homebrew管理のGUIアプリ
├── home/
│   ├── common.nix         # 共通設定（パッケージ、Git、Zsh、シークレット等）
│   ├── darwin.nix         # macOS固有（Karabiner、1Password SSH Agent等）
│   └── linux.nix          # Linux固有（genericLinux、headless設定）
└── scripts/
    ├── bootstrap.sh       # 新しいMacの初期セットアップ
    ├── bootstrap-ubuntu.sh # Ubuntu Serverの初期セットアップ
    ├── install-tailscale-ubuntu.sh # Tailscale導入・認証
    ├── install-nvidia-driver-ubuntu.sh # Ubuntu推奨NVIDIAドライバ
    ├── install-comfyui-ubuntu.sh # ComfyUI・専用Python環境・自動起動
    ├── update-comfyui-ubuntu.sh # ComfyUIの明示的更新
    ├── configure-comfyui-tailscale-serve.sh # tailnet内だけにHTTPS公開
    └── macos-defaults.sh  # macOSシステム設定（sudo必要、冪等）
```

---

## いつ、何をすればいいか

| やりたいこと | やること |
|---|---|
| 新しいMacをセットアップ | [→ 初回セットアップ](#初回セットアップ新しいmac) |
| Ubuntu Serverをセットアップ | [→ Ubuntu Server手順](docs/ubuntu-server.md) |
| `.nix` ファイルを変更した | `hms`（下記の適用コマンド） |
| GUIアプリを追加したい | `Brewfile` に追記 → `brew bundle` |
| CLIツールを追加したい | `home/common.nix` の `home.packages` に追記 → 適用 |
| シークレットを追加/ローテーションした | `env.tpl` 編集（追加時のみ）→ 適用 → `update-secrets` |
| Node/Python等のバージョンを変えたい | `mise use node@XX`（Nixは関与しない） |
| macOSのdefaults設定を変えたい | `scripts/macos-defaults.sh` を編集して実行 |
| パッケージを最新にしたい | `nix flake update` → 適用 |
| switchしたら環境が壊れた | [→ ロールバック](#切り分けロールバック) |

### 設定の適用コマンド

```bash
nix run ~/.config/nix-config#home-manager -- switch --flake ~/.config/nix-config#$USER@darwin
```

**注意**: `nix run home-manager -- ...`（`.#` なし）は使わないこと。
registry経由でmaster版CLIを引いてしまい、端末間で挙動が変わる原因になる。
`.#home-manager` は flake.lock でピン留めされている。

長いのでエイリアス推奨（zshrcはNix管理なので、シェルで一時定義するか common.nix に追加）:

```bash
alias hms='nix run ~/.config/nix-config#home-manager -- switch --flake ~/.config/nix-config#$USER@darwin'
```

---

## 初回セットアップ（新しいMac）

### 1. 前提ツール

```bash
# Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# Homebrew（GUIアプリ管理用）
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# .zprofile は brew shellenv のみの最小構成にする（Nixとの競合回避）
# ※ Homebrewインストーラの自動追記提案には乗らないこと
cat > ~/.zprofile << 'EOF'
eval "$(/opt/homebrew/bin/brew shellenv)"
EOF
```

### 2. ブートストラップ

```bash
# 初回はHTTPSでclone（SSH鍵はまだ無いため）
git clone https://github.com/chibiham/nix-config.git ~/.config/nix-config

# ユーザーがflake.nixに未定義なら、mkDarwinHomeのエントリを先に追加すること

~/.config/nix-config/scripts/bootstrap.sh
```

途中で **1Password Service Account Token** の入力を求められる。
[my.1password.com/developer/serviceaccounts](https://my.1password.com/developer/serviceaccounts) で
**MyMachine Vaultへのread権限** を付けて発行しておく。

bootstrap.sh がやること（全ステップ冪等。途中で失敗したら原因を直して再実行すればいい）:

1. `home-manager switch -b backup`（既存dotfileは `*.backup` に退避される）
2. トークンを `~/.secrets/.env` に保存
3. SSH鍵（マシン共通鍵）を1Passwordから `~/.ssh/id_ed25519` に取得
4. `update-secrets` でAPIキー類を `~/.secrets/.env.secrets` に展開
5. プライベートリポジトリのclone（memo, clawd, affairs, skills）
6. mise ランタイム（node/python/pnpm）と clawdbot の導入
7. Homebrew導入（未導入なら）と `brew bundle`（GUIアプリ）
8. macOSシステム設定（y/n確認あり、sudo必要）

### 3. GUIアプリ

bootstrap.sh が `brew bundle` まで実行する。以降 `Brewfile` にアプリを追加したときは:

```bash
brew bundle   # HOMEBREW_BREWFILE が設定済みなのでどこから実行してもOK
```

### 4. 残りの手動作業

Nixで自動化できないもの:

- **Ghosttyにフルディスクアクセス付与**: システム設定 > プライバシーとセキュリティ > フルディスクアクセス
- **1Password GUI**: サインインし、設定 > Developer > **SSH Agent を有効化**（github.com以外のSSH接続で使用）
- **Clawdbot用の環境変数**: LaunchAgent動作でシェルの環境変数を読めないため、`~/.clawdbot/.env` に別途記述（`~/.secrets/.env.secrets` と同じ値を設定）

### 5. 動作確認

```bash
ssh -T git@github.com                    # → "Hi chibiham!" が出ればSSH認証OK
git commit --allow-empty -m test && git log --show-signature -1   # → "Good git signature"
echo $OPENAI_API_KEY                     # → 新しいシェルでシークレットが読めていればOK
```

---

## シークレット管理

### ファイル配置（cron等が依存しているので変更しないこと）

| ファイル | 内容 | 作成者 |
|---|---|---|
| `~/.secrets/.env` | `OP_SERVICE_ACCOUNT_TOKEN` のみ | bootstrap.sh（手動でも可） |
| `~/.secrets/env.tpl` | opシークレット参照のテンプレート | Nix（common.nixで管理） |
| `~/.secrets/.env.secrets` | 展開済みの実シークレット | `update-secrets` コマンド |

zsh起動時に `.env` → `.env.secrets` の順で自動sourceされる。

### シークレットを追加するとき

1. 1Passwordの **MyMachine** Vaultにアイテムを作成
2. `home/common.nix` の `env.tpl` に `export FOO="op://MyMachine/FOO/credential"` を追記
3. switch で適用 → `update-secrets` を実行 → 新しいシェルで反映

### ローテーションしたとき

1Password側で値を変えたら `update-secrets` を叩くだけ。
**switchでは再展開されない**（意図的。switchを認証・ネットワーク非依存に保つため）。

---

## Git / SSH の仕組み

認証・署名・authorized_keys はすべて **1Password管理のマシン共通鍵 `~/.ssh/id_ed25519`** に一本化。

- **github.com**: 鍵ファイルを直接使用（`IdentityAgent none`）。1Passwordのロック状態に依存しない
- **コミット署名**: 同じ鍵でSSH署名（commit/tag常時）。検証用の `~/.config/git/allowed_signers` もNixが配置
- **その他のホスト**: 1Password SSH Agent（`Host *`）。使う鍵は1Password GUI側の
  `~/.config/1Password/ssh/agent.toml` で登録する（Agent有効化だけでは鍵は提供されない）
- 他マシンからのSSHログイン用に、同じ鍵の公開鍵が `authorized_keys` に自動追記される（既存行は消さない）

---

## パッケージ管理の棲み分け

| ツール | 管理対象 | 追加方法 |
|---|---|---|
| **Nix** | CLIツール、LSP、フォーマッター、シェル環境 | `common.nix` の `home.packages` |
| **Homebrew** | GUIアプリ、Cask付属のCLI（code, docker等） | `Brewfile` → `brew bundle` |
| **mise** | Node.js, Python, Go, Rust等のランタイム | `mise use node@XX`（プロジェクト） / `common.nix` の `mise/config.toml`（グローバル） |

PATHの優先順位は Nix (`~/.nix-profile/bin`) → Homebrew (`/opt/homebrew/bin`) → システム。
同名コマンドはNix版が勝つ（再現性重視）。

unfreeパッケージ（1password-cli等）は `flake.nix` の `allowUnfree = true` で許可済み。

---

## 依存の更新

GitHub Actionsが毎週月曜に `flake.lock` 更新PRを自動作成する（`.github/workflows/update-flake-lock.yml`）。
CIが全homeConfigurationsの評価チェックを行うので、通っていればmergeして各マシンでswitchすればよい。

手動で更新する場合:

```bash
cd ~/.config/nix-config
nix flake update        # nixpkgs / nixpkgs-unstable / home-manager / mac-app-util を更新
# 適用前に評価チェック
nix eval --raw '.#homeConfigurations."chibiham@darwin".activationPackage.drvPath'
# 問題なければ switch → 動作確認してから flake.lock をコミット
```

更新の速いツール（gemini-cli, flyctl）は `flake.nix` のoverlayで
nixpkgs-unstableから取得している。追加したいときはoverlayの `inherit` に足す。

`.nix` ファイルの整形は `nix fmt`（nixfmt-rfc-style）。

## 切り分け・ロールバック

switchで環境が壊れたら、直前の世代に戻せる:

```bash
home-manager generations            # 世代一覧
/nix/store/…-home-manager-generation/activate   # 戻りたい世代のactivateを実行
```

switch自体が失敗するときの典型原因:

- **既存ファイルとの衝突**（`Existing file ... would be clobbered`）→ `switch -b backup` で退避しながら適用
- **flake.nixにユーザー未定義** → `mkDarwinHome` エントリを追加
- switchは設計上ネットワーク・1Password認証に依存しないので、
  「1Passwordが認証できないからswitchが失敗する」はない。あればバグなので設計違反を疑う

---

## 詳細ドキュメント

- [docs/1password-cli.md](docs/1password-cli.md) — 1Password CLI連携の詳細
- [docs/mise-setup.md](docs/mise-setup.md) — miseの使い方
- [docs/neovim-setup.md](docs/neovim-setup.md) — NeoVim設定
- [CLAUDE.md](CLAUDE.md) — 設計方針（AI向け・人間も可）
