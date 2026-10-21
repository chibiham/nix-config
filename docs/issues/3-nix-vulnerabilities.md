---
status: doing
created: 2026-10-21
related: [t-20261021-003]
updated: 2026-10-21
goal:
  - text: flake の入力、mise の処理系、Homebrew の中身の版の一覧と、それぞれが何で管理されているかが issue にある
    done: false
  - text: vulnix などで出した既知の脆弱性と、直したもの・残したもの(理由つき)が issue にある
    done: false
  - text: flake を上げた構成がビルドでき、本人に確かめて切り替えたあと、よく使う道具(git・node・python・ruby・claude・codex・omp)が動く
    done: false
  - text: mise の処理系が範囲の中の最新に上がり、使っていない版を本人に確かめて片付けている
    done: false
  - text: Homebrew の棚卸し(nix へ移す・nix-darwin で宣言にする・要らない)の案が issue にあり、本人が選んだ分を反映している
    done: false
  - text: 端末の依存とセキュリティの更新を回す手順が nix-config の README か docs に書かれ、変更が commit されている(push は本人に確かめる)
    done: false
assignee: agent
---
# nix で入れているもの(Python・Ruby ほか)の脆弱性を直す

## 内容

本人(2026-10-21)「.nix-configで定義している関係のもの、python, rubyもろもろも脆弱せいあればあげていきたい。」

執事の解釈:
- flake の入力(nixpkgs ほか)が今どの版かと、入れている言語の処理系(Python・Ruby・Node など。mise で入れているものも含む)の版を一覧にする
- vulnix などで、今の構成に入っているパッケージの既知の脆弱性を出し、重さと影響する範囲を issue に書く
- `nix flake update`(または nixpkgs だけ)で上げ、ビルドして切り替えられることを確かめる。上がらない・壊れるものは理由つきで残す
- 寿命の切れた処理系(例: 古い Python・Ruby の版)が残っていれば、上げるか外すかの案を出す(外すかは本人が決める)
- 切り替え(switch)は手元の作業機に効くので、実行の前に本人に確かめる。push も本人に確かめる

追記(本人 2026-10-21「おお、そうしようか。端末の依存とかセキュリティアップデートはnix-configでできると楽だよね」):
- 今の分担(執事が読んだ): nix は mise 本体と mise の全体設定(node 24・python 3.12・macOS は rust stable)を置くだけで、言語の本体は mise が入れる。Ruby は Homebrew(`/opt/homebrew/bin/ruby`)。Homebrew の 61 個は nix の設定に出てこない
- mise: `mise upgrade` で範囲の中の最新パッチに上げ、`mise prune` で使っていない版(node 22・26、古い pnpm など)を消す。どの版が残るかを issue に書く
- Homebrew: 入っているものを棚卸しし、nix(home-manager のパッケージ)へ移せるもの・nix-darwin の `homebrew` の設定で宣言にするもの・要らないものに分ける案を出す。`brew upgrade` で上げる
- 目指す形: 端末の依存とセキュリティの更新を nix-config の手順ひとつ(例: flake update → switch → mise upgrade → brew の宣言の反映)で回せるようにする。手順は README か docs に書く
- 消す・外す操作(mise prune、brew の uninstall)と切り替えは、実行の前に本人に確かめる
- 本人(2026-10-21)「中身はhomebrew管理でいいに同意。内容の棚卸しだけしてくれるんだよね。」: Homebrew の中身は Homebrew が入れる・上げる。nix に移すのは本人が選んだものだけ。この issue でやるのは棚卸し(何が入っていて、何に使うか・要るか)と、残すものを nix-darwin の `homebrew` の設定に一覧として書く案まで。宣言にするときも `onActivation.cleanup` は "none"(一覧にないものを勝手に消さない)にする

## 作業ログ

- 2026-10-21 23:59 [me] 完了条件の案を有効にした(ゴールのタスクにした)
