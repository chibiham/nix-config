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
- 2026-10-14 07:25 [agent] 返事待ち: TASK_DONE を受けたが、まだ develop に入れていない: 実装レビューを動かせなかった。環境を確かめる: 実装レビューを始められない: omp が subako の MCP を読めない: /Users/chibiham/.subako/worktrees/nix-config/1 の .mcp.json か ~/.omp/agent/mcp.json に subako を足す
- 2026-10-14 09:04 [agent] 実装レビュー開始。develop..agent/1 の2コミット(4e7320a・f3341f0)、home/common.nix と CLAUDE.md の変更を読み、ラッパーのコマンド解決・72時間制限・非対話シェルへの適用を実行で確認する。コード変更・コミット・switch は行わない。
- 2026-10-14 09:05 [agent] 不具合を再現: 実 pnpm が無い PATH(shims:/usr/bin:/bin)でも command -v pnpm が成功し、bootstrap の導入判定が pnpm 導入を飛ばす。その後 pnpm --version は「Is 'pnpm' installed...」で終了1。home/common.nix:102-127 の無条件shim追加と既存 bootstrap.sh:131 / bootstrap-ubuntu.sh:56 の組合せ。
- 2026-10-14 09:06 [agent] 重大な迂回を再現: 一時package.jsonの npm run probe から npm safe-chain-verify を実行すると /opt/homebrew/bin/npm が選ばれ Unknown command で終了1。子のHTTP(S)_PROXY/npm_config_proxy/NODE_EXTRA_CA_CERTSも未設定。home/common.nix:113-119 がshimディレクトリを子へ渡すPATHから削除するため。Safe Chain 1.5.25 は run/test/start のプロキシを起動せず子のshim再捕捉に依存するので、npm scripts内のnpm installは保護を通らない。試験の一時ファイルは自動削除した。
- 2026-10-14 09:06 [agent] レビュー結論 REVIEW_NG。P1: npm run/test等の子からshimが消え、プロキシも無いためスクリプト内のパッケージ取得が無保護。P2: pnpm本体未導入でもshimの存在でbootstrapが導入を飛ばし、途中失敗後の再実行等で導入できない。いずれもMac上の実shimで再現。通常のzsh -lcはage=72でshimを選択。既報のキャッシュ/venv迂回は再試験せず、コード変更・コミット・switchも行っていない。
- 2026-10-14 09:06 [agent] 実装レビュー(gpt-6.1-sol)が終わった: 修正が必要な不具合を2件確認した。
- 2026-10-14 09:09 [agent] 実装レビューの指摘2件を a60fdd1 で直した。P1: shim が PATH を消さず、safe-chain が呼んだ実体の起動だけを $PPID と _SAFE_CHAIN_SHIM_PID で見分けて素通しする。npm run の子の npm も shim を通り、npm run 経由の safe-chain-test が止まった。再帰はない。P2: bootstrap の pnpm の有無の判定を pnpm --version に変えた。build した shims で確かめ、nix eval の3構成が通った。Mac には再 switch が要る
- 2026-10-14 09:09 [agent] 再レビュー開始。develop..agent/1 の3コミット(6c9ebaa・e997370・a5a8e09)を確認。前回のPATH削除・pnpm導入判定の修正を含め、shimの親PID判定と72時間制限、シェル/子プロセスへの適用を読むだけ・一時検証で確認する。コード変更・コミット・switchは行わない。
- 2026-10-14 09:10 [agent] a5a8e09の実ビルド済みshim(nsallhr...)をNix評価のsessionPathと照合し、一時package.jsonの npm run probe→子もshim・safe-chain-verify成功、pnpm実体なし→needs-installを確認。前回2件の修正はこの条件では有効。別の迂回を確認: bootstrap.sh:130/142・bootstrap-ubuntu.sh:53と同じmise/shims先頭PATHでは npm safe-chain-verify がUnknown commandで終了1となり、保護を通らない。
- 2026-10-14 09:11 [agent] 再レビュー結論 REVIEW_NG。P1: scripts/bootstrap.sh:130-133/142-146、bootstrap-ubuntu.sh:53-58がmise/shimsをSafe Chain shimより前へ置く。Macで同じPATHを構成して mise exec -- npm safe-chain-verify→Unknown command/終了1を確認。初期構築のpnpm/Qwen Code/Pi等のnpm取得がマルウェア判定・72時間制限を通らない。前回2件は改訂shimで解消を確認し、Nix評価3構成も成功。コード変更・コミット・switchなし、一時package.jsonは削除済み。
- 2026-10-14 09:11 [agent] 実装レビュー(gpt-6.1-sol)が終わった: 修正が必要な不具合を1件確認した。前回の2件は改訂shimで解消を確認した。
- 2026-10-14 09:13 [agent] 実装レビューの指摘(bootstrap の npm 導入が Safe Chain をすり抜ける)を c290170 で直した。HM が ~/.local/share/safe-chain-shims に固定パスを置き、bootstrap 2本は PATH を safe-chain shim → mise shims の順にし、shim がなければエラーで止まる。npm 導入は safe_npm(mise exec -- shim の絶対パス)を通す。bash で safe_npm safe-chain-verify が OK、bash -n と nix eval の3構成が通った
- 2026-10-14 09:13 [agent] 再レビュー開始。develop..agent/1 の4コミット(a141c55・4061325・c2d1cea・4ff8d37)を対象に、固定shim経由へ変更したbootstrapとラッパーのコマンド解決を読むだけ・一時検証で確認する。コード変更・コミット・switchは行わない。
- 2026-10-14 09:15 [agent] 不具合を再現: 最新のNix評価が指す実shim(nsallhr...)へ一時symlinkを作りbootstrapと同じPATH先頭に置くと、pnpm --version / npm --version が各8秒でタイムアウト。storeのbin直指定ではpnpm本体不在で即終了127。home/common.nix:118はstore文字列だけを除外し、新設固定パスのsymlinkを実体と誤認して再帰するため、bootstrapのpnpm導入判定で停止する。一時symlinkと起動プロセスは除去済み。
- 2026-10-14 09:16 [agent] 再レビュー結論 REVIEW_NG。P1: home/common.nix:113-122 の再帰防止が固定symlinkを除外せず、bootstrap.sh:130/140・bootstrap-ubuntu.sh:53/65のpnpm --versionが終了しない。実shimで固定パス相当symlink先頭→npm/pnpm --version各8秒タイムアウトを再現。safe_npm safe-chain-verifyとstore直指定のnpm run→子のsafe-chain-verifyは成功（mise shim経由も成功）、Nix評価3構成とbash -nも成功。コード変更・コミット・switchなし。一時ファイル・プロセスは除去済み。
- 2026-10-14 09:16 [agent] 実装レビュー(gpt-6.1-sol)が終わった: 修正が必要な不具合を1件確認した。
- 2026-10-14 09:17 [agent] 実装レビューの指摘(固定パス ~/.local/share/safe-chain-shims 経由でラッパーが自分を呼び続け、bootstrap が止まる)を 30806a9 で直した。実体を探すとき、リンク先と同じ実体(cd -P と -ef)のラッパーも飛ばす。入れ子の深さが32を超えたら exit 126 で止まる。固定パスを先頭にして試し、pnpm がないとき rc=127 ですぐ終わった。pnpm・npm の --version、verify、npm run の子、safe_npm も動き、npm run 経由の safe-chain-test は止まった。bash -n と nix eval の3構成も通った
- 2026-10-14 09:18 [agent] 再レビュー開始。develop..agent/1 の5コミット(db7aa30・b400fd5・2db4f55・3519bb7・3094973)を対象に、symlink除外と再帰深さ上限、bootstrap・子プロセスの保護を読むだけ・一時検証で確認する。コード変更・コミット・switchは行わない。
- 2026-10-14 09:19 [agent] 最新Nix評価の実shim(s9r0ij...)へ一時symlinkを作り、固定パス先頭で npm --version が成功、pnpm本体不在は即127終了を確認。npm runの子のsafe-chain-verifyとbootstrap相当のmise exec経由も成功。前回のsymlink再帰は解消。引き続き世代切替後のPATHを確認する。試験ファイルは除去済み。
- 2026-10-14 09:20 [agent] 実装レビュー(gpt-6.1-sol)が失敗した: 終了コード null
- 2026-10-14 09:20 [agent] 返事待ち: TASK_DONE を受けたが、まだ develop に入れていない: 実装レビューを動かせなかった。環境を確かめる: 終了コード null
- 2026-10-14 09:22 [agent] 再レビュー開始。develop..agent/1 の5コミット(e1c280e・f824bbb・49cf079・75092a8・0d063c6)を対象に、最新shimのsymlink除外・親PID判定とbootstrap、世代切替後のPATHを読むだけ・一時検証で確認する。コード変更・コミット・switchは行わない。
- 2026-10-14 09:24 [agent] 新しい不具合を再現: 最新shim(s9r0ij...)と旧shim(nsallhr...)をPATHにこの順で残し npm --version を実行すると25秒でタイムアウト。最新shimだけなら11.19.1で終了0。home/common.nix:99は自分の世代だけをPATHから除き、:119-126も別世代を実体と誤認するため、switch後に旧PATHを継承した子シェルでshim同士が再帰する。親PID一致の分岐では深さ上限も通らない。固定symlink単独・pnpm実体なし・npm runの子・bootstrap相当mise execは成功。試験プロセスと一時ファイルは除去済み。
- 2026-10-14 09:24 [agent] 再レビュー結論 REVIEW_NG。P1: home/common.nix:98-100,113-138 は旧世代shimをPATHに残し、実体探索で別世代shimを選ぶ。新旧実shimの共存で npm --version が25秒タイムアウト（単独は終了0）、実際のzshのPATH並べ直し式でも旧世代が残ることを確認。旧世代の除去と探索時の全世代除外が必要。前回symlink再帰・pnpm未導入判定・npm runの子・bootstrap相当mise execは今回の単一世代条件で成功。Nix評価3構成、bootstrap2本のbash -n成功。コード変更・コミット・switchなし。既報のキャッシュ/venv迂回と年齢判定は再試験していない。
- 2026-10-14 09:24 [agent] 実装レビュー(gpt-6.1-sol)が終わった: 修正が必要な不具合を1件確認した。
- 2026-10-14 09:24 [agent] 返事待ち: TASK_DONE を受けたが、まだ develop に入れていない: 実装レビューで指摘があった。worktree /Users/chibiham/.subako/worktrees/nix-config/1 で直して commit し、TASK_DONE で返す: 修正が必要な不具合を1件確認した。 ### P1 — 新旧世代のshimがPATHに共存すると再帰し、コマンドが終了しない 対象: `home/common.nix:98-100,113-138` `safeChainPathFirst` は現在の世代だけを重複排除し、継承した旧世代のshimを残す。実体探索も自分と同じshimだけを除外するため、別世代のshimを本物のnpm等と誤認して起動する。親PID一致の分岐から別世代へ進む再帰では、追加された深さ上限も有効に働かない。 **具体的な入力・結果:** - PATHを最新の実shim（`s9r0ij.../bin`）→旧実shim…(自動の差し戻しが上限 3 回に達した)
- 2026-10-14 09:28 [agent] 執事の差し戻し(新旧の世代のラッパーが PATH に並ぶと再帰する)を ea35359 で直した。実体を探すとき、どの世代でもラッパーと分かるもの(名前 *-safe-chain-shims、固定リンク、目印の行、旧世代にもある libexec/safe-chain の呼び出し)を飛ばす。PID が合うか、親が safe-chain 本体なら、本物を直接 exec する。新+旧3世代(wp4ld8/nsall/s9r)を両方の順に並べ、固定リンクも混ぜて試した。npm --version は約1秒で終わり、verify と npm run の子も OK、safe-chain-test は止まり、pnpm がないとき rc=127。旧世代だけが並ぶと今もループする(旧どうしなので直せない)
- 2026-10-14 09:29 [agent] 再レビュー開始。develop..agent/1 の6コミット(f188ce5〜5790939)を対象に、全世代shimの除外・親プロセス判定とbootstrap/子プロセスへの保護を読むだけ・一時検証で確認する。コード変更・コミット・switchは行わない。

## エージェントの結果(2026-10-14 09:06)

実装レビュー(gpt-6.1-sol)

修正が必要な不具合を2件確認した。

1. **P1 — npm scripts 内のインストールが保護を迂回する**  
   `home/common.nix:113-119`  
   ラッパーがshimディレクトリをPATHから削除し、そのPATHを子プロセスにも渡す。[Safe Chain 1.5.25](https://github.com/AikidoSec/safe-chain/blob/1.5.25/packages/safe-chain/src/packagemanager/npm/createPackageManager.js)は `run/test/start` 等ではプロキシを起動せず、子コマンドのshim再捕捉に依存するため、例えば `"setup": "npm install …"` を `npm run setup` で起動するとマルウェア・72時間制限の両方が効かない。  
   **再現:** 一時package.jsonから `npm run probe` → 子のnpmは `/opt/homebrew/bin/npm`。`npm safe-chain-verify` は `Unknown command`、プロキシ環境変数も未設定だった。  
   **修正:** 再帰防止のコマンド解決と、子へ渡すPATHを分離し、scripts内でもshimを残す。

2. **P2 — 未導入のpnpmを導入済みと誤判定し、bootstrapが導入を飛ばす**  
   `home/common.nix:102-127`  
   pnpm本体が無くても同名shimが存在するため、既存の `scripts/bootstrap.sh:131`／`scripts/bootstrap-ubuntu.sh:56` の `command -v pnpm` が成功する。Home Manager反映後、本体導入前に失敗してbootstrapを再実行する場合など、pnpmを導入できない。  
   **再現:** PATHを実shim＋`/usr/bin:/bin`にすると導入判定は成功するが、`pnpm --version` は本体不在のエラーで終了1。  
   **修正:** bootstrapの導入判定をshimの存在ではなく、本体の利用可否で行う。

作業ログに記録済み。コード変更・コミット・switchは行っていない。

REVIEW_NG

## エージェントの結果(2026-10-14 09:11)

実装レビュー(gpt-6.1-sol)

修正が必要な不具合を1件確認した。前回の2件は改訂shimで解消を確認した。

### P1 — bootstrapのパッケージ取得がSafe Chainを迂回する

対象: `scripts/bootstrap.sh:130-133,142-146`、`scripts/bootstrap-ubuntu.sh:53-58`

bootstrapが `~/.local/share/mise/shims` をPATH先頭へ追加し、Safe Chainのshimより優先させる。Bashでは対話zshのラッパー関数も使えないため、初期構築時のnpmによるpnpm・Qwen Code・Pi等の導入が、マルウェア判定と72時間制限を通らない。

**再現:** 改訂Safe Chain shimを含むPATHに、bootstrapと同じmise/shimsの先頭追加を行った。
- `command -v npm` → `~/.local/share/mise/shims/npm`
- `mise exec -- npm safe-chain-verify` → `Unknown command: "safe-chain-verify"`、終了1

**修正方針:** bootstrap内でもSafe Chain shimを優先させ、`mise exec`経由の取得コマンドが保護を通ることを確認する。

検証: 改訂shim経由の`npm run`では子の検証コマンドが成功。pnpm実体なしでは導入必要と判定。Nix評価3構成とbootstrapの構文検査は成功。

作業ログに記録済み。コード変更・コミット・switchなし。

REVIEW_NG

## エージェントの結果(2026-10-14 09:16)

実装レビュー(gpt-6.1-sol)

修正が必要な不具合を1件確認した。

### P1 — 固定パスのshimが再帰し、bootstrapが停止する

対象: `home/common.nix:113-122,278`、`scripts/bootstrap.sh:130,140`、`scripts/bootstrap-ubuntu.sh:53,65`

bootstrapは `~/.local/share/safe-chain-shims` をPATH先頭に置く。このディレクトリはstore内のshimへのsymlinkだが、再帰防止処理はstoreのパス文字列だけを除外する。そのため固定パスのshimを「本物のコマンド」と誤認して再実行し、Safe Chainとの再帰が続く。

**起きる誤り:** bootstrapの `pnpm --version` が終了せず、pnpmの導入判定から先へ進まない。

**再現:** 最新のNix評価が指す実shimへ一時symlinkを作り、bootstrapと同じくPATH先頭へ追加。
- `pnpm --version`／`npm --version` → それぞれ8秒でタイムアウト。
- storeのshimを直接PATH先頭に置いた比較条件 → pnpm本体不在で直ちに終了127。

**修正方針:** 実体の探索時、storeパスだけでなく同じshimを指すsymlinkも除外する。固定パス経由の `pnpm --version` が、本体あり・なしの両条件で終了することを確認する。

検証: `safe_npm safe-chain-verify`、mise経由を含む `npm run` 内の子の検証コマンド、Nix評価3構成、bootstrap2本の構文検査は成功。

作業ログに記録済み。コード変更・コミット・switchなし。一時ファイルと検証プロセスは除去済み。

REVIEW_NG

## エージェントの結果(2026-10-14 09:24)

実装レビュー(gpt-6.1-sol)

修正が必要な不具合を1件確認した。

### P1 — 新旧世代のshimがPATHに共存すると再帰し、コマンドが終了しない

対象: `home/common.nix:98-100,113-138`

`safeChainPathFirst` は現在の世代だけを重複排除し、継承した旧世代のshimを残す。実体探索も自分と同じshimだけを除外するため、別世代のshimを本物のnpm等と誤認して起動する。親PID一致の分岐から別世代へ進む再帰では、追加された深さ上限も有効に働かない。

**具体的な入力・結果:**
- PATHを最新の実shim（`s9r0ij.../bin`）→旧実shim（`nsallhr.../bin`）→実npmの順にして `npm --version` → **25秒でタイムアウト**。
- 旧shimを除いた比較条件 → `11.19.1`、終了0。
- 実装と同じzshのPATH並べ直し式でも、旧世代が残ることを確認した。

**影響:** switch後、旧PATHを持つ親から起動した子シェルでパッケージコマンドが停止し得る。bootstrapの `pnpm --version` にも同じ探索処理が使われる。

**修正方針:** PATH初期化と実体探索の両方で、別世代を含むSafe Chain shimを除外する。

検証: 単一世代での固定symlink、pnpm本体不在時の終了127、`npm run` 内の子の検証コマンド、bootstrap相当のmise経由呼び出しは成功。Nix評価3構成とbootstrap2本の構文検査も成功。

作業ログに記録済み。コード変更・コミット・switchなし。一時ファイル・試験プロセスは除去済み。

REVIEW_NG
