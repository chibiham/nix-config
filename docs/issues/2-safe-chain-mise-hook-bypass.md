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
    done: true
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
- 2026-10-14 15:50 [agent] 完了条件 2 を済みにした: agent/2 に dcd8d93 を commit(home/common.nix と tests/test_safe_chain_mise_hook.py)。develop へは TASK_DONE 後に subako が早送りで入れる。switch は本人が流す
- 2026-10-14 15:50 [agent] 実装レビュー開始。指定範囲 develop..agent/2 は 7abb46f の1コミット、home/common.nix と tests/test_safe_chain_mise_hook.py の変更。コード・コミットは変更せず、フック順序と npm scripts 内の実挙動を確認する。
- 2026-10-14 15:52 [agent] 指定変更の生成済み .zshrc をビルドし、追加テスト2件が成功。実 mise/direnv フック後の npm run 内 npm install safe-chain-test は Malicious changes detected で停止し、npm --version は11.16.0で即終了。macbook・ubuntu-server のNix評価も成功。続けて実 chpwd と複数プロンプト相当の切替を確認する。
- 2026-10-14 15:52 [agent] レビュー結論: 修正必須の正しさの不具合なし。実対話zshで3回のcdによるchpwdとprecmd列の後もshimがPATH先頭。npm runの子でnpm/npx/pnpmが現世代shimへ解決され、子のnpm safe-chain-verifyもOK。追加テスト2件成功、mac-miniビルド・macbook/ubuntu-server評価成功。コード変更・コミット・switchは未実施。REVIEW_OK。
- 2026-10-14 15:52 [agent] 実装レビュー(gpt-6.1-sol)が終わった: 修正が必要な正しさの不具合は見つかりませんでした。対象は `develop..agent/2` の `7abb46f`。

## エージェントの結果(2026-10-14 15:52)

実装レビュー(gpt-6.1-sol)

修正が必要な正しさの不具合は見つかりませんでした。対象は `develop..agent/2` の `7abb46f`。

確認済み:
- 追加テスト2件成功。実 mise フック後、`npm run` 内の `npm install safe-chain-test` はマルウェア判定で停止。`npm --version` は即終了。
- 対話 zsh の実 `chpwd` と `precmd` 列を繰り返しても、Safe Chain shim が PATH 先頭を維持。
- `npm run` の子で `npm`・`npx`・`pnpm` が shim に解決され、子の `npm safe-chain-verify` も成功。
- mac-mini のビルド、macbook・ubuntu-server の Nix 評価が成功。

作業ログ記録済み。コード変更・コミット・switch は未実施。

REVIEW_OK

## エージェントの結果(2026-10-14 15:52)

直しを入れ、テストは通りました。ただし、そのテストが元の不具合を捕まえられるかは確かめていません(下に書きます)。commit は agent/2 の `dcd8d93` です。push と switch はしていません。

**直したこと**(`home/common.nix`)
- Safe Chain の shim を PATH の先頭へ戻す関数 `_safe_chain_path_first` を足しました。
- この関数を、プロンプトのたびとディレクトリ移動のたびに動くフックの列(`precmd_functions` / `chpwd_functions`)の末尾に置きました。mise と direnv のフックより後に動くので、mise が Node.js の bin を先頭に足しても shim が先頭に戻ります。
- 設定を2回読んでも、関数が2回入ることはありません。#1 で直した「npm が終わらない」点はそのままです。

**確かめたこと**
- 新しいテスト `tests/test_safe_chain_mise_hook.py`: switch はせず mac-mini の設定をビルドし、その設定で実際の `_mise_hook_precmd` を呼んだあとに試しました。
  - `npm run` の中の `npm install safe-chain-test` は Safe-chain に止められました。
  - `npm --version` はすぐ 11.16.0 を返しました。
  - 2件とも通りました。
- mac-mini・macbook・ubuntu-server の3つとも nix の評価が通りました。

**残る点:** `/tmp` で実際の `_mise_hook_precmd` を呼んでも、直す前の状態で shim が先頭のままでした。直す前のコードでこのテストが落ちることは試していません。なので、このテストは直したあとが動くことは示しますが、元の不具合を確実に捕まえられるかは未確認です。必要なら、Node.js の版を指定した一時ディレクトリで、直す前の commit に対して落ちることを確かめる次の作業を足せます。

**お願い:** develop に入ったら、switch をお願いします。
