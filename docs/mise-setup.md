# mise セットアップ完全ガイド

最終更新: 2026-01-25

## 概要

miseは複数のプログラミング言語のバージョンを管理するツール。プロジェクトごとに異なるバージョンを自動的に切り替え可能。

## アーキテクチャ

- **バージョン管理**: mise (Polyglot runtime version manager)
- **自動切り替え**: direnv連携
- **検出方法**: `.node-version`, `.python-version`等を自動検出
- **グローバル設定**: `~/.config/mise/config.toml` (Nix管理)
- **LSPサーバー**: Nix管理（安定性優先）
- **ランタイム**: mise管理（柔軟性優先）

## Nix + mise の役割分担

### Nix管理（安定性重視）

以下は引き続きNixで管理（NeoVimで常に利用可能）:

- **LSPサーバー** (8言語)
  - typescript-language-server (TypeScript/JavaScript)
  - pyright (Python)
  - gopls (Go)
  - rust-analyzer (Rust)
  - nil (Nix)
  - lua-language-server (Lua)
  - vscode-langservers-extracted (JSON/HTML/CSS/ESLint)
  - yaml-language-server (YAML)
  - marksman (Markdown)

- **フォーマッター**
  - prettier (JS/TS/JSON/YAML)
  - black (Python)
  - gofumpt (Go)
  - rustfmt (Rust)
  - stylua (Lua)

- **システムツール**
  - git, gh, ripgrep, fd, fzf, eza, bat, delta
  - mise本体

### mise管理（柔軟性重視）

プロジェクトごとに異なるバージョンが必要なランタイム:

- Node.js (各バージョン)
- Python (各バージョン)
- pnpm (パッケージマネージャー)
- その他言語ランタイム（Ruby, Go, Rust等）

## 対応言語

以下の言語のバージョン管理に対応:

- **Node.js** (`.node-version`, `.nvmrc`)
- **Python** (`.python-version`)
- **Ruby** (`.ruby-version`)
- **Go** (`.go-version`)
- **Rust** (`rust-toolchain.toml`)
- **pnpm** (パッケージマネージャー)
- その他多数

## 基本的な使い方

### プロジェクトでバージョン指定

```bash
# プロジェクトディレクトリで
cd ~/projects/my-app

# Node.js 20を使用
mise use node@20

# .node-version ファイルが作成される
cat .node-version  # => 20

# ディレクトリを離れて戻ると自動的にNode.js 20に切り替わる
cd ~
node --version  # グローバル版 (22)

cd ~/projects/my-app
node --version  # => v20.x.x
```

### グローバルバージョン設定

```bash
# すべてのプロジェクトでデフォルトで使用するバージョン
mise use --global node@22
mise use --global python@3.12
```

### バージョン確認

```bash
# 現在のバージョン一覧
mise ls

# 利用可能なバージョン一覧
mise ls-remote node
mise ls-remote python
```

## 各言語のセットアップ

### Node.js

#### バージョンインストール

```bash
# 最新LTS
mise use node@lts

# 特定バージョン
mise use node@20
mise use node@22.1.0

# プロジェクト固有
cd ~/projects/legacy-app
mise use node@18
```

#### パッケージマネージャー

```bash
# pnpm も mise で管理
mise use pnpm@latest

# グローバルパッケージインストール
pnpm add -g some-package
```

#### .nvmrc対応

miseは `.nvmrc` も自動検出:

```bash
# プロジェクトに .nvmrc がある場合
echo "20" > .nvmrc
cd .  # ディレクトリ再読み込み
node --version  # => v20.x.x
```

#### package.jsonのenginesフィールド対応

```json
{
  "engines": {
    "node": ">=20.0.0"
  }
}
```

miseは`package.json`の`engines`フィールドも自動検出して適切なバージョンを使用します。

### Python

#### バージョンインストール

```bash
# 最新版
mise use python@latest

# 特定バージョン
mise use python@3.12
mise use python@3.11.7

# プロジェクト固有
cd ~/projects/ml-project
mise use python@3.11
```

#### 仮想環境との併用

```bash
# mise でバージョンを管理
mise use python@3.12

# 仮想環境は通常通り
python -m venv .venv
source .venv/bin/activate

# pipパッケージインストール
pip install numpy
```

#### pyproject.toml対応

```toml
[tool.mise.tools]
python = "3.12"
```

または`.python-version`ファイル:

```bash
echo "3.12" > .python-version
```

### Go

```bash
# 最新版
mise use go@latest

# 特定バージョン
mise use go@1.22
mise use go@1.21.5

# プロジェクト固有
cd ~/projects/go-app
mise use go@1.22
```

### Rust

```bash
# 安定版
mise use rust@stable

# 特定バージョン
mise use rust@1.75

# プロジェクト固有
cd ~/projects/rust-app
mise use rust@1.75
```

miseは`rust-toolchain.toml`も自動検出します。

### Ruby

```bash
# 最新版
mise use ruby@latest

# 特定バージョン
mise use ruby@3.3
mise use ruby@3.2.0

# プロジェクト固有
cd ~/projects/rails-app
mise use ruby@3.3
```

## バージョンアップグレード方法

### 個別ランタイムのアップグレード

```bash
# Node.js を最新の22系にアップグレード
mise upgrade node@22

# 特定バージョンにアップグレード
mise use node@22.5.0

# すべてをアップグレード
mise upgrade
```

### miseアップデート

mise自体はNix管理のため:

```bash
# 1. Nixパッケージ更新
cd ~/dotfiles/.config/nix-config
nix flake update

# 2. Home Manager適用
home-manager switch --flake .#chibimaru@darwin

# 3. mise バージョン確認
mise --version
```

### グローバルバージョン変更

```bash
# Node.js のグローバル版を20から22に変更
mise use --global node@22

# または設定ファイルを直接編集
vim ~/.config/mise/config.toml
# [tools]
# node = "22"

# 設定反映（Nix管理の場合）
cd ~/dotfiles/.config/nix-config
vim home/common.nix
# xdg.configFile."mise/config.toml".text の [tools] セクションを編集

home-manager switch --flake .#chibimaru@darwin
```

## direnv連携

### 自動的な動作

direnvとの連携により、プロジェクトディレクトリに入ると自動的にバージョンが切り替わる:

```bash
cd ~/projects/app-node20  # Node.js 20に自動切り替え
node --version  # => v20.x.x

cd ~/projects/app-node22  # Node.js 22に自動切り替え
node --version  # => v22.x.x
```

### .envrcとの併用

既存の `.envrc` がある場合も問題なし:

```bash
# .envrc
use mise

# カスタム環境変数も追加可能
export DATABASE_URL="..."
export API_KEY="..."
```

### トラブルシューティング

```bash
# direnv許可
direnv allow

# 強制リロード
direnv reload

# mise状態確認
mise doctor
```

## 動作確認

### LSPサーバー（Nix管理）

LSPサーバーは常に利用可能:

```bash
which typescript-language-server
# => /nix/store/.../bin/typescript-language-server

which pyright
# => /nix/store/.../bin/pyright
```

NeoVimで `:LspInfo` を実行して、LSPサーバーが正常動作しているか確認。

### ランタイム（mise管理）

ランタイムはプロジェクトごとに切り替わる:

```bash
which node
# => /Users/chibimaru/.local/share/mise/shims/node

node --version
# => v22.x.x (または .node-version で指定されたバージョン)

which python
# => /Users/chibimaru/.local/share/mise/shims/python

python --version
# => Python 3.12.x (または .python-version で指定されたバージョン)
```

## トラブルシューティング

### バージョンが切り替わらない

```bash
# 1. mise状態確認
mise doctor

# 2. direnv状態確認
direnv status

# 3. シェル再起動
exec zsh

# 4. PATH確認
echo $PATH | tr ':' '\n' | grep mise
# => ~/.local/share/mise/shims が含まれているか確認
```

### インストールエラー

```bash
# 1. キャッシュクリア
rm -rf ~/.cache/mise

# 2. 手動インストール
mise install node@22

# 3. ログ確認
mise doctor

# 4. 詳細ログ
MISE_DEBUG=1 mise install node@22
```

### shims が動作しない

```bash
# 1. PATH確認
echo $PATH | tr ':' '\n' | grep mise

# 2. mise再設定
mise reshim

# 3. シェル再起動
exec zsh
```

### NeoVimでNode.jsが見つからない

```bash
# 1. グローバルバージョン確認
mise ls

# 2. グローバルバージョンインストール
mise use --global node@22

# 3. NeoVim再起動
```

### pnpmグローバルパッケージが見つからない

```bash
# 1. pnpm確認
which pnpm
mise ls | grep pnpm

# 2. pnpmインストール
mise use --global pnpm@latest

# 3. グローバルパッケージ再インストール
pnpm add -g clawdbot@latest
```

## 設定ファイル

### グローバル設定 (~/.config/mise/config.toml)

Home Managerで管理されているため、直接編集しない:

```bash
# 編集する場合は
vim ~/dotfiles/.config/nix-config/home/common.nix

# xdg.configFile."mise/config.toml".text の部分を編集:
# [settings]
# auto_install = true
# legacy_version_file = true
# experimental = true
#
# [tools]
# node = "22"
# python = "3.12"
# pnpm = "latest"

# 適用
cd ~/dotfiles/.config/nix-config
home-manager switch --flake .#chibimaru@darwin
```

### プロジェクト設定

プロジェクトごとには `.tool-versions` または言語別ファイル:

```bash
# .node-version (推奨 - シンプル)
22

# .python-version
3.12

# または .tool-versions (複数言語)
node 22.1.0
python 3.12.1
ruby 3.3.0
```

### .tool-versions vs 言語別ファイル

**言語別ファイル（推奨）:**
- シンプル
- 他のツール（nvm, pyenv等）との互換性
- Gitコミット推奨

**. tool-versions:**
- 複数言語を1ファイルで管理
- asdf互換

## mise CLI リファレンス

```bash
# バージョン確認
mise --version

# ヘルプ
mise help
mise help use

# ランタイム管理
mise use <tool>@<version>           # インストール＆設定
mise use --global <tool>@<version>  # グローバル設定
mise install <tool>@<version>       # インストールのみ
mise uninstall <tool>@<version>     # アンインストール

# バージョン確認
mise ls                             # インストール済み一覧
mise ls-remote <tool>               # 利用可能バージョン一覧
mise current                        # 現在のバージョン
mise current <tool>                 # 特定ツールの現在バージョン

# アップグレード
mise upgrade                        # すべてアップグレード
mise upgrade <tool>                 # 特定ツールアップグレード

# 診断
mise doctor                         # 診断情報
mise env                            # 環境変数表示
mise which <command>                # コマンドのパス表示

# キャッシュ管理
mise cache clear                    # キャッシュクリア
mise prune                          # 未使用バージョン削除

# 設定
mise settings                       # 設定一覧
mise trust                          # 設定ファイルを信頼
```

## よくある質問

### Q: nvmやpyenvと併用できる?

A: 推奨しません。mise単独での使用を推奨。nvmやpyenvがインストールされている場合は削除してください。

```bash
# nvm削除
rm -rf ~/.nvm

# pyenv削除（Homebrewの場合）
brew uninstall pyenv
```

### Q: Dockerコンテナ内でも使える?

A: 使えますが、コンテナではランタイムを直接インストールする方が一般的。

```dockerfile
# Dockerfileでは通常のインストール方法を推奨
FROM node:22
# または
RUN apt-get install -y python3.12
```

### Q: CIでも使える?

A: 可能。GitHub ActionsやCircleCIでもmise対応。

```yaml
# .github/workflows/ci.yml
- uses: jdx/mise-action@v2
- run: mise install
- run: node --version
```

### Q: `.node-version`をgitにコミットすべき?

A: Yes。チーム全体で同じバージョンを使うためにコミット推奨。

```bash
git add .node-version
git commit -m "Add Node.js version specification"
```

### Q: プロジェクトごとに違うバージョンを使いたい

A: それがmiseの主要な用途です。各プロジェクトで`mise use`を実行:

```bash
cd ~/projects/app-a
mise use node@20

cd ~/projects/app-b
mise use node@22
```

### Q: グローバルバージョンを変更したい

A: `mise use --global`を使用:

```bash
mise use --global node@22
```

またはNix設定ファイルを編集:

```nix
# home/common.nix
xdg.configFile."mise/config.toml".text = ''
  [tools]
  node = "22"  # ここを変更
'';
```

### Q: miseとNixどちらで管理すべき?

A: 以下を参考に:

- **Nix管理**: LSPサーバー、フォーマッター、システムツール
- **mise管理**: ランタイム（Node.js, Python等）

### Q: WSLでも同じ設定で動く?

A: Yes。`home/common.nix`に設定しているため、macOSとWSL両方で同じ動作。

```bash
# WSLで
home-manager switch --flake .#chibimaru@wsl
```

## 参考リンク

- [mise公式サイト](https://mise.jdx.dev/)
- [mise GitHub](https://github.com/jdx/mise)
- [mise Documentation](https://mise.jdx.dev/getting-started.html)
- [direnv](https://direnv.net/)
- [Nix + mise統合例](https://github.com/jdx/mise/discussions)

## 変更履歴

### 2026-01-25: 初期セットアップ

- mise統合（Nix + Home Manager）
- direnv連携
- 対応言語: Node.js, Python, Go, Rust, Ruby
- グローバルデフォルト: Node.js 22, Python 3.12, pnpm latest
- LSPサーバーはNix管理継続
- activation hookによる自動インストール
