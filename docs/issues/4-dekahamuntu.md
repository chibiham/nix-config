---
status: doing
created: 2026-11-11
updated: 2026-11-13
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
    done: false
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
