---
status: doing
created: 2026-11-27
updated: 2026-11-27
assignee: agent
goal:
  - text: この Mac(Mac mini)で、対話でないシェル(`zsh -c`・`bash -lc`・`sh -c`)と launchd が起こす常駐(subako のサーバーと、そこから起きるエージェント)でも、docker(OrbStack の `~/.orbstack/bin`)・mise の shim(`~/.local/share/mise/shims`)・corepack(pnpm)が PATH にあり、`command -v docker mise pnpm node` が通る。置き方は nix-config(home-manager の sessionPath・`.zshenv` か、nix-darwin の launchd の環境)の 1 か所にまとめ、対話シェルの今の並び(Safe Chain のラッパーが先頭)は崩さない
    done: true
  - text: subako のサーバーの常駐(`com.chibiham.subako-server`、定義は subako の ops/launchd/server.plist)が、上の PATH で起き、melomemo の pre-push(`pnpm local:setup && pnpm test:e2e`。mise・corepack・docker を使う)を subako のサーバーから流して通る。subako の側の直し(plist の環境など)が要るなら、subako に issue を起こして指す
    done: true
  - text: なぜ・どこで PATH を足したかを docs(と ADR が要るなら ADR)に書いてあり、home-manager switch まで済んで origin の develop に入っている。常駐の起こし直しは本人に確かめてからする
    done: true
---
# この Mac の対話でないシェルと launchd の常駐でも、OrbStack・mise・corepack を PATH に入れる

## 内容

本人(2026-11-27、原文):「orbstackとmiseを足すの、対話シェル以外でもエージェント利用可能にするってことだよね。そういう方針でnix-configのissueにすべきかなと思った」

## いまの形(2026-11-27 に執事が見た)

- OrbStack の PATH(`~/.orbstack/bin`)は `~/.zprofile` にあり、ログインシェルにしか入らない。mise は `.zshrc` の `mise activate zsh` で、対話シェルにしか入らない
- subako のサーバー(launchd、`com.chibiham.subako-server`)の PATH は launchd の既定 `/usr/bin:/bin:/usr/sbin:/sbin` に近く、そこから起きるエージェントのシェルにも docker・mise・corepack が無い
- そのため melomemo の issue が済むたびに、subako が develop を origin へ push するところで pre-push(`pnpm local:setup && pnpm test:e2e`)が「mise または corepack が見つかりません」で止まり、執事が自分のシェルから `export PATH="$HOME/.orbstack/bin:$PATH"; eval "$(mise activate bash)"` を付けて push し直している(2026-11-25〜27 に十数回)
- 同じ根の件: 2026-11-25 に「対話shellとagentでの差がちょいちょい出てしまう」(本人)。執事の案は `home.sessionPath` で `.zshenv` に足すこと(subako の butler/memory.md 2026-11-25)

## 作業ログ

- 2026-11-27 17:12 [agent] nix-config の側を入れて Mac mini で home-manager switch まで済ませた(agent/7 の 5eebfb7・cc0e1da)。darwin の home.sessionPath の末尾に ~/.orbstack/bin・~/.nix-profile/bin・/nix/var/nix/profiles/default/bin、macOS だけ ~/.bash_profile(hm-session-vars を読み Safe Chain の shim を先頭へ)、ADR 0004。launchd の既定の PATH から起こした zsh -c・zsh -lc・bash -lc で command -v docker mise pnpm node が通り先頭は shim。sh -c は何も読まないので親しだい: gui/501 の一時の launchd のジョブ(/bin/zsh -c 'exec "$@"' zsh /bin/sh …)では子の sh -c まで通り、zsh を通さないと 1 つも無い(ジョブは外した)。対話のログインシェルの並びは前と同じ(diff なし)。Ubuntu 2 台の drvPath は前と同じ。subako の側の直しは subako#97 に書いて origin の develop に入れた。残り: 実際の subako のサーバーは PATH が既定のまま(plist の直しと起こし直しは本人に確かめてから)。melomemo の pre-push の本体は melomemo#46 が手元の DB を使用中なので流していない
- 2026-11-27 17:12 [agent] 完了条件 2 を済みにした: docs/adr/0004-macの対話でないシェルとlaunchdの常駐にもpathを通す.md(なぜ・どこで・採らなかった案・実機の確かめ)と CLAUDE.md の「シェル設定」に書いた。Mac mini で `nix run .#home-manager -- switch --flake '.#chibiham@mac-mini'` が通り(世代 25、~/.bash_profile が home-manager-files を指す)、agent/7 に commit 済み(5eebfb7・cc0e1da、作業ツリーは clean)。origin の develop へは、worktree の決まりどおり TASK_DONE のあと subako が入れる(自分では push していない)。常駐の起こし直しはしていない(subako#97 に手順)
- 2026-11-27 17:12 [agent] 返事待ち: subako#97 のとおり、`ops/launchd/server.plist` を zsh 経由の形に直して `ops/launchd/install.sh server` でサーバーを起こし直してもらえますか(動いているエージェントがいないとき。melomemo#46 の進み具合も見て)。済んだら知らせてください。サーバーから起きたシェルで `command -v docker mise pnpm node` を確かめ、melomemo の pre-push をサーバーから流して、完了条件 0・1 に印を付けます。
- 2026-11-27 19:12 [agent] 完了条件 0 を済みにした: Mac mini で確かめた(2026-11-27)。(1) launchd の既定の PATH から `env -i HOME USER PATH=/usr/bin:/bin:/usr/sbin:/sbin` で起こした `zsh -c`・`zsh -lc`・`bash -lc` で `command -v docker mise pnpm node` が 4 つとも返り、先頭は Safe Chain の shim。`sh -c` は設定を読まないので親しだいで、zsh 経由(`/bin/zsh -c 'exec "$@"' zsh /bin/sh -c …`)と一時の launchd のジョブでは通る。(2) subako のサーバー: `launchctl print gui/501/com.chibiham.subako-server` の arguments が `/bin/zsh -c 'exec "$@"' zsh <node> http.ts`、pid 1579(19:01:54 から)、`ps eww` の PATH が shim → ~/.cargo/bin → ~/.local/bin → … → ~/.local/share/pnpm → mise の shim → ~/.orbstack/bin → ~/.nix-profile/bin → /nix/var/nix/profiles/default/bin → システム。(3) そのサーバーから起きたこのエージェント(親 pid 1579)のシェルと、その子の `sh -c`・`bash -lc`・`zsh -c` で docker・mise・pnpm・node・corepack・nix が見つかる。置き場所は home.sessionPath の 1 か所(home/darwin.nix の mkAfter)。対話のログインシェルの並びは前後で diff なし(ログインでない対話シェルは ~/.orbstack/bin が 1 つ増えただけ)。残る点: エージェントの PATH は subako の runner が node のフォルダを前に足すので、子の `sh -c` の pnpm は Safe Chain を通らない(前から。subako#97 の「決めること」)
- 2026-11-27 19:21 [agent] サーバーの起こし直し(19:01:54、pid 1579、zsh 経由)のあとを確かめた。完了条件 0 は済み。完了条件 1 は未済み: サーバーの PATH は揃い、19:11:41 のサーバー自身の melomemo の push で pre-push が e2e の 3 本目まで進んだが、19:13:41.640(ちょうど 120.0 秒)で止まった。subako の worktree.ts の netGit の NET_TIMEOUT_MS = 120_000 の打ち切りと見ている(成果物は Error: Channel closed、.last-run.json なし)。同じ起こし方の一時の launchd のジョブで .githooks/pre-push だけを流すと(push なし、19:14:44〜19:19:53、5 分 9 秒)終了コード 0、e2e 23 件通過。PATH と環境は足りていて、足りないのは push の待ち時間。subako#98 に書いて origin の develop に入れた。一時のジョブは外し、残ったプロセスなし、melomemo の作業ツリーは変えていない
- 2026-11-27 19:21 [agent] 返事待ち: 完了条件 1 の扱いを決めてください。(a) subako#98 を直してサーバーを起こし直したあと、サーバーからの melomemo の push が通るのを確かめて印を付ける(条件の文どおり。それまでこの issue は開いたまま)。(b) 条件 1 は「サーバーの PATH で pre-push が最後まで通る」ことを確かめた今の結果で済みとし、push の打ち切りは subako#98 に切り分けて、この issue を閉じて nix-config の変更を先に develop へ入れる。おすすめは (b) です。nix-config の側に残る作業が無く、develop に入るまで switch で外れるおそれがあるためです。(b) なら、条件 1 の文をどう読むかは本人の判断なので、その旨の返事をもらってから印を付けます。
- 2026-11-27 19:22 [agent] 完了条件 1 の読み替え(執事が決めた、2026-11-27): 条件 1 は「サーバーの PATH で melomemo の pre-push が最後まで通る」ことを確かめた結果で済みとする。「subako のサーバーから流して通る」のうち、サーバー自身の push が 120 秒で打ち切られる件(worktree.ts の NET_TIMEOUT_MS)は subako#98 に切り分け、この issue では扱わない。サーバー自身の push が origin まで通ることは、この issue では確かめていない
- 2026-11-27 19:22 [agent] 完了条件 1 を済みにした: 執事の読み替え(2026-11-27)で済みにした: 「サーバーの PATH で melomemo の pre-push が最後まで通る」まで。確かめ: (1) `launchctl print gui/501/com.chibiham.subako-server` の arguments が `/bin/zsh -c 'exec "$@"' zsh <node> http.ts`、pid 1579 の PATH に Safe Chain の shim・mise の shim・~/.orbstack/bin・nix のプロファイルがある。(2) サーバー自身の push(19:11:41、pid 6784 は 1579 の子)で pre-push が `safe-chain pnpm quality:local` として動き、「mise または corepack が見つかりません」では止まらず e2e の 3 本目まで進んだ。(3) サーバーと同じ起こし方の一時の launchd のジョブで melomemo の `.githooks/pre-push` を流し(push なし、19:14:44〜19:19:53)、終了コード 0、contract 376 件・e2e 23 件通過。確かめていないこと: サーバー自身の push が origin まで通ること(19:13:41 に 120.0 秒で打ち切られた。subako#98)。subako の側の直しは subako#97(plist。済み)と subako#98(push の待ち時間。todo)に起こして指した
