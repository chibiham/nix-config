# 定期メンテナンス（更新と脆弱性確認）

月に1回程度、または `update-flake-lock.yml` の自動PRが来たときに行う。
flake update → ビルド/評価 →（vulnix）→ switch → mise upgrade → mise prune → Homebrew の順に上げる。どの段階も途中で止めてよい。

以下、`H` は対象ホスト（`mac-mini` / `macbook` / `ubuntu-server`）。

```bash
cd ~/.config/nix-config
H=mac-mini   # MacBookなら H=macbook（以降の手順は同じ）
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

## 5. mise

```bash
mise outdated               # 設定の範囲（node = "24" など）で新しい版があるか
mise upgrade                # 範囲内の最新を入れ、置き換えた旧版はアンインストールする
mise prune --dry-run        # どの設定からも使われていない版の一覧
mise prune                  # 確認してから実行
```

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
Nixが提供するツール（gh, gnupg, tmux, pinentry-mac など）はbrewで重複して入れない。

- `Brewfile` は mac-mini / macbook 共通。マシン固有のものは `Brewfile.<host>`（例: `Brewfile.macbook`）に書き、
  共通Brewfileの末尾から読み込まれる（無ければ何もしない）
- `HOMEBREW_BUNDLE_FILE`（darwin.nix）と `HOMEBREW_BUNDLE_HOST`（flake.nixの `mkDarwinHome`）がswitchで設定されるので、
  どちらのMacでも引数なしの `brew bundle` で同じ手順になる

```bash
brew update && brew upgrade
brew bundle                 # Brewfile（+ Brewfile.<host>）で足りないものを入れる
brew bundle cleanup         # Brewfileにないもの（ドライラン。--forceは付けない）
```

- アプリを足す・消すときは `Brewfile`（両Mac）か `Brewfile.<host>`（そのMacだけ）を手で編集する。
  `brew bundle dump --force` は今のMacの状態で共通Brewfileを丸ごと上書きし、ホスト別の分け方が崩れるので、
  使ったら `git diff` で他のMac用の行が消えていないか、ホスト固有のものが紛れていないかを確かめる（`--describe` は現行brewでは無効）
- `brew bundle cleanup` に出たものは、Brewfile / `Brewfile.<host>` へ足すか `brew uninstall` するかを決めて差分をなくす
- Homebrewには脆弱性スキャナがないので、`brew outdated` を古さの目安にする

### 別のMacで初めて共通Brewfileを使うとき（例: macbook）

```bash
cd ~/.config/nix-config && git pull
nix run .#home-manager -- switch --flake ".#$USER@macbook"
exec zsh                    # HOMEBREW_BUNDLE_FILE / HOMEBREW_BUNDLE_HOST を読み込む
brew bundle                 # 共通Brewfileで足りないものを入れる
brew bundle cleanup         # macbookにだけあるもの（ドライラン）
```

cleanupに出たものごとに、macbookで使い続けるなら `Brewfile.macbook` に足す（両Macで使うなら `Brewfile`）、
不要なら `brew uninstall` する。cleanupが空になったらコミットする。
