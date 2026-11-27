---
status: doing
created: 2026-11-27
goal:
  - text: この Mac(Mac mini)で、対話でないシェル(`zsh -c`・`bash -lc`・`sh -c`)と launchd が起こす常駐(subako のサーバーと、そこから起きるエージェント)でも、docker(OrbStack の `~/.orbstack/bin`)・mise の shim(`~/.local/share/mise/shims`)・corepack(pnpm)が PATH にあり、`command -v docker mise pnpm node` が通る。置き方は nix-config(home-manager の sessionPath・`.zshenv` か、nix-darwin の launchd の環境)の 1 か所にまとめ、対話シェルの今の並び(Safe Chain のラッパーが先頭)は崩さない
    done: false
  - text: subako のサーバーの常駐(`com.chibiham.subako-server`、定義は subako の ops/launchd/server.plist)が、上の PATH で起き、melomemo の pre-push(`pnpm local:setup && pnpm test:e2e`。mise・corepack・docker を使う)を subako のサーバーから流して通る。subako の側の直し(plist の環境など)が要るなら、subako に issue を起こして指す
    done: false
  - text: なぜ・どこで PATH を足したかを docs(と ADR が要るなら ADR)に書いてあり、home-manager switch まで済んで origin の develop に入っている。常駐の起こし直しは本人に確かめてからする
    done: false
updated: 2026-11-27
assignee: agent
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
