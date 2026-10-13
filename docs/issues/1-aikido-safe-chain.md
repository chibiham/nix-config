---
status: doing
created: 2026-10-13
related: [t-20261013-002]
updated: 2026-10-13
assignee: agent
goal:
  - text: Aikido Safe Chain が nix-config の宣言で入り、npm・pnpm・yarn・bun・pip などの入れ口に挟まる(手で入れた設定に頼らない)
    done: false
  - text: 公開から3日(72時間)たたない版を入れない設定が入っている。設定の書き方と、どの入れ口に効くかを issue に書く
    done: true
  - text: "確かめる: マルウェアとして知られた試しのパッケージ(Safe Chain の文書の確かめ方)が止まること、公開から3日たたない版が入らないこと、ふつうのパッケージは入ること。subako のエージェントの worktree での npm install にも効くこと"
    done: false
  - text: nix の構文の検査が通り、develop に commit している。darwin-rebuild switch は本人が流す(その前で止まって本人に頼む)。chibihamuntu にも当てるかは本人に確かめる
    done: false
---
# Aikido Safe Chain を入れ、公開から3日たたないパッケージを入れない

## 内容

本人の言葉(2026-10-13、タスク t-20261013-002):

> aikido safe chainを入れ、安全にライブラリの更新を入れられるようにする
> cool timeは3日を設定してsupply chain riskを低減する

> aikido safe chain 導入タスク作ったので、goalありissueにして

執事の解釈:

- Aikido Safe Chain は、npm・pnpm・yarn・bun・pip などのパッケージの入れ口に挟まり、マルウェアと分かっているパッケージを止める道具。公開されてから一定の時間がたたない版を入れない設定(最小の公開経過時間)がある。その時間を3日(72時間)にする
- 本人の Mac と chibihamuntu の両方の環境は nix-config で宣言している。手で入れるのではなく nix-config に書き、作り直しても同じになるようにする
- エージェントの作業(subako の worktree での npm install など)も同じシェルを通るので、効き目がそちらにも及ぶかを確かめる

## 進め方

- まず Safe Chain の入れ方(nixpkgs にあるか、npm の全体に入れてシェルの別名で挟むか)と、3日の設定の書き方を公式の文書で確かめる
- nix-config に書き、本人の Mac で効くことを確かめる。chibihamuntu にも当てるかは本人に確かめる
- darwin-rebuild switch・home-manager switch は本人が流す(システムを作り直すため)。エージェントは nix の構文の検査と、作り直したあとの確かめの手順までを用意する

## 作業ログ

- 2026-10-13 23:33 [agent] f4e8df6: safe-chain 1.5.25 の公式バイナリを sha256 固定で home/common.nix に入れた。SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=72(sessionVariables とラッパーの既定値)。包む入れ口: npm/npx/pnpm/pnpx/yarn/bun/bunx/rush/rushx/pip/pip3/uv/uvx/poetry/pipx/pdm。非対話シェルには home.sessionPath 先頭のラッパー、対話 zsh には mise activate の後の関数。対象外: python -m pip、絶対パスでの呼び出し、hm-session-vars を読まないプロセス。npm は新しすぎる版をメタデータから消し、PyPI も同様。switch 前の試験: safe-chain-test 拒否、公開54時間の typescript dev 版 notarget(48h なら入る)、is-number 入る、pip3 safe-chain-pi-test 拒否。nix eval 3構成が通った。switch 待ち
- 2026-10-13 23:33 [agent] 完了条件 1 を済みにした: home/common.nix(f4e8df6)で SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=72 を設定した。書き方と効く入れ口は作業ログに書いた。npm install typescript@7.1.0-dev.20261011.1(公開から約54時間)が notarget になり、48h にすると入ることで確かめた
- 2026-10-13 23:34 [agent] 返事待ち: Mac で `home-manager switch` を流してもらえますか(`nix run ~/.config/nix-config#home-manager -- switch --flake ~/.config/nix-config#$USER@mac-mini`。agent/1 の内容が develop に入ったあと、またはこの worktree を指して)。流したら知らせてください。また、chibihamuntu にも当てますか(今は common.nix にあるので、当てないなら Mac だけに移します)。
