---
status: doing
created: 2026-10-14
related: ["#1"]
updated: 2026-10-14
assignee: agent
goal:
  - text: mise の precmd / chpwd のフックが Node.js の bin を PATH の先頭に足したあとも、Safe Chain の shim が実体の npm などより先に来る(フックのあとに並べ直す、など)。npm scripts の中の子の npm・npx・pnpm も Safe Chain を通る
    done: true
  - text: テストで、実際の _mise_hook_precmd を呼んだあとに npm run の中から safe-chain-test を入れようとすると止まり、npm --version はすぐ終わることを確かめる。nix の評価が通る
    done: true
  - text: develop に commit している。switch は本人が流す
    done: false
---
# mise のフックのあとに、npm scripts の中で Safe Chain が迂回される

## 内容

#1 のレビューは自動の差し戻しの上限まで往復し、執事が develop に入れた(ce7e66e。新旧の世代の shim が並んでも npm が終わらない直しを含む)。4回目のレビューで残った指摘:

- [P1] `mise activate zsh` が登録する precmd / chpwd のフックが、Node.js の bin を PATH の先頭に足す。#1 の並べ直しはシェルの初期化のときだけなので、次のプロンプトからは実体の npm が shim より先に来る。いちばん外の npm は関数で守られるが、npm scripts の中の子のコマンドには関数が引き継がれず、Safe Chain を通らない(`home/common.nix:400-410`。再現: 実際の `_mise_hook_precmd` を呼んだあと、一時の package.json の `npm run probe`)

## 執事の解釈

- 守りの穴なので、完了条件を置いて次に進める

## 作業ログ

- 2026-10-14 15:50 [agent] 完了条件 0 を済みにした: home/common.nix に _safe_chain_path_first を追加し precmd_functions/chpwd_functions の末尾(mise・direnv のフックより後)に登録。ビルドした .zshrc で順序 _direnv_hook _mise_hook_precmd … _safe_chain_path_first を確認。npm run の子の npm install safe-chain-test が Safe-chain に止められた(dcd8d93)
- 2026-10-14 15:50 [agent] 完了条件 1 を済みにした: nix build で mac-mini の activationPackage を作り HM_GENERATION=… python3 -m unittest -v tests/test_safe_chain_mise_hook.py → 2 tests OK(実際の _mise_hook_precmd 実行後、npm run 内の safe-chain-test を阻止、npm --version 11.16.0 が即終了)。nix eval で mac-mini/macbook/ubuntu-server の drvPath すべて成功
