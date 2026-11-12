---
status: doing
created: 2026-11-11
updated: 2026-11-11
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
    done: false
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
