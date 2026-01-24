# NeoVim セットアップ完全ガイド

最終更新: 2026-01-25

## 概要

Home Manager + Nixを使用した完全宣言的NeoVim環境。macOSとWSLの両方で同じ開発環境を再現可能。

## アーキテクチャ

- **エディタ**: NeoVim 0.11.5
- **設定言語**: Lua
- **プラグイン管理**: lazy.nvim
- **LSPサーバー**: Nix管理（バージョン統一・再現性）
- **設定ファイル**: Home Manager完全管理（`~/.config/nvim/` はNixストアへのシンボリックリンク）

## ディレクトリ構成

```
nix-config/
├── home/
│   ├── common.nix              # NeoVim設定を含む共通設定
│   ├── darwin.nix              # macOS固有設定
│   ├── wsl.nix                 # WSL固有設定
│   └── nvim/                   # NeoVim設定ディレクトリ（Lua）
│       ├── init.lua            # メインエントリーポイント
│       └── lua/
│           └── config/
│               ├── options.lua         # Vim設定
│               ├── keymaps.lua         # キーマップ
│               ├── lazy-bootstrap.lua  # lazy.nvimブートストラップ
│               └── plugins/            # プラグイン定義
│                   ├── colorscheme.lua
│                   ├── lsp.lua
│                   ├── completion.lua
│                   ├── telescope.lua
│                   ├── neo-tree.lua
│                   ├── git.lua
│                   ├── ui.lua
│                   └── alpha.lua
│                   # treesitter.lua は一時的に無効化
```

## インストール済みコンポーネント

### エディタ本体

- **NeoVim**: 0.11.5 (Nix管理)
- **vi/vim/vimdiff**: すべて `nvim` へのエイリアス

### LSPサーバー（Nix管理）

```nix
typescript-language-server  # TypeScript/JavaScript
nil                         # Nix
lua-language-server        # Lua
pyright                    # Python
gopls                      # Go
rust-analyzer              # Rust
vscode-langservers-extracted  # JSON/HTML/CSS/ESLint
yaml-language-server       # YAML
marksman                   # Markdown
```

### フォーマッター（Nix管理）

```nix
stylua                  # Lua
prettier                # JS/TS/JSON/YAML
black                   # Python
gofumpt                 # Go
rustfmt                 # Rust
```

### ビルドツール（Nix管理）

```nix
tree-sitter             # パーサー（将来の利用のため）
gcc                     # コンパイラ
```

### プラグイン（lazy.nvim管理）

#### コアプラグイン
- **nvim-lspconfig** (v1.0.0): LSP設定フレームワーク
- **neodev.nvim**: NeoVim用Lua開発補助

#### 補完
- **nvim-cmp**: 補完エンジン
- **cmp-nvim-lsp**: LSP補完ソース
- **cmp-buffer**: バッファ補完
- **cmp-path**: パス補完
- **LuaSnip**: スニペットエンジン
- **friendly-snippets**: スニペットコレクション

#### UI/UX
- **catppuccin/nvim**: カラースキーム（Mocha）
- **lualine.nvim**: ステータスライン
- **bufferline.nvim**: バッファライン
- **which-key.nvim**: キーバインドヘルプ
- **alpha-nvim**: スタートスクリーン

#### ファイル操作
- **telescope.nvim**: ファジーファインダー
- **telescope-fzf-native.nvim**: fzf拡張
- **neo-tree.nvim**: ファイルツリー

#### Git
- **gitsigns.nvim**: Git差分表示
- **vim-fugitive**: Gitコマンド統合

#### 無効化されたプラグイン
- **nvim-treesitter**: エラーのため一時的に無効化
  - シンタックスハイライトは基本的なVimのものを使用
  - 必要になったら再度有効化可能

## 環境変数

```bash
EDITOR=nvim        # Home Managerが自動設定
VISUAL=nvim        # 同上
```

## 主要なキーマップ

### リーダーキー: `Space`

### ファイル操作
- `<Space>e` - ファイルツリー表示
- `<Space>ff` - ファイル検索（Telescope）
- `<Space>fg` - 文字列検索（Telescope）
- `<Space>fb` - バッファ一覧（Telescope）
- `<Space>fh` - ヘルプ検索（Telescope）
- `<Space>fr` - 最近使ったファイル（Telescope）
- `<Space>w` - 保存
- `<Space>q` - 終了

### LSP
- `gd` - 定義へ移動
- `gr` - 参照表示
- `K` - ホバードキュメント
- `<Space>rn` - リネーム
- `<Space>ca` - コードアクション
- `<Space>f` - フォーマット
- `[d` - 前の診断
- `]d` - 次の診断

### Git
- `]c` - 次の変更
- `[c` - 前の変更
- `<Space>hp` - 変更プレビュー
- `<Space>gs` - Git status

### ウィンドウナビゲーション
- `Ctrl-h/j/k/l` - ウィンドウ間移動（左/下/上/右）
- `Shift-h/l` - バッファ切り替え（前/次）
- `<Space>bd` - バッファ削除

### 編集
- `<` / `>` (ビジュアルモード) - インデント（選択保持）
- `Alt-j/k` - 行を上下に移動
- `Esc` - 検索ハイライト解除
- `p` (ビジュアルモード) - ヤンクせずペースト

### インクリメンタル選択
- `Ctrl-Space` - 選択開始/拡大
- `Backspace` - 選択縮小

## セットアップ手順

### 初回セットアップ

```bash
# 1. Home Manager適用
cd ~/dotfiles/.config/nix-config
nix run home-manager -- switch --flake .#chibimaru@darwin

# 2. シェル再起動
exec zsh

# 3. NeoVim起動（プラグイン自動インストール）
nvim
# `:Lazy` でインストール状況確認
```

### 設定変更後

```bash
# 設定ファイルをgit add（Nixはgit追跡ファイルのみ参照）
git add home/

# Home Manager再適用
nix run home-manager -- switch --flake .#chibimaru@darwin

# NeoVim再起動
nvim
```

## トラブルシューティング

### 実施した解決策

#### 1. 下半分が真っ黒になる問題
**原因**: `extraLuaConfig` が `init.lua` の内容だけを読み込み、`lua/config/` ディレクトリが含まれていなかった

**解決策**:
```nix
# 変更前
extraLuaConfig = builtins.readFile ./nvim/init.lua;

# 変更後
xdg.configFile."nvim" = {
  source = ./nvim;
  recursive = true;
};
```

#### 2. vi/vimエイリアスが効かない問題
**原因**: `~/dotfiles/.zprofile` に古いMacVimへのエイリアスが残っていた

**解決策**: `.zprofile` の以下をコメントアウト
```bash
# alias vi='env LANG=ja_JP.UTF-8 /Applications/MacVim.app/Contents/MacOS/Vim "$@"'
# alias vim='env LANG=ja_JP.UTF-8 /Applications/MacVim.app/Contents/MacOS/Vim "$@"'
```

#### 3. EDITOR環境変数の競合
**原因**: `home.sessionVariables.EDITOR` と `programs.neovim.defaultEditor` が競合

**解決策**: `home.sessionVariables.EDITOR` をコメントアウト（`defaultEditor = true` に一任）

#### 4. nvim-treesitterエラー
**原因**: `nvim-treesitter.configs` モジュールが見つからないエラー

**解決策**: treesitter.luaを一時的に無効化（`.disabled` リネーム）
- 基本的なシンタックスハイライトはVimのものを使用
- LSPは正常動作

#### 5. lspconfigのdeprecation警告
**原因**: NeoVim 0.11でlspconfigの内部実装が変更

**解決策**: nvim-lspconfigを安定版に固定
```lua
"neovim/nvim-lspconfig",
version = "v1.0.0",
```

### 一般的なトラブルシューティング

#### プラグインが読み込まれない
```bash
# プラグインキャッシュをクリア
rm -rf ~/.local/share/nvim/lazy/

# NeoVim再起動
nvim
# `:Lazy sync` を実行
```

#### LSPが動作しない
```bash
# LSPサーバーがPATHに存在するか確認
which typescript-language-server
which nil
which lua-language-server

# NeoVim内でLSP情報確認
# `:LspInfo`
# `:checkhealth lsp`
```

#### Nixの変更が反映されない
```bash
# ファイルがgit追跡されているか確認
git status

# 未追跡の場合は追加
git add home/nvim/

# Home Manager再適用
nix run home-manager -- switch --flake .#chibimaru@darwin
```

## バックアップ

古いVim設定は以下にバックアップ済み：
```
~/vim-backup/.vim
~/vim-backup/vimrc
```

## 今後の改善案

### 短期
- [ ] Treesitterを再度有効化（よりシンプルな設定で）
- [ ] alpha-nvimのカスタマイズ（ヘッダー、ボタン）
- [ ] よく使う言語のLSP設定を最適化

### 中期
- [ ] デバッガー統合（nvim-dap）
- [ ] テストランナー統合
- [ ] コードアクションのカスタマイズ
- [ ] プロジェクト固有設定（.nvim.lua）

### 長期
- [ ] カスタムスニペット追加
- [ ] AIアシスタント統合（Copilot、Codeium等）
- [ ] リモート開発環境対応

## 参考リンク

- [NeoVim公式ドキュメント](https://neovim.io/doc/)
- [lazy.nvim](https://github.com/folke/lazy.nvim)
- [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)

## 変更履歴

- **2026-01-25**: 初期セットアップ完了
  - NeoVim 0.11.5 + lazy.nvim
  - LSPサーバー6言語対応
  - Treesitterは一時無効化
  - 基本プラグイン構成確立
