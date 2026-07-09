#!/usr/bin/env bash
# macOSシステム設定の適用（冪等）
# sudoが必要な項目を含むため、home-manager switch ではなく明示的に実行する。
# 実行タイミング: bootstrap.sh から、または設定を変えたいとき手動で。
set -uo pipefail

echo "macOS設定を適用中..."

# キーボード設定
defaults write NSGlobalDomain KeyRepeat -int 1                          # リピート速度最速
defaults write NSGlobalDomain InitialKeyRepeat -int 10                  # 遅延最短
defaults write NSGlobalDomain com.apple.keyboard.fnState -bool true     # FnキーをF1-F12として使用
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false      # 長押しアクセント無効

# 音声入力
defaults write com.apple.HIToolbox AppleDictationAutoEnable -bool true  # 音声入力を有効化

# テキスト入力設定
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false  # スマート引用符無効
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false   # スマートダッシュ無効
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool true  # タイプミス修正有効

# 日本語IM設定（可能な範囲で）
defaults write com.apple.inputmethod.Kotoeri JIMPrefLiveConversionKey -bool false  # ライブ変換無効
defaults write com.apple.inputmethod.Kotoeri JIMPrefWindowsModeKey -bool false     # Windows風キー操作無効

# マジックマウス設定（右側で右クリック）
defaults write com.apple.AppleMultitouchMouse MouseButtonMode TwoButton                    # セカンダリクリック有効
defaults write com.apple.driver.AppleBluetoothMultitouch.mouse MouseButtonMode TwoButton   # Bluetooth経由の場合

# Dock設定
defaults write com.apple.dock autohide -bool true
killall Dock 2>/dev/null || true  # 設定反映

# Finder設定
defaults write com.apple.finder FXPreferredViewStyle -string "clmv"           # デフォルトをカラム表示
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true  # ネットワークドライブで.DS_Store無効
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true      # USBドライブで.DS_Store無効
killall Finder 2>/dev/null || true  # 設定反映

# ---- 以下 sudo が必要（対話的にパスワードを求める） ----

# 起動音を無効化
sudo nvram StartupMute=%01 && echo "✓ 起動音を無効化しました"

# リモートログイン（SSH）を有効化
sudo systemsetup -setremotelogin on 2>/dev/null && echo "✓ リモートログイン（SSH）を有効化しました"

# SSHパスワード認証を無効化（鍵認証のみ許可）
SSHD_CONFIG="/etc/ssh/sshd_config"
if ! sudo grep -q "^PasswordAuthentication no" "$SSHD_CONFIG" 2>/dev/null; then
  sudo sed -i.bak 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
  sudo sed -i.bak 's/^#*KbdInteractiveAuthentication.*/KbdInteractiveAuthentication no/' "$SSHD_CONFIG"
  sudo rm -f "$SSHD_CONFIG.bak"
  sudo launchctl stop com.openssh.sshd 2>/dev/null || true
  echo "✓ SSHパスワード認証を無効化しました（鍵認証のみ）"
else
  echo "✓ SSHパスワード認証は無効化済み"
fi

# スリープ設定: AC電源接続時はスリープ無効、ディスプレイは30分でオフ
sudo pmset -c sleep 0 displaysleep 30 && echo "✓ スリープ設定を適用しました"

echo "✓ macOS設定完了（一部設定は再ログインまたは再起動後に反映）"
