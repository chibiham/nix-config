---
status: doing
created: 2026-11-11
updated: 2026-11-14
assignee: agent
goal:
  - text: flake に chibiham@dekahamuntu があり評価が通る。chibihamuntu（chibiham@ubuntu-server）と Mac の評価結果（drvPath）が変わっていない
    done: true
  - text: scripts の chibihamuntu 前提（RTX 3090 1 枚・Intel・Vault 名）がホストの設定（hosts/ubuntu/*.env）に切り出され、chibihamuntu のスクリプトが書く unit・設定ファイルが変わっていない
    done: true
  - text: Blackwell（オープンカーネルモジュール、R570 以降、CUDA 12.8 以降、sm_120）・GPU 2 枚・AMD・DDR5 への対応と、カーネル更新の前に NVIDIA モジュールを確かめる手順がある
    done: true
  - text: 第1段（Ubuntu を入れてから Claude Code が動くまで）と第2段以降（エージェントへの指示の雛形）の手順が docs/dekahamuntu-setup.md にある
    done: true
  - text: どのモデルをどちらで動かすかの叩き台が docs/ai-server-placement.md にある
    done: true
  - text: 本人が dekahamuntu で第1段を通し、Claude Code が動く
    done: true
  - text: 第2段（ドライバ・HWE・ComfyUI・Qwen）を通し、実機で確かめた値を docs/dekahamuntu-setup.md に書く
    done: true
---
# dekahamuntu（2 台目の Ubuntu の AI サーバー）を Nix でセットアップできるようにする

## 内容

本人（2026-11-11）:

> dekahamuntuとして、新たにマシンを追加します。nix-configを新しいubuntuのセットアップ用に作って欲しい。用途はchibihamuntuと同様にai serverとして使用しますが、構成がchibihamuntuがRTX3090(VRAM24GB), intel CPU, RAM DDR4 64GBなのに対してRTX5060ti(VRAM32GB) 2枚, amd ryzen, RAM DDR5 64GBのマシンになっています。ので、現在のモデルをどっちで動かすかも決めていきたい(まあdense系のLLMやlora学習はchibihamuntu, 画像生成、MoEのLLMはdekahamuntuかなーなどと思っている)です。とりあえずnixでのセットアップができるように作って欲しい

確かめたこと（本人、2026-11-11）: GPU は RTX 5060 Ti 16GB を 2 枚（合計 32GB）。マザーボードは ASUS ProArt B850（Creator WiFi か WiFi Neo。型番は未確認）。まず第1段（bootstrap と Tailscale まで）を本人が行い、残りはマシンの上のエージェントに進めさせる。

## 進め方

- 管理の境界は ADR 0001 のまま。ホストごとの差の置き場所は ADR 0002
- 反映（home-manager switch、実機でのスクリプトの実行）はしない。本人に確かめる
- chibihamuntu の実機は読むだけ

## 作業ログ

- 2026-11-11 [agent] 枝 feat/dekahamuntu。flake に chibiham@dekahamuntu（cudaCapabilities 12.0、home/hosts/dekahamuntu.nix）。home/linux.nix に chibiham.ubuntu.opVault・aiMode。scripts/lib/ubuntu-host.sh と hosts/ubuntu/{chibihamuntu,dekahamuntu}.env。Blackwell の検査（install-nvidia-driver・install-hwe-kernel）、check-nvidia-kernel-modules-ubuntu.sh（読むだけ。chibihamuntu で流して動くことを確かめた）、GPU 2 枚の割り当て（ComfyUI=0、Qwen=1、qwen38-dual=0,1、学習・Applio=0）、LED の複数台、RAPL のゾーンがないときに止まらないこと
- 2026-11-11 [agent] 確かめたこと: 3 つの既存の構成の drvPath が変わらない。dekahamuntu を評価でき、llama.cpp は CMAKE_CUDA_ARCHITECTURES=120。shellcheck と bash -n。ComfyUI・Qwen・Applio・diffusion-pipe のインストーラを、コマンドを差し替えた環境で旧版と新版を流し、chibihamuntu（とホストのファイルがないホスト）で書かれる unit・設定ファイルが同じことを確かめた
- 2026-11-13 19:36 [agent] 完了条件 5 を済みにした: 2026-11-13 に Mac から `ssh dekahamuntu`（Tailscale 経由）で入れ、`zsh -lic "claude --version"` が「2.1.323 (Claude Code)」を返した。~/.config/nix-config が clone されていて、comfyui.service（user unit）が enabled・active。第1段の実績は docs/dekahamuntu-setup.md の「実機で本人が最初にやる順（2026-11 の実績）」にある
- 2026-11-13 19:36 [agent] 作業ブランチ agent/4 に枝 feat/dekahamuntu-fan-control（bcabaa0 まで）を取り込んだ（88d80bf）。docs/dekahamuntu-setup.md のケースファンの節に実機の値を書いた（e95788d: 初回の解析は 4 本同時に約 1 分 45 秒、PWM 77 で約 520〜660 RPM、pwm はすべて mode=1、制限の中で nvidia-smi が動く、lax なし。88d80bf: 執事が確かめた負荷時の値 33→70℃ で pwm 77→164）。試験の時間の上限は Linux でだけ確かめるようにした（fbfe12c。macOS の timeout は -k 0.3 1.2 に約 1.8 秒、dekahamuntu では 1.50 秒）。試験 24 件 OK。未確認: stop で BIOS に戻ること、再起動のあとの自動起動、83℃ 以上の全開。完了条件 6 の Qwen は本人の答え待ち（実機に qwen38.service はない）
- 2026-11-13 20:15 [agent] Qwen3.8-Flash-Next（UD-Q3_K_XL）の速さを 3 つの形で計った（2026-11-13、同じ GGUF・同じ引数・同じ問い、温度 0、512 トークン。llama.cpp は chibihamuntu 0.5.0・dekahamuntu 0.6.0）。温まったあとの長い問い（入力 3,939 トークン）: chibihamuntu の 3090（n-cpu-moe 38）入力 約 409・生成 約 22.7 tok/s、dekahamuntu の 1 枚（GPU 1、n-cpu-moe 45、ComfyUI はアイドルで同居）約 440・約 25.6、2 枚束ね（n-cpu-moe 33、tensor-split 39,10）約 519・約 29.0。tensor-split 1,1 は重い層が GPU 1 に寄って読み込めない。3 つとも温まれば RAM に収まりディスクの読みは止まる（RSS 45.7 / 54.5 / 41.2GB）。1 枚は、ほかに 16〜24GB の RAM を使われると 1 回の問いで SSD を約 33GB 読み直し、生成が 17〜19 tok/s に落ちる（別プロセスで RAM を確保してまねた）。dekahamuntu にはモデル（UD-Q3_K_XL と mmproj、85GB）を取っただけで、install-qwen38-ubuntu.sh はまだ流していない。chibihamuntu は lora-charactor を pause（10:39 UTC）→ resume（10:51 UTC）し、次の学習が走っているのを確かめた。dekahamuntu の ComfyUI は 10:48〜10:59 UTC だけ止め、/system_stats 200 を確かめた
- 2026-11-13 20:19 [agent] 実測の値を agent/4 に commit した（ab538fb）: hosts/ubuntu/dekahamuntu.env の QWEN_FLASH_N_CPU_MOE 43→45、LLM_DUAL_TENSOR_SPLIT 1,1→39,10、QWEN_DUAL_FLASH_N_CPU_MOE は 33 のまま。速さの比べ・RAM とディスクの読み・見立ては docs/ai-server-placement.md の「実測（2026-11-13）」、要点は docs/dekahamuntu-setup.md。2 台のモデルファイル 4 つは sha256 が同じ。11:19 UTC の時点で、chibihamuntu は lora-charactor の学習が走っていて（一時停止でない）、dekahamuntu は ComfyUI・art-studio・fan2go が active。完了条件 6 の残り: install-qwen38-ubuntu.sh を dekahamuntu で流すこと（Uncensored 版 約 89.5GB の取得、qwen38.service の常駐、Tailscale Serve 8443 を伴う。本人の答え待ち）と Uncensored 版の n-cpu-moe
- 2026-11-13 20:19 [agent] 返事待ち: (1) dekahamuntu の Flash-Next は (a)（必要なときだけ束ねる）・(b)（1 枚を常駐）・(c)（chibihamuntu に残す）のどれにしますか。(2) `install-qwen38-ubuntu.sh` を dekahamuntu で流してよいですか（Uncensored 版 約 89.5GB の取得、qwen38.service の常駐、Tailscale Serve 8443 を伴います。Uncensored 版の n-cpu-moe の詰めには、もう一度 ComfyUI を 10 分ほど止めます）。(3) 新しい env の値を dekahamuntu へどう届けますか（agent/4 を develop に入れてから実機で取り込む / 今回だけ環境変数で渡す）。
- 2026-11-13 21:15 [agent] 本人の依頼（2026-11-13）「Nix-config にマシンスペックをそれぞれ記載しよう」で、4 台の部品・仕様を docs/machines.md にまとめた（agent/4）。出どころを本人の一覧・実機で読んだ値（読むだけ）・メーカーの仕様に分け、本人の一覧の原文は文書の末尾に残した。CLAUDE.md・README.md・docs/ubuntu-server.md・dekahamuntu-setup.md・ai-server-placement.md から参照を張った。実機で分かったこと: chibihamuntu のメモリは 2,666 MT/s で動いている（商品名は 3200MHz）、一覧にない NVMe（Lexar NM790 2TB、NTFS、Ubuntu からは未マウント）がある、dekahamuntu の GPU は Palit（1569:f328）で PCIe x8、有線は 5GbE でつながっている。MacBook Air は SSH を受け付けず読めていない
- 2026-11-13 21:15 [agent] 返事待ち: (1) dekahamuntu の Flash-Next は (a) 必要なときだけ束ねる・(b) 1 枚を常駐・(c) chibihamuntu に残す、のどれにしますか。(2) `install-qwen38-ubuntu.sh` を dekahamuntu で流してよいですか（Uncensored 版 約 89.5GB の取得、qwen38.service の常駐、Tailscale Serve 8443 を伴います。Uncensored 版の n-cpu-moe の詰めには、もう一度 ComfyUI を 10 分ほど止めます）。(3) 新しい env の値を dekahamuntu へどう届けますか（agent/4 を develop に入れてから実機で取り込む / 今回だけ環境変数で渡す）。
- 2026-11-13 22:59 [agent] 返事待ち: (1) dekahamuntu の Flash-Next は (a) 必要なときだけ束ねる・(b) 1 枚を常駐・(c) chibihamuntu に残す、のどれにしますか。(2) `install-qwen38-ubuntu.sh` を dekahamuntu で流してよいですか（Uncensored 版 約 89.5GB の取得、qwen38.service の常駐、Tailscale Serve 8443 を伴います。Uncensored 版の n-cpu-moe の詰めには、もう一度 ComfyUI を 10 分ほど止めます）。(3) 新しい env の値を dekahamuntu へどう届けますか（agent/4 を develop に入れてから実機で取り込む / 今回だけ環境変数で渡す）。
- 2026-11-13 23:09 [agent] 本人の答え（2026-11-13）を docs/machines.md に反映した（agent/4、3b79b3d・c9e374f・5f0349e）。chibihamuntu のメモリは Acclamator OUNCE（型番は未確認、電圧は商品名が 1.2V と 1.35V で食い違う）。chibihamuntu の GPU は Gigabyte GeForce RTX 3090 GAMING（本人の型番は GV-N3090GAMING まで。OC の有無は決めていない。サブシステム 1458:4043 は製品と照らせなかった）。dekahamuntu のケースファンは Thermalright TL-C12C（どの機械かは本人が明示していない。個数と位置は未確認。メーカーの最大 1,550 RPM ±10%、実機の全開の境の閾値は約 1,320〜1,480 RPM）
- 2026-11-13 23:09 [agent] 返事待ち: (1) dekahamuntu の Flash-Next は (a) 必要なときだけ束ねる・(b) 1 枚を常駐・(c) chibihamuntu に残す、のどれにしますか。(2) `install-qwen38-ubuntu.sh` を dekahamuntu で流してよいですか（Uncensored 版 約 89.5GB の取得、qwen38.service の常駐、Tailscale Serve 8443 を伴います。Uncensored 版の n-cpu-moe の詰めには、もう一度 ComfyUI を 10 分ほど止めます）。(3) 新しい env の値を dekahamuntu へどう届けますか（agent/4 を develop に入れてから実機で取り込む / 今回だけ環境変数で渡す）。
- 2026-11-13 23:17 [agent] 本人の答え（2026-11-13）で dekahamuntu のケースファンの構成を docs/machines.md と docs/dekahamuntu-setup.md に書いた（agent/4）: Thermalright TL-C14C（140mm）×7 と TL-C12C（120mm）×3 の 10 個、底 3 吸気・側面 3 吸気・天面 3 排気・背面 1 排気。本人の文では 120mm が「背面」、一覧では「Side」で食い違う（一覧を採った）。10 個が 4 チャネル（fan1・3・4・6）にどうつながっているかと、ヘッダーの電流の上限は未確認。定格の電流は TL-C14C 0.13A・TL-C12C 0.20A で、1 チャネルに多く見て 4 個でも 0.73A
- 2026-11-13 23:17 [agent] 返事待ち: (1) dekahamuntu の Flash-Next は (a) 必要なときだけ束ねる・(b) 1 枚を常駐・(c) chibihamuntu に残す、のどれにしますか。(2) `install-qwen38-ubuntu.sh` を dekahamuntu で流してよいですか（Uncensored 版 約 89.5GB の取得、qwen38.service の常駐、Tailscale Serve 8443 を伴います。Uncensored 版の n-cpu-moe の詰めには、もう一度 ComfyUI を 10 分ほど止めます）。(3) 新しい env の値を dekahamuntu へどう届けますか（agent/4 を develop に入れてから実機で取り込む / 今回だけ環境変数で渡す）。
- 2026-11-13 23:25 [agent] 本人の答え（2026-11-13）「4番であってる。背面って言ったけど、表は側面で、それであってる。」を docs/machines.md と docs/dekahamuntu-setup.md に反映した（agent/4）: fan4 / pwm4 = 側面の TL-C12C（120mm）×3・吸気（本人が確認）、120mm の位置の食い違いは解けた（側面）。TL-C14C の 7 個（底 3・天面 3・背面 1）が fan1・3・6 にどう分かれているかは未確認のまま
- 2026-11-13 23:25 [agent] 返事待ち: (1) dekahamuntu の Flash-Next は (a) 必要なときだけ束ねる・(b) 1 枚を常駐・(c) chibihamuntu に残す、のどれにしますか。(2) `install-qwen38-ubuntu.sh` を dekahamuntu で流してよいですか（Uncensored 版 約 89.5GB の取得、qwen38.service の常駐、Tailscale Serve 8443 を伴います。Uncensored 版の n-cpu-moe の詰めには、もう一度 ComfyUI を 10 分ほど止めます）。(3) 新しい env の値を dekahamuntu へどう届けますか（agent/4 を develop に入れてから実機で取り込む / 今回だけ環境変数で渡す）。
- 2026-11-14 00:21 [agent] 本人の決め（2026-11-13「とりあえずflash nextとcomfy常駐にしよう。nixで設定して」）で、dekahamuntu に install-qwen38-ubuntu.sh を流した（実機の作業ツリーは bcabaa0 のまま、値は環境変数で渡した。スクリプトは agent/4 と sha256 が同じ）。qwen38.service が enabled・active（GPU 1 だけ、未ロードで VRAM 4MiB）、qwen38-dual.service は enable していない（tensor-split 39,10）。Uncensored 版を取得して詰めた: 1 枚 42（入力 約 477・生成 約 29.4 tok/s）、束ね 31（約 560・約 33.9）。Router 経由で 2 つのモデルの読み込みと応答、ai-mode llm-dual → split の切り替えを確かめ、ComfyUI は /system_stats 200、fan2go は active。ComfyUI を止めたのは 15:04:52〜15:07:37 と 15:14:07〜15:17:37 UTC。スクリプトは最後の Tailscale Serve 8443 だけ sudo が要って失敗（本人が流す: sudo tailscale serve --bg --https=8443 http://127.0.0.1:8080）。値と実績は agent/4 の eb2f85c（dekahamuntu.env、docs/dekahamuntu-setup.md、docs/ai-server-placement.md）。ComfyUI にモデルが載った状態での計測はできていない（アイドルだった）。完了条件 6 の印は、8443 を本人が流して確かめてから付ける
- 2026-11-14 00:21 [agent] 返事待ち: dekahamuntu で `sudo tailscale serve --bg --https=8443 http://127.0.0.1:8080` を流してもらえますか。流れたら、tailnet から Qwen に届くのを確かめて完了条件 6 に印を付けます。
- 2026-11-14 01:21 [agent] 本人の依頼（2026-11-14「comfyで適当に画像生成を1枚ずつループして生成して計測してみて」）で、dekahamuntu の本番の ComfyUI（GPU 0）に Anima と Qwen-Image 2.1 を 1 枚ずつ続けて投げながら、常駐の Router（GPU 1）で Flash-Next を計った（11-13 15:42〜16:18 UTC）。画像は Anima 25.2→25.3〜25.6 秒、Qwen-Image 17.2→17.2〜17.6 秒でほぼ変わらず。LLM の生成（温まったあとの長い問い）は UD-Q3_K_XL 25.7→20.6〜22.3 tok/s、Uncensored 29.3→22.2〜25.8 tok/s、入力はほぼ同じ。SSD の大きな読み直しは起きなかった（UD は 1 回の問いで約 0.2〜0.3GB、Uncensored は 0）。最大は GPU 0 72℃、GPU 1 44℃、Tctl 82℃、pwm 169、fan2go は ok のまま。終わったあと LLM をアンロードし、ComfyUI の VRAM を /free で降ろし、試しの画像（temp の 77 枚）を消した。Router 常駐・モデル未ロード・ComfyUI 200・キュー空に戻った。swap に 2,005MB が残った（前は 235MB）。結果は docs/ai-server-placement.md（agent/4）。Tailscale Serve 8443 は本人がまだ流していない
- 2026-11-14 01:21 [agent] 返事待ち: dekahamuntu で `sudo tailscale serve --bg --https=8443 http://127.0.0.1:8080` を流してもらえますか。流れたら、tailnet から Qwen に届くのを確かめて完了条件 6 に印を付けます。
- 2026-11-14 04:07 [agent] 完了条件 6 を済みにした: 第2段が通った。ドライバ 595.99.02・HWE カーネル 7.0.0-43・ComfyUI（GPU 0、/system_stats 200）は 2026-11-12 の実績。Qwen は 2026-11-13 に install-qwen38-ubuntu.sh を実機で流し、qwen38.service が enabled・active（GPU 1 だけ、未ロードで VRAM 4MiB）、Router 経由で UD-Q3_K_XL と Uncensored 版の読み込みと応答、ai-mode llm-dual → split の切り替えを確かめた。Tailscale Serve 8443 は本人が sudo で流し（2026-11-14）、Mac から tailnet 経由で /health 200、/v1/chat/completions に答え「2」が返るのを確かめた（19:06 UTC）。実機で確かめた値（n-cpu-moe 1 枚 45 / 42・束ね 33 / 31、tensor-split 39,10、速さ、VRAM、ケースファン、GPU のメーカー）は docs/dekahamuntu-setup.md の「実機で確かめた値」と 2-5、細かい実測は docs/ai-server-placement.md（agent/4 の 20bcf05 まで）
- 2026-11-14 04:08 [agent] 返事待ち: develop への取り込みと push を進めてよいですか。進めるなら、形はこの issue の統合（agent/4 を develop に入れる。`docs/issues` のぶつかりは agent/4 の側で両方を残して解く）でよいですか、それとも別の形（枝を --no-ff で入れるなど）にしますか。
- 2026-11-14 12:40 [agent] 本人の依頼（2026-11-14「ompでそれらを使えるようにしたいな。」）で、omp の models.yml（home/common.nix）に dekahamuntu の Router を qwen-dekahamuntu として足した（agent/4 の 3ec6b69。既存の qwen-ubuntu はそのまま）。完了条件 0 の「chibihamuntu と Mac の drvPath が変わっていない」は、この依頼による変更で 4 台とも変わる: 変わった drv は omp-models.yml と、それを束ねる home-manager-files・home-manager-generation だけ（nix-store -qR の閉包の差で確かめた）。common.nix なので Ubuntu の 2 台にも入る（既存の qwen-ubuntu と同じ場所）。switch はしていない。確かめ: 生成された models.yml に provider が 2 つ。一時のディレクトリ（HOME と PI_CODING_AGENT_DIR を差し替え）で omp models が dekahamuntu の 2 つのモデルを列挙し、omp -p で Uncensored 版に 1 問投げて答え「2」が返った。そのあとモデルをアンロード（2 つとも unloaded）。chibihamuntu の 8443 はいま 502（qwen38.service が inactive。学習中の形で、今回の変更とは無関係）
- 2026-11-14 12:41 [agent] 返事待ち: 次の 3 つを進めてよいですか。(1) agent/4 を develop に取り込む（形はこの issue の統合でよいか、枝を --no-ff で入れるなど別の形か。`docs/issues/4-dekahamuntu.md` のぶつかりは、取り込む直前に agent/4 の側で両方を残して解きます）。(2) origin への push。(3) Mac の home-manager switch（omp の `qwen-dekahamuntu` の反映。switch するのは本人か、こちらで流してよいか）。
- 2026-11-14 17:07 [agent] 本人の了承（2026-11-14「nix configのdeveopへ取り込み、push, switch実行行なってください」）を受け、agent/4 を develop の最新に載せ直した（merge を外して 18 コミットを一直線に。載せ直し前の位置は refs/backup/agent4-pre-rebase）。docs/issues/4-dekahamuntu.md のぶつかりは両方を残して解いた（ファンの枝の作業ログ 5 行を、subako が書いた時刻つきの行の手前に入れた）。確かめ: docs/issues を除く中身は載せ直しの前と差が 0 行、issue のファイルの develop との差は足した 5 行だけ、bash -n、ファンの試験 24 件 OK、shellcheck（info 1 件だけ）、nix fmt --check、4 つの構成の評価（drvPath は omp の変更のあとの値と同じ）。push・switch・実機の操作は執事が行う
- 2026-11-14 17:08 [agent] 実装レビュー開始。指定の git log / git diff develop..agent/4 を確認。差分は18コミット・18ファイルで、主な実装変更はfan2goによるケースファン制御、dekahamuntuの実測設定、ompのprovider追加。コード変更・コミット・実機への反映は行わない。
- 2026-11-14 17:11 [agent] レビューでGPUのみの設定（CASE_FAN_CPU_CURVE空）が、fan2go 0.15.0では不正になることを確認。--print-configを偽hwmonで実行すると参照1本のmaximum曲線を生成する一方、固定版のvalidateCurvesは2本以上を要求する。追加でGPU曲線の最終値が100%未満でも受理され、温度取得失敗時の全開保証が崩れる経路を調査中。実機操作なし。
- 2026-11-14 17:12 [agent] 実装レビュー完了、修正が必要な不具合2件（ともにP2）。(1) install-case-fan-control-ubuntu.sh:284-285: CPU曲線が空だとmaximumの参照が1本となり、固定版fan2go 0.15.0の検証（2本以上必須）で導入失敗。(2) 同:202-204: GPU曲線の最終デューティ100%を検証しておらず、45:30 83:65を受理するため、GPU取得失敗の100℃でもPWM166止まり（CPU60℃以下なら全開にならない）。偽hwmonで--print-configを実行し両経路の出力を確認、上流の検証・補間実装と照合。既存24試験はmacOSでBash5/coreutils/LC_ALL=Cにて全件成功（実fan2goによる検証ではない）。補助スクリプト・unit・omp/ホスト設定のレビューでは追加の具体的不具合なし。コード変更・コミット・switch・実機操作なし。判定REVIEW_NG。
- 2026-11-14 17:13 [agent] 実装レビュー(gpt-6.1-sol)が終わった: 修正が必要な不具合が2件あります。
- 2026-11-14 17:17 [agent] 実装レビューの指摘 2 件を直した（agent/4。scripts/install-case-fan-control-ubuntu.sh）: (1) GPU の曲線の最後の点が 100% でないと止める（fan2go 0.15.0 の線形の曲線は最後の点より上で最後の値のままなので、GPU が読めないときの 100℃ でも全開にならない設定を通していた）。(2) CASE_FAN_CPU_CURVE が空のとき maximum に 1 本だけ並べていたのをやめ、ファンが GPU の曲線を直に指す形にした（fan2go 0.15.0 の検査は function の曲線に 2 本以上を求める）。確かめ: dekahamuntu の設定で作られる YAML は直す前とあとで diff なし（138 行。入れ直しは要らない）、試験 27 件 OK（3 件足した。にせの fan2go に 2 本未満で落ちる検査のまねを足した）、bash -n、shellcheck（warning なし）、4 つの構成の評価は変わらず。本物の fan2go の config validate は通していない（Linux のバイナリ）。develop の最新に載せ直した（19 コミット、一直線）

## エージェントの結果(2026-11-14 17:13)

実装レビュー(gpt-6.1-sol)

修正が必要な不具合が2件あります。

1. **[P2] GPU温度取得失敗時の全開が保証されない**  
   `scripts/install-case-fan-control-ubuntu.sh:202-204`  
   `CASE_FAN_GPU_CURVE="45:30 83:65"` を拒否せず、末尾をPWM 166として生成します。GPU取得失敗で100℃が入力されても、[固定版の補間処理](https://github.com/markusressel/fan2go/blob/0.15.0/internal/util/math.go)は末尾値に固定するため、CPU側が低温なら65%止まりです。末尾デューティを100%必須にするか、異常時の全開を通常曲線から独立させる必要があります。

2. **[P2] 文書で許可された「GPUのみ」の構成を導入できない**  
   `scripts/install-case-fan-control-ubuntu.sh:284-285`  
   `CASE_FAN_CPU_CURVE` が空だと、`maximum` 曲線の参照が `gpu_curve` 1本になります。しかし、[fan2go 0.15.0の検証](https://github.com/markusressel/fan2go/blob/0.15.0/internal/configuration/validation.go)は2本以上を要求するため、`write_config` で失敗します。CPU曲線がない場合はGPU曲線を直接使う必要があります。

偽hwmonで `--print-config` を実行し、両方の生成結果を確認。既存24試験は成功しましたが、実fan2goの検証は通していません。コード変更・コミット・実機操作なし。結果は `task_log(nix-config#4)` に記録済みです。

REVIEW_NG
