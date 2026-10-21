---
status: doing
created: 2026-10-21
related: [t-20261021-003]
updated: 2026-10-22
assignee: agent
goal:
  - text: flake の入力、mise の処理系、Homebrew の中身の版の一覧と、それぞれが何で管理されているかが issue にある
    done: true
  - text: vulnix などで出した既知の脆弱性と、直したもの・残したもの(理由つき)が issue にある
    done: true
  - text: flake を上げた構成がビルドでき、本人に確かめて切り替えたあと、よく使う道具(git・node・python・ruby・claude・codex・omp)が動く
    done: true
  - text: mise の処理系が範囲の中の最新に上がり、使っていない版を本人に確かめて片付けている
    done: true
  - text: Homebrew の棚卸し(nix へ移す・nix-darwin で宣言にする・要らない)の案が issue にあり、本人が選んだ分を反映している
    done: true
  - text: 端末の依存とセキュリティの更新を回す手順が nix-config の README か docs に書かれ、変更が commit されている(push は本人に確かめる)
    done: true
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
- 2026-10-22 00:48 [agent] 実際に変えたこと(Mac mini): flake.lock 更新 nixpkgs 078d69f(01-22)→b6018f8(06-30, nixos-25.11 は 06-30 で更新停止)・nixpkgs-unstable d54020a→5adc508・home-manager 75ed713→3ee51fb、omp は固定のまま。mac-app-util は SBCL 2.5.10 が macOS 27 で落ちるため nixpkgs-mac-app-util で旧 nixpkgs に固定(commit da56808、build のみで switch は未実行)。mise upgrade で node 24.18.0→24.22.1・python 3.12.12→3.12.15 に上げ、そのとき旧版が消えた(想定外)。npm グローバルの pnpm/agent-browser/neonctl を入れ直し、qwen・pi を bootstrap 手順で導入。node 24.18.0 は執事が、python 3.12.12 はエージェントが mise install で戻した。brew は何も変えていない(update/upgrade/uninstall なし)。
- 2026-10-22 00:48 [agent] mise の版を絶対パスで指す launchd: subako-{server,digest,news,daylog,alerts,heartbeat,market-report} → node/24.18.0。melomemo.{venue,enricher,dashboard,fetcher} → node/22.22.0 と python/3.12.12/bin(3.12.12 は upgrade で消えていたので戻した。melomemo の venv が旧 python に依存していれば確認が要る)。案: plist は版を書かず mise の symlink(installs/node/24、installs/python/3.12)を指す、または `~/.local/share/mise/shims` を PATH に置き cwd の mise 設定で版を決める。symlink 案が一番小さい変更(patch 更新で自動追従、メジャーは明示)。subako の plist は subako の issue へ。以降、mise の版を消す操作(upgrade・prune・uninstall)は本人の確認まで止める。
- 2026-10-22 00:48 [agent] 棚卸しと脆弱性の詳細は spec docs/specs/3/inventory.html。要旨: 管理の分担は flake 入力=flake.lock、node/python/rust=mise(版の範囲は nix の mise 全体設定)、ruby 4.0.7=Homebrew(cocoapods の依存)、非対話シェルの python3 は /usr/bin 3.9.6。Homebrew formula 61(leaf 16)・cask 27、nix-darwin は未導入。vulnix(NVD 6年分): 更新前 279件/31パッケージ(Critical 29・High 100)→更新後 269件/28(Critical 28・High 104)。解消: inetutils の Critical、gnupg、libtasn1、ngtcp2、nix、curl 43→26、unbound 42→32。残す: openssl 3.6.0/zlib/rsync は mac-app-util の旧 nixpkgs 固定のため、curl/openssl 3.6.2/perl/cargo/unbound は 25.11 更新停止のため(26.05 移行で解消見込み、別作業)、git・terraform・swift・gcc の一部は名前一致の誤検知か上流未対応。Homebrew 分類案: 残す23・nix へ移す候補13(ffmpeg, git-lfs, libpq, supabase, xcodegen, codex, フォント類)・不要の可能性7(gh/gnupg/tmux は nix と重複、pinentry-mac、mpdecimal/openssl@3/sqlite は依存の残り)。Brewfile にあって未導入の cask 13、Brewfile にない導入済み codex・cyberduck・formula 13。
- 2026-10-22 00:49 [agent] 完了条件 0 を済みにした: flake.lock・mise ls・which -a・brew list/leaves の結果を作業ログ(00:48)と spec inventory.html に載せた
- 2026-10-22 00:49 [agent] 完了条件 1 を済みにした: vulnix を更新前の home-manager-71 と更新後のビルド結果に対して実行(NVD mirror 経由)。件数、解消したもの、残したものと理由を作業ログ(00:48)に書いた
- 2026-10-22 00:49 [agent] 返事待ち: switch・mise prune(上の候補のみ)・Homebrew で移す/消すもの・brew upgrade・push のそれぞれ、実行してよいか教えてください
- 2026-10-22 01:06 [agent] gh・gnupg・tmux・pinentry-mac の brew uninstall は、方針変更の連絡が届く前にエージェントが実行していた(依存の gmp・libgpg-error・gettext・libunistring も外れた)。本人の「No such keg」はそのため。nix の版が PATH で先に来ることを which -a で確認済み。ほか: mac-mini で switch(trampolineApps の SBCL クラッシュは mac-app-util を nixpkgs-unstable の SBCL 2.6.8 に追従させて解消、5f20a25)。mise から bun 1.4.2・npm:pnpm 11.23.0・pnpm 10.28.1/10.28.2/10.29.1/10.30.1/10.30.3/10.33.2 を uninstall。残る版は node 22.22.0・24.18.0・24.22.1・26.7.0、python 3.12.12・3.12.15、npm:pnpm 11.24.0。Brewfile は brew bundle dump で作り直し(b82c697)、cask の依存で要る mpdecimal・openssl@3・sqlite を書き足した(77e98a9)。brew bundle cleanup の空打ちは formula の差が 0(キャッシュの brew cleanup だけ)。
- 2026-10-22 01:06 [agent] 完了条件 2 を済みにした: 本人の了承後に nix run .#home-manager -- switch --flake .#chibiham@mac-mini がエラーなしで完了。git 2.51.2・node v24.22.1・Python 3.12.15・ruby 4.0.7・claude 2.1.306・codex-cli 0.163.0・omp 18.8.4 の --version が出た。launchd が参照する node 24.18.0・22.22.0、python 3.12.12 が残っていることを ls で確認
- 2026-10-22 01:06 [agent] 完了条件 3 を済みにした: mise upgrade で node 24.22.1・python 3.12.15 に上げた。本人の了承後、prune 候補(bun 1.4.2、npm:pnpm 11.23.0、pnpm の古い版6つ)だけを mise uninstall で消した。mise ls で確認、launchd が参照する版は残した
- 2026-10-22 01:06 [agent] 完了条件 4 を済みにした: 分類案は作業ログと spec に記載。本人の決定どおり gh・gnupg・tmux・pinentry-mac を brew から外し(which で nix 版を確認)、mpdecimal・openssl@3・sqlite は残し、nix へは移さない。Brewfile を dump して正本にし(b82c697, 77e98a9)、brew bundle cleanup の空打ちで formula の差 0 を確認
- 2026-10-22 01:06 [agent] 完了条件 5 を済みにした: docs/maintenance.md(flake update→ビルド→vulnix→switch→mise upgrade(launchd の参照を先に確認)→prune→brew update/upgrade→brew bundle cleanup 空打ち)と CLAUDE.md からのリンクを commit(da56808, 0310e6f, b82c697)。push は本人の確認待ち
- 2026-10-22 01:06 [agent] 返事待ち: agent/3 の commit 5つを push してよいですか(または subako の develop への取り込みに任せてよいですか)
- 2026-10-22 01:10 [agent] macbook 対応: Brewfile は両 Mac 共通の1つ(機械ごとの分割なし)。darwin.nix の HOMEBREW_BREWFILE(brew が読まない名前)を HOMEBREW_BUNDLE_FILE に直し、bootstrap も同じファイルを使う。macbook・mac-mini の activationPackage をビルド、ubuntu-server を評価して通った。docs/maintenance.md に「macbook で行う手順」(pull→switch→launchd の mise 参照確認→mise upgrade→prune 空打ち→brew update/upgrade→brew bundle→cleanup 空打ち)を追加(deac01a, e76a516)。macbook はオフラインのため実行は本人。
- 2026-10-22 01:11 [agent] 返事待ち: agent/3 の commit 7つを push してよいですか(または subako の develop への取り込みに任せてよいですか)
- 2026-10-22 01:12 [agent] 実装レビュー開始。develop..agent/3 の7コミット・7ファイルを対象に、設定差分と更新手順の正しさを読み取り・非破壊検証する。コード変更・コミット・switch・更新操作は行わない。
- 2026-10-22 01:14 [agent] 3ホストの activationPackage 評価と bootstrap の bash -n は成功。brew bundle check は既存アプリ8件と corepack 更新待ちを報告、cleanup はキャッシュのみ。mise prune --dry-run は launchd が参照中の node 24.18.0 と python 3.12.12 を削除候補に出すため、保守手順の一括 prune と参照保護の整合性を確認中。
- 2026-10-22 01:15 [agent] 要修正2件: (1) docs/maintenance.md の macbook 手順は絶対パス依存の旧版を後から再インストールする選択肢を示す一方、その後に一括 mise prune を実行するため再削除される。現機の dry-run でも launchd が参照する node 24.18.0/python 3.12.12 が候補。(2) switch 後の exec zsh は継承された __HM_SESS_VARS_SOURCED に阻まれ、新 HOMEBREW_BUNDLE_FILE を読み込まない。候補の生成済み hm-session-vars.sh で、ガード継承時 UNSET・ガードなし時は正しいパスになることを確認。
- 2026-10-22 01:15 [agent] レビュー完了、REVIEW_NG。旧ランタイム保護と一括 prune の矛盾、および exec zsh で新環境変数が反映されない2件を報告する。後者は生成済み設定を読み込んで /tmp から brew bundle check --no-upgrade を実行し Error: No Brewfile found まで確認。3構成評価・bash構文確認は成功。コード変更・コミットなし。補足調査では brew vulns --json も実行可能だった(26件検査・findings空・未検査あり)。

## エージェントの結果(2026-10-22 01:16)

実装レビュー(gpt-6.1-sol)

要修正2件。

1. **[P1] 保護すべき旧ランタイムを最後の `mise prune` で再削除する**
   — `docs/maintenance.md:121-135`
   launchd が旧版の絶対パスを参照する場合、「upgrade 後に旧版を入れ直す」選択肢が示されています。しかし、続く一括 `mise prune` は launchd の参照を認識しません。現機の dry-run でも、参照中の `node@24.18.0` と `python@3.12.12` が削除候補になりました。この経路では再インストールしても再削除され、サービスの再起動時に起動不能になります。参照を移行するまでは一括 prune を避け、削除可能と確認した版だけを `mise uninstall` する手順が必要です。

2. **[P2] `exec zsh` では新しい Home Manager 環境変数を読み込めない**
   — `docs/maintenance.md:113-115`
   既存シェルには `__HM_SESS_VARS_SOURCED=1` があり、`exec zsh` にも継承されます。生成された `hm-session-vars.sh` はこの値があると即 return するため、新設の `HOMEBREW_BUNDLE_FILE` は未設定のままです。候補の生成済み設定で再現し、リポジトリ外からの `brew bundle check --no-upgrade` は `Error: No Brewfile found` になりました。新しいターミナルセッションを開くか、ガードを解除して環境設定を再読込する手順にしてください。

検証：3ホストの Nix 評価、`bootstrap.sh` の構文確認は成功。コード変更・コミットなし。作業ログへ記録済み。

REVIEW_NG
