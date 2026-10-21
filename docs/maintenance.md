# 定期メンテナンス（更新と脆弱性確認）

月に1回程度、または `update-flake-lock.yml` の自動PRが来たときに行う。
flake update → ビルド/評価 →（vulnix）→ switch → mise upgrade → 不要な版の削除 → Homebrew の順に上げる。どの段階も途中で止めてよい。

以下、`H` は対象ホスト（`mac-mini` / `macbook` / `ubuntu-server`）。

```bash
cd ~/.config/nix-config
H=mac-mini   # macbookは末尾の「macbook で行う手順」
```

## 1. flake inputsの更新

```bash
nix flake update            # すべて上げる
# 一部だけ上げるなら: nix flake update nixpkgs nixpkgs-unstable home-manager
git diff flake.lock
```

- `omp` はflake.nixでコミット固定なので `nix flake update` では動かない。上げるときはflake.nixのrevを書き換える
- mac-app-util（SBCL）は `nixpkgs-unstable` でビルドしている（理由はflake.nixのコメント）
- `nixpkgs` は `nixos-25.11` などのリリースブランチ。サポート終了後は更新が止まるので、新リリースへの移行を別途検討する

## 2. ビルドと評価（switchの前に）

```bash
# 今のホストはビルドまで
nix build --out-link /tmp/hm-new ".#homeConfigurations.\"chibiham@$H\".activationPackage"
# 他のホストは評価だけ（CIでも実行される）
nix eval --raw '.#homeConfigurations."chibiham@macbook".activationPackage.drvPath'
nix eval --raw '.#homeConfigurations."chibiham@ubuntu-server".activationPackage.drvPath'
```

壊れたら、原因のinputだけ戻して他を上げる（`git checkout flake.lock` → `nix flake update <input>...`）。

## 3. 脆弱性確認（vulnix）

```bash
# 今の世代
nix run nixpkgs#vulnix -- -C ~/.local/state/nix/profiles/home-manager
# 新しいビルド
nix run nixpkgs#vulnix -- -C /tmp/hm-new
```

- 新しいビルドで減っていれば更新する価値がある。残ったものはCVSSと内容を見て判断する
- NVDのデータ（直近6年分＋modified）を `~/.cache/vulnix` に取り込む。nvd.nist.govが遅くて
  タイムアウトするときは、`curl -C -` でフィードを手元に落として `python3 -m http.server` で配り、
  `--mirror http://127.0.0.1:8000/` を指定する
- バージョン文字列だけで照合するため、誤検知（別製品の同名CVE、パッチ済み）も多い

## 4. 反映

```bash
nix run .#home-manager -- switch --flake ".#chibiham@$H"
git add flake.lock && git commit -m "chore: flake.lockを更新"
```

switch後に新しいHM環境変数を読むには、新しいターミナルを開く（推奨）か
`unset __HM_SESS_VARS_SOURCED; exec zsh -l` を実行する（単なる `exec zsh` は
`__HM_SESS_VARS_SOURCED=1` を引き継ぐので読み込まれない）。`echo $HOMEBREW_BUNDLE_FILE` で確認する。

## 5. mise

```bash
mise outdated               # 設定の範囲（node = "24" など）で新しい版があるか
mise upgrade                # 範囲内の最新を入れ、置き換えた旧版はアンインストールする
mise prune --dry-run        # どの設定からも使われていない版の一覧（候補）
```

- **plistが `mise/installs/<tool>/<版>` を参照している間は、一括の `mise prune` を実行しない**。
  launchdが絶対パスで使っている版（例: node@24.18.0, python@3.12.12）も「未使用」として候補に出て消される。
  候補から launchd 参照中の版を除き、確認したものだけ個別に消す

  ```bash
  grep -ho 'mise/installs/[^/<"]*/[^/<"]*' ~/Library/LaunchAgents/*.plist | sort -u   # launchdが参照中の版
  mise prune --dry-run                                                               # 候補
  mise uninstall <tool>@<版>                                                         # 参照されていない候補だけ
  ```

  一括の `mise prune` は、plistを版に依存しないパス（`installs/node/24` のsymlinkなど）へ移した後にだけ使う

- `mise upgrade` の前に、launchd などが版の絶対パス（`~/.local/share/mise/installs/node/24.18.0` など）を指していないか確かめる。
  `grep -l mise/installs ~/Library/LaunchAgents/*.plist`。指していれば版を消さない（`mise upgrade` も旧版を消す）か、
  参照を `installs/node/24` のような symlink に直してから上げる
- `mise upgrade` は旧版を消すので、**旧版のNode.jsに `npm install -g` していたコマンドも消える**
  （pnpm、Qwen Code、Pi、agent-browser、neonctlなど）。upgrade前に一覧を控えておき、後で入れ直す

  ```bash
  npm ls -g --depth=0 > /tmp/npm-global-before.txt   # upgrade前
  # upgrade後（Safe Chain経由で入れ直す）
  npm install -g pnpm@latest @qwen-code/qwen-code@latest
  npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
  mise reshim
  ```

- プロジェクトの `.node-version` 等で使っている版も、そのディレクトリの外では「未使用」に見える。
  prune前に一覧を確認する

## 6. Homebrew

方針: Homebrewの中身はHomebrew自身が管理し、`Brewfile` はその一覧として扱う（nix-darwinは使わない）。
`Brewfile` は mac-mini / macbook 共通で、両Macで同じ内容にする（マシン別の分割はしない）。
Nixが提供するツール（gh, gnupg, tmux, pinentry-mac など）はbrewで重複して入れない。
`HOMEBREW_BUNDLE_FILE`（darwin.nix）がswitchで設定されるので、どちらのMacでも引数なしの `brew bundle` がリポジトリのBrewfileを使う。

```bash
brew update && brew upgrade
brew bundle                 # Brewfileにあって入っていないものを入れる
brew bundle cleanup         # Brewfileにないもの（ドライラン。--forceは付けない）
```

- アプリを足す・消すときは、`Brewfile` を手で編集するか、
  入れた後に `brew bundle dump --force` で今の状態を書き出し直す（`--describe` は現行brewでは無効）。
  dumpはそのMacの状態で丸ごと上書きするので、`git diff` で意図しない増減がないか確かめる
  （dumpは `npm "..."` 行も書き出すが、npmのグローバルはmiseのNode.jsとbootstrapで管理するので消す。
  Brewfileに残すと `npm install -g` が直接入れたpnpm等と衝突し `EEXIST` で失敗する）
- `brew bundle cleanup` に出たものは、Brewfileへ足すか `brew uninstall` するかを決めて差分をなくす。
  確認せずに `--force` を付けない
- Homebrewには脆弱性スキャナがないので、`brew outdated` を古さの目安にする

## macbook で行う手順

flake.lockの更新とコミットはmac-miniで済ませ、macbookではpullして反映する。上から順に貼り付けて実行する。

```bash
cd ~/.config/nix-config
git pull

# 4. 反映
nix run .#home-manager -- switch --flake ".#$USER@macbook"
```

新しいHM環境変数（`HOMEBREW_BUNDLE_FILE` など）は、`exec zsh` では読み込まれない
（`__HM_SESS_VARS_SOURCED=1` が引き継がれ、hm-session-vars.sh が読み込みを飛ばすため）。
新しいターミナルを開く（推奨）か、次を実行してから確認する。

```bash
unset __HM_SESS_VARS_SOURCED; exec zsh -l
echo $HOMEBREW_BUNDLE_FILE   # リポジトリのBrewfileを指していること
```

```bash
# 5. mise: upgradeの前に、launchdが版の絶対パスを指していないか確かめる
cd ~/.config/nix-config
grep -l mise/installs ~/Library/LaunchAgents/*.plist
# 何か出たら、upgradeで旧版が消えるので、後でその版を入れ直す（mise install node@<版>）か、
# plistの参照を installs/node/24 のようなsymlinkに直してから進む

npm ls -g --depth=0 > /tmp/npm-global-before.txt   # 入れ直す対象を控える
mise outdated
mise upgrade

# 旧版に入れていたnpmグローバルを入れ直す（Safe Chain経由）
npm install -g pnpm@latest @qwen-code/qwen-code@latest
npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
mise reshim

# 不要な版の削除: plistがmise/installs/<tool>/<版>を参照している間は一括のmise pruneを使わない
grep -ho 'mise/installs/[^/<"]*/[^/<"]*' ~/Library/LaunchAgents/*.plist | sort -u   # launchdが参照中の版
mise prune --dry-run        # 候補。上で出た版を除いたものだけ消す
# mise uninstall <tool>@<版>   # 確認した候補ごとに実行
# （plistを installs/node/24 などのsymlinkへ移し終えた後なら mise prune で一括削除してよい）
```

```bash
# 6. Homebrew
brew update && brew upgrade
brew bundle                 # Brewfileにあって入っていないものを入れる
brew bundle cleanup         # Brewfileにないもの（ドライラン）
```

`brew bundle cleanup` に出たものごとに、両Macで使うなら `Brewfile` に足してコミットし（mac-miniでも `brew bundle` で入る）、
不要なら `brew uninstall` する。確認せずに `brew bundle cleanup --force` を実行しない。
