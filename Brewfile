# ============================================================
# Homebrew Brewfile（Nix併用環境向け）
# ============================================================
#
# 【管理方針】
# - CLIツール: Nix管理（再現性・クロスプラットフォーム）
# - GUIアプリ: Homebrew管理（macOS統合）
# - フォント: Homebrew管理（GUIアプリと同様）
#
# ============================================================

# ------------------------------------------------------------
# tap（外部リポジトリ）
# ------------------------------------------------------------

tap "argon/mas"                # App Store CLI
tap "homebrew/bundle"          # Brewfile管理
tap "homebrew/services"        # サービス管理

# ------------------------------------------------------------
# brew（CLIツール）
# ------------------------------------------------------------

# App Store アプリをコマンドラインで管理
brew "mas"

# ------------------------------------------------------------
# cask（GUIアプリケーション）
# ------------------------------------------------------------

# ===== ブラウザ・通信 =====
cask "google-chrome"
cask "microsoft-teams"
cask "slack"
cask "discord"
cask "zoom"

# ===== 開発ツール =====
cask "visual-studio-code"      # codeコマンド提供
cask "docker-desktop"          # docker, docker-composeコマンド提供
cask "android-studio"
cask "postman"
cask "proxyman"
cask "tableplus"

# ===== AI・生産性 =====
cask "claude"
cask "notion"
cask "obsidian"

# ===== デザイン =====
cask "figma"

# ===== メディア =====
cask "spotify"

# ===== ユーティリティ =====
cask "1password"
cask "alt-tab"                 # Windows風アプリ切り替え
cask "karabiner-elements"      # キーボードカスタマイズ
cask "clipy"                   # クリップボード履歴
cask "google-drive"

# ===== セキュリティ =====
cask "nordvpn"

# ===== ハードウェア設定 =====
cask "logitune"                # Logicool Webカメラ・ヘッドセット設定

# ===== Microsoft Office =====
cask "microsoft-auto-update"
cask "microsoft-excel"
cask "microsoft-powerpoint"

# ------------------------------------------------------------
# フォント
# ------------------------------------------------------------
cask "font-fira-code"
cask "font-fira-code-nerd-font"
cask "font-hack-nerd-font"
cask "font-jetbrains-mono-nerd-font"  # Nix管理と併用

# ------------------------------------------------------------
# App Store アプリ
# ------------------------------------------------------------
mas "Amphetamine", id: 937984704         # スリープ防止
mas "GarageBand", id: 682658836          # 音楽制作
mas "iMovie", id: 408981434              # 動画編集
mas "Keynote", id: 409183694             # プレゼン
mas "Kindle", id: 302584613              # 電子書籍
mas "LINE", id: 539883307                # メッセンジャー
mas "Magnet", id: 441258766              # ウィンドウ配置
mas "Numbers", id: 409203825             # 表計算
mas "Pages", id: 409201541               # ワープロ
mas "Presentify", id: 1507246666         # プレゼン補助
mas "Xcode", id: 497799835               # iOS/Mac開発

# ------------------------------------------------------------
# VS Code 拡張機能（最小限）
# ------------------------------------------------------------
vscode "anthropic.claude-code"
vscode "github.copilot"
vscode "github.copilot-chat"
vscode "bradlc.vscode-tailwindcss"
vscode "esbenp.prettier-vscode"
vscode "dbaeumer.vscode-eslint"
vscode "dsznajder.es7-react-js-snippets"
vscode "formulahendry.auto-rename-tag"
vscode "editorconfig.editorconfig"
vscode "prisma.prisma"
vscode "mhutchie.git-graph"
vscode "github.vscode-pull-request-github"
vscode "ms-vscode-remote.remote-containers"
vscode "ms-vscode-remote.remote-ssh"
vscode "dracula-theme.theme-dracula"
