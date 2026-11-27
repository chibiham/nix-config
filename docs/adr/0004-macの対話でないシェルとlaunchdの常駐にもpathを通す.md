# Mac の対話でないシェルと launchd の常駐にも PATH を通す

- Status: Accepted
- Date: 2026-11-27

## Context

Mac（Mac mini・macbook。Determinate Nix と Home Manager 単体で、nix-darwin は無い）では、対話の zsh には docker（OrbStack の `~/.orbstack/bin`）・mise 本体（`~/.nix-profile/bin/mise`）・mise の shim（`~/.local/share/mise/shims`。node・pnpm・corepack）が PATH にある。一方、対話でないシェルと launchd の常駐では、どれかが欠けていた。launchd の既定の PATH（`/usr/bin:/bin:/usr/sbin:/sbin`）から起こして確かめた形は次のとおり。

- `zsh -c`: `~/.zshenv`（Home Manager）が `hm-session-vars.sh` を読むので、pnpm（Safe Chain のラッパー）と node（mise の shim）はある。docker と mise が無い。`~/.orbstack/bin` は OrbStack が `~/.zprofile` に足す追記でログインシェルにしか入らない。`~/.nix-profile/bin` は `/etc/zshrc` の `nix-daemon.sh` で対話シェルにしか入らない（`/etc/zshenv` は SSH のときだけ nix を読む）
- `bash -lc`: `/etc/profile` → `/etc/bashrc`（`nix-daemon.sh`）で `~/.nix-profile/bin`（mise）はあるが、`~/.bash_profile` が無いので docker・pnpm・node が無い。`~/.profile` は Home Manager の外の手置きのファイルで、中身は gam の alias の 1 行だけ
- `sh -c`: 何も読まない。親の PATH を受け継ぐだけ
- launchd の常駐: plist が node などの絶対パスを直に起こすので、PATH は launchd の既定のまま。subako のサーバーは push（git の hook は `#!/bin/sh`）とテスト（`/bin/sh -c`）に自分の環境をそのまま渡す。そのため melomemo の pre-push（`mise exec -- pnpm quality:local`、無ければ `corepack pnpm …`）が「mise または corepack が見つかりません」で止まり、執事が手で push し直していた

本人の言葉:

- 2026-11-25「対話shellとagentでの差がちょいちょい出てしまう」
- 2026-11-27「orbstackとmiseを足すの、対話シェル以外でもエージェント利用可能にするってことだよね。そういう方針でnix-configのissueにすべきかなと思った」

## Decision

- PATH の中身は `home.sessionPath`（→ `hm-session-vars.sh`）の 1 か所に置く。macOS では `home/darwin.nix` で、mise の shim より後ろ（`lib.mkAfter`）に `~/.orbstack/bin`・`~/.nix-profile/bin`（`config.home.profileDirectory`）・`/nix/var/nix/profiles/default/bin` を足す。先頭は Safe Chain の shim のままで、対話シェルの並びは変えない
- 経路ごとに次のように読ませる（macOS）
  - `zsh -c`: `~/.zshenv`
  - `zsh -lc`: `~/.zshenv` と `~/.zlogin`（`/etc/zprofile` の path_helper のあとで shim を先頭へ戻す）
  - `bash -lc`: `/etc/profile` → `~/.bash_profile`。Home Manager が macOS だけ `~/.bash_profile` を置く（`home/common.nix`）。中身は、手置きの `~/.profile` を読む → `hm-session-vars.sh` を読む → shim を先頭へ並べ直す（`/etc/profile` の path_helper が並べ直すため）。macOS の `/bin/bash` は 3.2 なので 3.2 で動く書き方だけを使う
  - `sh -c`・`bash -c`: 何も読まず、親の PATH を受け継ぐ。親で並びが正しければ正しい
  - launchd の常駐: plist の `ProgramArguments` を `/bin/zsh -c 'exec "$@"' zsh <プログラム> <引数…>` の形にして `~/.zshenv` を通す。`exec` で zsh はプログラムに置き換わるので、pid と `KeepAlive` の扱いは変わらない。子の `sh -c`・git の hook・エージェントはこの PATH を受け継ぐ
- subako のサーバーの plist（subako の `ops/launchd/server.plist`）の直しは、subako の issue（launchd のサーバーを zsh 経由で起こす）で行う
- macOS では `programs.bash` を有効にしない（対話の bash の設定までは持たない）。`~/.bashrc` は置かない。シークレット（`~/.secrets`）は読ませない

## Alternatives considered

### Home Manager の launchd agent で `launchctl setenv PATH …`

ログインのとき、ほかの常駐より先に走る保証がない。GUI のアプリ全部の PATH が変わる。Safe Chain の shim は世代ごとの store のパスなので、固定の値を書けない。

### `sudo launchctl config user path …`

sudo と再起動が要る。上と同じく固定の値になる。

### 各 plist の `EnvironmentVariables` に PATH を書く

並びを各リポジトリに写すことになり、1 か所にならない。

### `BASH_ENV`

ADR 0003 と同じ理由（先に渡っていないと効かず、渡せば `#!/bin/bash` のスクリプトすべてで読まれる）で採らない。

### macOS でも `programs.bash` を有効にする

対話の bash までは要らない。`~/.bashrc`・`~/.profile` まで Home Manager が持つことになり、手置きの `~/.profile` とぶつかる。

### `~/.zprofile` の OrbStack の追記に任せる

ログインシェルにしか効かない。

## Consequences

- ログインシェルでは `~/.orbstack/bin`・`~/.nix-profile/bin` が PATH に 2 回並ぶ（探す順は変わらない）
- 常駐の PATH は起きたときに決まる。`home.sessionPath` や Safe Chain の shim が変わる switch のあとは、常駐を起こし直す（shim は store の世代ごとのパスで、古い世代は週次の GC で 30 日後に消える）
- zsh を通さずに起こした常駐の下の `sh -c` には、今までどおり PATH が無い
- `hm-session-vars.sh` は一度読まれると `__HM_SESS_VARS_SOURCED` を受け継いだ子では何もしない。zsh 経由の常駐から起こした `bash -lc` では、`/etc/profile` の path_helper がシステムのパスを前へ並べ直し、そのあと shim だけが先頭へ戻る
- `/opt/homebrew/bin` は対話でない `zsh -c` には入らない（今回の範囲外。必要になったら同じ場所に足す）
- macbook も同じ出力になる。Ubuntu 機の出力（drvPath）は変わらない
