---
status: doing
created: 2026-10-13
related: [t-20261013-002]
updated: 2026-10-14
assignee: agent
goal:
  - text: Aikido Safe Chain が nix-config の宣言で入り、npm・pnpm・yarn・bun・pip などの入れ口に挟まる(手で入れた設定に頼らない)
    done: true
  - text: 公開から3日(72時間)たたない版を入れない設定が入っている。設定の書き方と、どの入れ口に効くかを issue に書く
    done: true
  - text: "確かめる: マルウェアとして知られた試しのパッケージ(Safe Chain の文書の確かめ方)が止まること、公開から3日たたない版が入らないこと、ふつうのパッケージは入ること。subako のエージェントの worktree での npm install にも効くこと"
    done: true
  - text: nix の構文の検査が通り、develop に commit している。darwin-rebuild switch は本人が流す(その前で止まって本人に頼む)。chibihamuntu にも当てるかは本人に確かめる
    done: true
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
- 2026-10-14 00:26 [agent] 返事待ち: 上の worktree を指したコマンドで Mac に switch してもらえますか。流したら知らせてください。Mac で確かめたあと、chibihamuntu に当てる手順を出します。
- 2026-10-14 00:40 [agent] Mac に f4e8df6 を switch したあと確かめた: エージェントの Bash(subako worktree)で npm はシェル関数で SAFE_CHAIN=72。worktree で safe-chain-test は「Exiting without installing malicious packages」で止まり、is-number は入った。typescript では「minimum package age で版を除外」の表示が出た。穴: zsh -lc / zsh -c では __HM_SESS_VARS_SOURCED のガードと brew shellenv のせいで shims が PATH に無く、/opt/homebrew/bin/npm が素で通る。8338b86 で .zshenv/.zlogin/.zshrc で shims を毎回 PATH 先頭へ置き直すよう直した(build と ZDOTDIR で確認、nix eval 3構成通過)。再 switch 待ち
- 2026-10-14 00:40 [agent] 返事待ち: もう一度 `nix run ~/.subako/worktrees/nix-config/1#home-manager -- switch --flake ~/.subako/worktrees/nix-config/1#$USER@mac-mini` を流してもらえますか。流したら知らせてください。chibihamuntu には、develop に入って pull したあとに当てる、という流れでよいですか。
- 2026-10-14 00:41 [agent] 返事待ち: 上のどちらかで Mac の switch を流して、結果を知らせてもらえますか。chibihamuntu には、develop に入って pull したあとに当てる流れでよいかも教えてください。
- 2026-10-14 07:23 [agent] 返事待ち: 上のコマンドを流して、`ls -l ~/.zlogin` の結果か、エラーの出力を教えてください。chibihamuntu には、develop に入って pull したあとに当てる流れでよいかも教えてください。
- 2026-10-14 07:24 [agent] 完了条件 0 を済みにした: 本人が 8338b86 を Mac に switch(~/.zlogin・~/.zshenv が 10/14 07:24 に作り直された)。zsh -c と zsh -lc で command -v npm / pip3 が .../safe-chain-shims/bin を指し、zsh -lic では npm・pip3 が関数。SAFE_CHAIN_MINIMUM_PACKAGE_AGE_HOURS=72。包む入れ口: npm/npx/pnpm/pnpx/yarn/bun/bunx/rush/rushx/pip/pip3/uv/uvx/poetry/pipx/pdm(home/common.nix)
- 2026-10-14 07:25 [agent] 完了条件 2 を済みにした: switch 後、subako worktree のエージェントの Bash から zsh -lc で一時ディレクトリに入れて確かめた。npm install safe-chain-test →「Safe-chain: Exiting without installing malicious packages.」。npm cache clean のあと typescript@7.1.0-dev.20261013.1(2026-10-13T08:33Z公開、約14時間)→ notarget と「minimum package age で除外」の表示。npm install is-number@7.0.0 → 入った。注意: npm のキャッシュに入った版は年齢の検査をすり抜けた。venv を activate すると venv の pip が前に来て包まれない
- 2026-10-14 07:25 [agent] 返事待ち: chibihamuntu にも当てますか。当てるならこのまま閉じて、develop に入ったあと chibihamuntu で pull して switch してもらいます。当てないなら、common.nix から Mac 用の設定に移します。
- 2026-10-14 07:25 [agent] 完了条件 3 を済みにした: nix fmt と nix eval の3構成(mac-mini/macbook/ubuntu-server)が通り、mac-mini は nix build まで通った。f4e8df6・8338b86 を agent/1 に commit した。develop へは TASK_DONE のあと subako が早送りで入れる。Mac の switch は本人が流した(10/14 07:24)。chibihamuntu には当てると本人が返事した(develop に入れたあと pull して ubuntu-server を switch)
