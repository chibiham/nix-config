# Ubuntu の bash にも PATH を通す

- Status: Accepted
- Date: 2026-11-11

## Context

Ubuntu 機（chibihamuntu・dekahamuntu）のログインシェルは `/bin/bash` のまま。一方、mise（`mise activate`）と Aikido Safe Chain の shim（npm・npx・pnpm・pnpx などをラッパー経由にする設定）は、Home Manager が作る zsh の設定（`~/.zshrc` など）にしか書いていなかった。`~/.bashrc` と `~/.profile` は Ubuntu 標準のままで Home Manager の外にあり、`hm-session-vars.sh` も読まれない。そのため bash では `which pnpm` / `which node` が空になる。

マシンの上で動くエージェント（Claude Code、Codex）は bash でコマンドを動かす。bash で PATH が通らないと、エージェントが Node.js のツールを使えないか、Safe Chain を通らずに入れてしまう。

## Decision

- Linux だけ `programs.bash.enable` にして、Home Manager が `~/.bashrc`・`~/.profile`・`~/.bash_profile` を持つ（`home/common.nix`。macOS のログインシェルは zsh なので触らない）
- PATH の並びは zsh と同じにする。先頭が Safe Chain の shim で、そのあとに `home.sessionPath`（`~/.local/bin`、pnpm、mise の shim など）
- 経路ごとに次のように読ませる
  - `bash -l`（ssh の対話、`bash -lc`）: `~/.bash_profile` → `~/.profile`（`hm-session-vars.sh`）→ `~/.bashrc`
  - `ssh host 'cmd'`: bash は `~/.bashrc` だけを読み、対話でなければ途中で返る。そのため `~/.bashrc` の対話の判定より前（`bashrcExtra`）でも `hm-session-vars.sh` を読み、shim を先頭に並べ直す
  - 対話のとき（`bash -i`）: zsh と同じく `mise activate bash` を使い、npm などを関数でもラッパーへ向ける。mise はプロンプトごと（`PROMPT_COMMAND`）と cd のたび（`chpwd_functions`）に node などを PATH の先頭へ戻すので、そのあとで shim を先頭に並べ直す
  - `bash -c`（エージェントが動かすコマンド）: bash は設定を何も読まない。親（ログインシェルやエージェント）の PATH をそのまま受け継ぐ。親で並びが正しければ正しい
- Ubuntu 標準の対話の設定（プロンプト、色、補完、履歴）は、Home Manager の `~/.bashrc` から `/etc/skel/.bashrc` を読んで残す。starship・fzf・direnv の bash 統合は、その後に入る

## Alternatives considered

### `~/.profile` や `~/.bash_profile` だけを Home Manager で置く

`~/.bashrc` を触らずに済むが、`ssh host 'cmd'` は `~/.bashrc` しか読まないので PATH が通らない。対話のときの mise も入らない。

### `BASH_ENV`（`~/.bash_env`）で非対話の bash にも読ませる

`BASH_ENV` は環境変数として先に渡っていないと効かず、ssh の非対話コマンドでは誰も設定しない。設定したら、こんどは `#!/bin/bash` のスクリプトすべてで読まれる（bootstrap も含む）。影響が広すぎるので採用しない。

### 既存の `~/.bashrc` に追記する（activation で書き足す）

Ubuntu の設定はそのまま残るが、Home Manager の外のファイルを命令的に書き換えることになり、冪等にしにくく、何が効いているかが読めない。

### ログインシェルを zsh に変える（chsh）

対話は揃うが、エージェントが `bash -lc` を使う経路と、`ssh host 'cmd'` で bash を経る経路は残る。OS 側の変更でもあり、今回はしない。

## Consequences

- 初めてこの設定に上げるときは、既存の `~/.bashrc`・`~/.profile`（Ubuntu 標準）とぶつかるので `home-manager switch -b backup` が要る。元のファイルは `~/.bashrc.backup`・`~/.profile.backup` に残る。`bootstrap-ubuntu.sh` は最初から `-b backup` を付けている
- 元の `~/.bashrc` の末尾にあった Codex のインストーラの追記（`~/.local/bin` を PATH へ）はなくなるが、`home.sessionPath` に同じものがある
- chibihamuntu の Home Manager の出力（drvPath）も変わる。変わるのは `~/.bashrc`・`~/.profile`・`~/.bash_profile` の 3 つだけで、zsh の設定と macOS の出力は変わらない
- bash の対話のプロンプトは starship になる（zsh と同じ）
- シークレット（`~/.secrets/.env*`）を読むのは、これまでどおり zsh だけ
