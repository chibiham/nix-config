---
status: doing
created: 2026-10-14
goal:
  - { text: "mise の precmd / chpwd のフックが Node.js の bin を PATH の先頭に足したあとも、Safe Chain の shim が実体の npm などより先に来る(フックのあとに並べ直す、など)。npm scripts の中の子の npm・npx・pnpm も Safe Chain を通る", done: false }
  - { text: "テストで、実際の _mise_hook_precmd を呼んだあとに npm run の中から safe-chain-test を入れようとすると止まり、npm --version はすぐ終わることを確かめる。nix の評価が通る", done: false }
  - { text: "develop に commit している。switch は本人が流す", done: false }
related: ["#1"]
updated: 2026-10-14
assignee: agent
---
# mise のフックのあとに、npm scripts の中で Safe Chain が迂回される

## 内容

#1 のレビューは自動の差し戻しの上限まで往復し、執事が develop に入れた(ce7e66e。新旧の世代の shim が並んでも npm が終わらない直しを含む)。4回目のレビューで残った指摘:

- [P1] `mise activate zsh` が登録する precmd / chpwd のフックが、Node.js の bin を PATH の先頭に足す。#1 の並べ直しはシェルの初期化のときだけなので、次のプロンプトからは実体の npm が shim より先に来る。いちばん外の npm は関数で守られるが、npm scripts の中の子のコマンドには関数が引き継がれず、Safe Chain を通らない(`home/common.nix:400-410`。再現: 実際の `_mise_hook_precmd` を呼んだあと、一時の package.json の `npm run probe`)

## 執事の解釈

- 守りの穴なので、完了条件を置いて次に進める
