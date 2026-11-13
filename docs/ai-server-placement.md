# どのモデルをどちらのマシンで動かすか（叩き台）

状態: 叩き台（2026-11-11）。Flash-Next の実測を足した（2026-11-13）。dekahamuntu の Flash-Next の置き方は本人が決めた（2026-11-13。「[決定](#決定)」）。ほかは決めるのは本人。決まったら「決定」の節に書き、各ホストの設定（`hosts/ubuntu/*.env`、`~/ai` のモデル台帳）に反映する。

本人の案（2026-11-11）: dense の LLM と LoRA 学習は chibihamuntu、画像生成と MoE の LLM は dekahamuntu。

数字の出どころ: **実測**（chibihamuntu の実機・スクリプトのコメントにある計測）、**ファイル**（モデルのファイルの大きさ。VRAM の下限の目安）、**仕様**（メーカーの公表値）、**推測**（確かめていない見積もり）。

## 両マシンの資源

| | chibihamuntu | dekahamuntu |
|---|---|---|
| GPU | RTX 3090 ×1（Ampere、sm_86） | RTX 5060 Ti ×2（Blackwell、sm_120） |
| VRAM | 24GB | 16GB ×2（合計 32GB。1 つのモデルを載せられるのは、束ねなければ 16GB まで） |
| VRAM の帯域（仕様） | 936 GB/s | 448 GB/s ×2（1 枚あたり 3090 の約半分） |
| 低い精度の演算 | FP16/BF16、INT8 | FP16/BF16、INT8、**FP8・FP4（NVFP4）をハードウェアで扱う** |
| GPU の消費電力（仕様） | 350W | 180W ×2 |
| GPU 間 | — | NVLink なし。PCIe 5.0 x8 ×2（実機は 2 枚とも幅 x8・最大 Gen5。負荷時の速さは未確認。[dekahamuntu-setup.md](dekahamuntu-setup.md) の「PCIe の帯域」） |
| CPU | Intel i7-13700KF（24 スレッド） | AMD Ryzen 7 9700X（16 スレッド） |
| RAM | DDR4 64GB（2,666 MT/s で動いている） | DDR5 64GB（5,600 MT/s。帯域は DDR4 より広い。推測で 1.5〜2 倍） |
| ディスク | 1.9TB（約 900GB 使用） | 1.9TB（約 580GB 使用。2026-11-13） |

部品・仕様の正は [machines.md](machines.md)。この表は要約。

読み方:

- **dense の LLM の生成**は VRAM の帯域で速さが決まる。1 枚あたりの帯域は 3090 が約 2 倍で、24GB に 27B の Q4 が収まる。dekahamuntu で 27B を動かすには 2 枚に分ける必要があり、PCIe 越しになる。dense は chibihamuntu が向く
- **MoE の LLM**（Qwen3.8-Flash-Next、125B-A6B）はエキスパートの多くを RAM に置いて動かす。RAM の帯域（DDR5）と、GPU に置ける量（束ねて 32GB）が効く。実測では dekahamuntu の方が速かった（1 枚でも。llama.cpp の版は違う。下の「[実測（2026-11-13）](#実測2026-11-13-qwen38-flash-next)」）
- **画像・動画の生成**は 1 枚に収まれば並列に回せる。dekahamuntu は 2 枚あり、FP8・NVFP4 の重み（ComfyUI に既にある）をハードウェアで扱える。16GB を超えるモデルは RAM に逃がすので遅くなる
- **学習**は VRAM の量が効く（1 枚 24GB の方が余裕がある）。chibihamuntu が向く

## chibihamuntu で今動いているもの（2026-11-10 に読んだ）

| もの | 形 | VRAM | RAM | 出どころ |
|---|---|---|---|---|
| ComfyUI | `comfyui.service`（常駐） | 読んだ時点で 6.3GB（GPU 使用率 100%。何を生成していたかは不明） | — | 実測（nvidia-smi） |
| Qwen Router | `qwen38.service`（常駐。モデル未ロードなら 0） | 下表 | 下表 | — |
| art-studio | `art-studio.service`（Node、ComfyUI の出力を取り込む） | 使わない | 小さい | unit を読んだ |
| LoRA 学習 | `lora-charactor.timer`（5 分ごと、anima と sdxl）、`lora-auto*.timer`、`lora-train` の一時 unit | 不明（推測で 12〜20GB） | 不明 | unit を読んだ。VRAM は未計測 |
| Applio | `applio.service`（明示起動） | 不明（推測で 4〜8GB） | — | — |

1 枚を排他で使っている（`ai-mode`、unit の `Conflicts=`）。学習中は ComfyUI・Qwen が止まる。

### LLM（`~/models`、235GB）

| モデル | ファイル | VRAM（chibihamuntu） | 出どころ |
|---|---|---|---|
| Qwen3.8-27B UD-Q4_K_M（dense） | 16GB + mmproj 1GB | 128K ctx・Q8 KV で 24GB に収まる（推測で 21〜23GB） | ファイル。VRAM は推測 |
| Qwen3.8-27B UD-Q4_K_XL / Uncensored Q4_K_M / Heretic-v2 UD-Q4_K_XL | 各 16〜17GB | 同上 | ファイル |
| Qwen3.8-Flash-Next UD-Q3_K_XL（MoE 125B-A6B） | 86GB（3 分割） | 約 22GB（48 層中 38 層のエキスパートを RAM）。prompt 約 480 tok/s、生成 約 21 tok/s。2026-11-13 の計り方では、温まったあとの長い問いで入力 約 409、生成 約 22.7 tok/s | 実測（スクリプトのコメント。2026-11-13 は下の「実測」） |
| Qwen3.8-Flash-Next-Uncensored i1-IQ3_M | 84GB | 22.6GB（35 層を RAM）。生成 約 22 tok/s | 実測（同） |

Flash-Next（UD-Q3_K_XL）は RAM 64GB に収まる（2026-11-13 の実測）。温まったあとの llama-server の RSS は 45.7GB（うち mmap 43.0GB）で、問いのあいだのディスクの読みは止まる。ディスクを読むのは読み込みと最初の 2 回（合わせて 58.4GB）だけ。ComfyUI のノードから LLM を使うのは 27B だけ。

### ComfyUI のモデル（`~/ComfyUI/models`、約 400GB）

| 種類 | 主なもの | ファイル | 1 枚 16GB に載るか（推測） |
|---|---|---|---|
| SDXL のチェックポイント | rinFeatherfall、waiIllustrious など 13 個 | 各 6.9〜7.1GB | 載る |
| Anima（2.9B / 3.8B） | anima-base、anima38B_11、fnMix など 26 個 | 各 4.2〜8.8GB（+ テキストエンコーダー Qwen3 0.6B） | 載る |
| Qwen-Image 2.1 | int8 7.3GB + Qwen3-VL 8B int8 9.4GB | 合計 約 17GB | ComfyUI がテキストエンコーダーを入れ替えれば載る。同時には載らない |
| MOSS-Image 5B | int8 5.4GB + テキストエンコーダー | 約 10〜15GB | 載る見込み |
| Krea2 turbo | fp8 13.1GB | — | 載る。fp8 は Blackwell の方が向く |
| ACE-Step 1.5 XL（音楽） | 10GB + Qwen 4B 8.4GB | 約 18GB | 入れ替えれば載る |
| MiniMax H3（動画） | int8 21GB + Qwen3-VL 32B NVFP4 15.7GB | 約 37GB | **載らない**。RAM に逃がして遅くなる。3090 でも 24GB を超えている |
| LoRA | 59GB | — | — |

## 割り当ての案

### 案 A（本人の案に沿う。既定にしたもの）

| マシン | 動かすもの | 理由 |
|---|---|---|
| chibihamuntu | Qwen3.8-27B（dense、4 種）、LoRA 学習（anima・sdxl の自動の学習、`lora-train`）、Applio、MiniMax H3（動画） | dense は帯域の広い 1 枚 24GB が速い。学習は VRAM に余裕がいる。MiniMax H3 は 16GB には全く載らない |
| dekahamuntu GPU 0 | ComfyUI（SDXL・Anima・Qwen-Image・MOSS・Krea2・ACE-Step）、art-studio | 画像生成を学習と分けられる（chibihamuntu の学習中も絵を作れる）。FP8・NVFP4 をハードウェアで扱える |
| dekahamuntu GPU 1 | Qwen3.8-Flash-Next（MoE、Router） | ComfyUI と独立に常駐できる |
| dekahamuntu GPU 0+1 | Flash-Next を束ねて（`ai-mode llm-dual`） | 長い作業で速さが要るとき。ComfyUI は止まる |

効くこと:

- chibihamuntu の学習（5 分ごとの timer）が、画像生成と LLM を止めなくなる（いまは 1 枚を取り合っている）
- ComfyUI のノードから 27B を呼ぶ使い方（VRAM の受け渡し）は、同じマシンにないとできない。dekahamuntu の ComfyUI から LLM を使うなら、Flash-Next を GPU 1 で呼ぶか、chibihamuntu の 27B を HTTP で呼ぶ形に変える（`~/ai` のノードの変更。要検討）

確かめること（推測の部分）:

1. Flash-Next を GPU 1 枚（16GB）で動かすと chibihamuntu（24GB）より遅くなる見込みだったが、実測（2026-11-13）では 1 枚でも chibihamuntu より速く、束ねるとさらに速い（下の「実測」。llama.cpp の版は違う）
2. ComfyUI の主なワークフローが 16GB で回るか（Qwen-Image・ACE-Step はテキストエンコーダーの入れ替えで遅くなる）
3. dekahamuntu の n-cpu-moe: 詰めた（2026-11-13、`--tensor-split 39,10`）。UD-Q3_K_XL は 1 枚 45・束ね 33、Uncensored 版は 1 枚 42・束ね 31

### 案 B（LLM を chibihamuntu に寄せる）

- chibihamuntu: LLM すべて（27B・Flash-Next）、Applio
- dekahamuntu: ComfyUI（GPU 0）、LoRA 学習（GPU 1。SDXL と Anima の LoRA は 16GB に収まる見込み、推測）

Flash-Next が dekahamuntu で遅かったときの案。学習を dekahamuntu に移すには `~/ai/scripts/lora-train` と `lora-charactor` の `Conflicts=` を GPU ごとに分ける変更が要る。

### 案 C（dekahamuntu を画像だけの 2 本立てにする）

- dekahamuntu: ComfyUI を 2 つ（GPU ごとに 1 つ。ポートを分ける）で並列に生成
- chibihamuntu: LLM と学習（いまの形から ComfyUI を外す）

大量に画像を作る使い方（データセットづくりなど）向け。ComfyUI を 2 つ動かす形はスクリプトにまだない（作るなら `install-comfyui-ubuntu.sh` にインスタンスの変数を足す）。

## 実測（2026-11-13）: Qwen3.8-Flash-Next

chibihamuntu（3090 1 枚）、dekahamuntu の 1 枚、dekahamuntu の 2 枚束ねで、同じモデル・同じ問いの速さを計った。

### 計り方

- モデル: `unsloth/Qwen3.8-Flash-Next-GGUF` の UD-Q3_K_XL（revision 38bb39ee…、3 分割）と `mmproj-BF16.gguf`。dekahamuntu へは `install-qwen38-ubuntu.sh` の `download_model` と同じ取り方（aria2c、同じ revision・名前）でこの 2 つだけを取った（約 87GB を約 3 分 50 秒、約 490MiB/s）。Uncensored 版（i1-IQ3_M、約 89.5GB）はあとで取って詰めた（下の「[Uncensored 版の詰めと速さ](#uncensored-版の詰めと速さdekahamuntu)」）。この表の計測は `install-qwen38-ubuntu.sh` を流す前（流したのはこのあと。下の「[入れた unit での確かめ](#入れた-unit-での確かめdekahamuntu)」）
- llama-server を一時の user unit（systemd-run）で、`qwen38.service` と同じ引数で立てた: `--ctx-size 131072 --n-gpu-layers 99 --flash-attn on --cache-type-k q8_0 --cache-type-v q8_0 --parallel 1 --jinja --batch-size 2048 --ubatch-size 2048 --mmproj …`。Router（`--models-preset`）と `--agent` は使わず、モデル 1 つを直に指定した
- 束ねは `CUDA_VISIBLE_DEVICES=0,1 --split-mode layer --tensor-split <値>`、1 枚は `CUDA_VISIBLE_DEVICES=1`（どちらも `CUDA_DEVICE_ORDER=PCI_BUS_ID`）
- 問い: `/v1/chat/completions`、temperature 0、max_tokens 512、cache_prompt false。短い問い = 入力 83 トークン、長い問い = 入力 3,939 トークン（`docs/ubuntu-server.md` の先頭 9,000 字の解説を頼む）。どの回も 512 トークンを出し切った（finish=length）
- 順: 読み込み → 短い問い 1 回（読み込み直後）→ 長い問い 1 回 → 長い問い 3 回（温まったあと）→ 短い問い 3 回。各段の前後に、llama-server の RSS（/proc/PID/status）、major page fault、プロセスのディスクの読み（/proc/PID/io の read_bytes）、free -m、swap、VRAM を記録した
- llama.cpp の版は 2 台で違う: chibihamuntu 0.5.0（build 11146）、dekahamuntu 0.6.0（build 11429）。そろえていない（switch をしない決まり）。速さの差には版の差も混ざる
- dekahamuntu の読み込み時間は、取得した直後でファイルがページキャッシュに載った状態の値。冷えた状態（ページキャッシュを捨てる）は sudo が要るので計っていない。chibihamuntu の読み込みはディスクから 42.6GB を読んだ

### 結果

| | chibihamuntu（3090 24GB） | dekahamuntu 1 枚（GPU 1、ComfyUI はアイドルで同居） | dekahamuntu 2 枚束ね（ComfyUI は止める） |
|---|---|---|---|
| llama.cpp | 0.5.0 | 0.6.0 | 0.6.0 |
| n-cpu-moe（48 層中、エキスパートを RAM に置く層数） | 38（今の設定） | 45 | 33（tensor-split 39,10） |
| 長い問い・温まったあと 入力 tok/s（3 回） | 409.4 / 408.4 / 409.0 | 437.6 / 440.2 / 440.2 | 504.0 / 518.7 / 518.8 |
| 長い問い・温まったあと 生成 tok/s（3 回） | 22.77 / 22.67 / 22.60 | 25.66 / 25.62 / 25.61 | 28.97 / 28.97 / 28.91 |
| 短い問い・温まったあと 入力 tok/s（3 回。83 トークンしかないので目安） | 34.1 / 38.6 / 38.7 | 50.2 / 52.5 / 52.6 | 61.4 / 67.4 / 67.5 |
| 短い問い・温まったあと 生成 tok/s（3 回） | 23.51 / 23.90 / 23.39 | 25.36 / 26.11 / 26.15 | 28.60 / 29.58 / 29.46 |
| 読み込み直後の 1 回目（短い問い）入力 / 生成 | 2.82 / 13.78 | 11.1 / 20.87 | 12.4 / 23.77 |
| 最初の長い問い 入力 / 生成 | 117.7 / 21.64 | 221.8 / 24.94 | 256.0 / 27.58 |
| 読み込み（起動から /health が 200 まで） | 125.0 秒（ディスクから 42.6GB） | 3.1 秒（ページキャッシュに載った状態。ディスクから 0.2GB） | 3.4 秒（同じ。ほかの回は 4〜10 秒） |
| VRAM（計測のあと） | 23,602 / 24,576MiB（空き 974） | GPU 1: 14,822 / 16,311MiB（空き 1,489）。GPU 0 は ComfyUI の 138MiB だけ | GPU 0: 15,440、GPU 1: 14,834 / 各 16,311MiB（空き 871 / 1,477） |
| llama-server の RSS（うちファイル由来 = mmap） | 45.7GB（43.0GB） | 54.5GB（51.8GB） | 41.2GB（38.4GB） |
| free -m（計測のあと）used / buff/cache / available（total） | 4,987 / 60,128 / 59,119（64,106） | 6,029 / 56,232 / 55,376（61,405） | 5,619 / 56,776 / 55,785（61,405） |
| swap の使用 | 27MB（前から 19MB） | 172MB（前から 122MB） | 0 |
| 温まったあとの長い問い 3 回のあいだのディスクの読み / major fault | +1MB / +17 | +1MB / +49 | +93MB / +302 |
| 温まるまで（読み込み＋最初の 2 回）のディスクの読み | 58.4GB | 11.2GB（ページキャッシュに載った状態から） | 10.5GB（同じ） |
| 計測中の GPU の温度の最大 | 51℃ | 41℃（GPU 1） | 51℃ / 34℃ |

比（長い問い・温まったあとの中央の値）:

- 生成: 3090 の 22.67 に対して、1 枚 25.62（+13%）、束ね 28.97（+28%）
- 入力: 409.0 に対して、440.2（+8%）、518.7（+27%）
- 束ねは 1 枚より生成 +13%、入力 +18%

### chibihamuntu では RAM に収まっていたか、ディスクも使っていたか

- 収まっている。温まったあとは RSS 45.7GB（うち mmap のファイル 43.0GB）で、RAM 64GB の中。swap は 27MB。温まったあとの長い問い 3 回のあいだのディスクの読みは +1MB で、読みは止まる
- ディスクを読むのは読み込み（42.6GB）と最初の 2 回（さらに 15.8GB）だけ。ファイルは約 87GB あるが、約 22GB ぶんは VRAM へ行き、残りのうち実際に触るのが約 43GB
- ページキャッシュの載り具合（mincore で見た。計測のあと）: chibihamuntu は 2 つ目の分割（46.6GiB）が 18.8GiB（40%。ファイルの前半はほぼ載っていない）、3 つ目（37.2GiB）は 100%。dekahamuntu（束ねのあと）は 2 つ目 18.0GiB（38%。同じく前半が載っていない）、3 つ目 34.5GiB（92%）
- 2 つ目の前半の約 28GiB は n-gram 埋め込み（mmap のまま、1 トークンあたり数行しか読まない）にあたる見込み（テンソルの並びは確かめていない）

### 1 枚で ComfyUI と同居できるか（RAM の圧をまねた試し）

- ComfyUI がアイドル（RAM 約 1.4GB）なら収まる（上の表）。ただし RAM の残りは約 5GB（used 6.0GB ＋ mmap 51.8GB / 61.4GB）
- ComfyUI がモデルを RAM に持った状態は、本番のキューに生成を投げない決まりなので作っていない。代わりに、別のプロセスで RAM を確保してまねた（1 枚、n-cpu-moe 45 のまま）:
  - 16GB を確保: 直後の長い問いは 入力 70.4 / 生成 18.53、2 回目 204.8 / 25.21、3 回目 435.5 / 25.72。この 3 回でディスクを 36.5GB 読み直した。カーネルが確保したプロセスの側を swap（8GB を使い切り）に追い出して、元の速さに戻った（アイドルなメモリなので追い出せた。使っている最中の ComfyUI のモデルならこうは戻らない）
  - 24GB を確保（swap が埋まり、RAM に残ったのは約 19.5GB）: 長い問い 3 回が 入力 69.8 / 72.2 / 84.5、生成 16.69 / 18.96 / 17.44。3 回でディスクを 99.2GB 読んだ（1 回あたり約 33GB）。major fault +338,000。短い問いは 16.3 / 18.86 → 38.6 / 25.46
- つまり、同じ機械でほかに 16〜20GB の RAM を使われると、モデルのページキャッシュが追い出され、問いのたびに SSD を数十 GB 読み直して、生成が 17〜19 tok/s、入力が 70〜85 tok/s に落ちる
- この試しのあと、dekahamuntu の swap に約 950MB が残った（ほかのプロセスのページ。害はないが、試しの前は 0）

### n-cpu-moe と層の分け方の詰め（dekahamuntu、llama.cpp 0.6.0）

VRAM は読み込み直後の MiB（GPU 0 / GPU 1）。

| 形 | n-cpu-moe @ tensor-split | 結果 |
|---|---|---|
| 束ね | 33 @ 1,1（今までの `LLM_DUAL_TENSOR_SPLIT`） | 読み込めない。層を半分ずつ分けると、エキスパートを GPU に置く後ろの 15 層が全部 GPU 1 に寄り、19.1GB を確保しようとして落ちる（`--n-cpu-moe N` は前から N 層のエキスパートを RAM に置くので、重い層は後ろに固まる） |
| 束ね | 33 @ 40,9 | GPU 0 に mmproj（865MiB）が入らず落ちる |
| 束ね | 38 @ 43,6 | 14,732 / 9,920（長い問いの 1 回目 159.9 / 26.21） |
| 束ね | 38 @ 41,8 | 12,434 / 12,216 |
| 束ね | 34 @ 39,10 | 14,222 / 14,678。温まったあと 入力 494.8〜510.6、生成 28.66〜28.68。計測のあと 14,378 / 14,834（空き 1,933 / 1,477） |
| 束ね | **33 @ 39,10**（採用） | 15,284 / 14,678。計測のあと 15,440 / 14,834（空き 871 / 1,477）。上の表の値 |
| 1 枚 | 43（今までの推測値） | mmproj が入らず落ちる |
| 1 枚 | 46 | 13,604 |
| 1 枚 | **45**（採用） | 14,666。計測のあと 14,822（空き 1,489） |
| 1 枚 | 44 | 計算で 15,728（空き約 0.4GB）。流していない |
| Uncensored 版・束ね | 30 @ 39,10 | GPU 0 に mmproj（862MiB）が入らず落ちる |
| Uncensored 版・束ね | **31 @ 39,10**（採用） | 15,298 / 13,014。計測のあと 15,454 / 13,170（空き 857 / 3,141） |
| Uncensored 版・1 枚 | 41 | 15,508（空き 803。計測のあとは約 650 の見込みで、きつい） |
| Uncensored 版・1 枚 | **42**（採用） | 14,370。計測のあと 14,526（空き 1,785） |

- エキスパート 1 層ぶんは約 1,062MiB、層を 1 つ GPU の間で動かすと約 1,148MiB。束ねの 33 と 34 の速さの差は約 1%
- Uncensored 版のエキスパート 1 層ぶんは約 1,138MiB
- 採用した値は `hosts/ubuntu/dekahamuntu.env`（`QWEN_FLASH_N_CPU_MOE=45`、`QWEN_FLASH_UNCENSORED_N_CPU_MOE=42`、`QWEN_DUAL_FLASH_N_CPU_MOE=33`、`QWEN_DUAL_FLASH_UNCENSORED_N_CPU_MOE=31`、`LLM_DUAL_TENSOR_SPLIT=39,10`）。tensor-split は unit の引数で、Router の全部のモデルに同じ値が効く。UD-Q3_K_XL に合わせた 39,10 では、Uncensored 版の束ねで GPU 1 に約 3.1GB 余る（使い切るにはモデルごとの tensor-split が要る。スクリプトは変えていない）

### Uncensored 版の詰めと速さ（dekahamuntu）

- モデル: mradermacher の Qwen3.8-Flash-Next-Uncensored i1-IQ3_M（約 89.5GB）と `Qwen3.8-Flash-Next-Uncensored.mmproj-f16.gguf`。`install-qwen38-ubuntu.sh` の `download_model` と同じ取り方で取った（約 473MiB/s）。ファイルの大きさは chibihamuntu と同じ（sha256 は照らしていない）
- 計り方は上と同じ（llama.cpp 0.6.0、qwen38.service と同じ引数、同じ問い）。1 枚は GPU 1 で、ComfyUI は動かしたまま。束ねのあいだは ComfyUI を止めた（15:04:52〜15:07:37 UTC。キューが空で、art-studio に running のループがないのを確かめてから。戻して `/system_stats` 200）

| | 1 枚（GPU 1）、n-cpu-moe 42 | 束ね、n-cpu-moe 31 @ 39,10 |
|---|---|---|
| 長い問い・温まったあと 入力 tok/s | 452.1 / 477.3 / 476.9 | 554.5 / 560.7 |
| 長い問い・温まったあと 生成 tok/s | 29.37 / 29.44 / 29.42 | 33.82 / 33.95 |
| 最初の長い問い 入力 / 生成 | 88.8 / 26.67 | 160.1 / 32.29 |
| 短い問い 入力 / 生成 | 40.9 / 27.03 → 53.4 / 29.91 | 62.8 / 33.05 → 66.4 / 34.37 |
| VRAM（計測のあと） | GPU 1: 14,526MiB（空き 1,785） | 15,454 / 13,170MiB（空き 857 / 3,141） |
| llama-server の RSS（うち mmap） | 48.7GB（46.3GB） | 37.6GB（35.1GB） |

- UD-Q3_K_XL（1 枚 25.6、束ね 29.0）より生成が速い。RAM も少ない

### 入れた unit での確かめ（dekahamuntu）

`install-qwen38-ubuntu.sh` を流したあと（2026-11-13）、Router（`qwen38.service`、GPU 1、`--models-max 1`）経由で計った。ComfyUI はアイドルで、モデルを載せていなかった（ComfyUI の cgroup のメモリは約 85〜140MB）。

| | UD-Q3_K_XL | Uncensored 版 |
|---|---|---|
| 最初の短い問い 入力 / 生成 | 7.8 / 19.54 | 3.4 / 15.57 |
| 長い問い 入力 / 生成（1 回目 → 2 回目 → 3 回目） | 170.4 / 24.59 → 426.6 / 25.67 → 444.4 / 25.69 | 186.7 / 28.08 → 476.0 / 29.35 → 476.0 / 29.28 |
| VRAM | GPU 1: 14,822MiB。GPU 0 は ComfyUI の 138MiB だけ | GPU 1: 14,526MiB |
| llama-server の RSS（うち mmap） | 52.0GB（50.4GB） | 47.5GB（45.5GB） |
| free -m used / buff/cache / available | 4,348 / 56,781 / 57,057 | 4,477 / 57,602 / 56,928 |

- モデル未ロードのとき、GPU 1 の VRAM は 4MiB。Uncensored 版への切り替えで UD-Q3_K_XL は自動でアンロードされた
- swap は 1,474MB（前の試しの名残を含む）
- `ai-mode llm-dual`（15:14 UTC）で qwen38 と ComfyUI が止まり、qwen38-dual が起動した。長い問いは UD-Q3_K_XL 125.7 / 27.26 → 502.9 / 29.13、Uncensored 版 102.0 / 31.06 → 550.5 / 33.87。VRAM は Uncensored 版で 15,454 / 13,170MiB。`ai-mode split` で戻した（15:17:37 UTC に ComfyUI の `/system_stats` 200。qwen38 は active、qwen38-dual は inactive。モデルは 2 つとも unloaded）
- そのあいだ ComfyUI は `/system_stats` 200 のまま、fan2go は active、`case-fan-gpu-temp.status` は ok

### そのほか

- 計測のあいだ fan2go は active のまま（再起動なし）、`case-fan-gpu-temp.status` は ok、pwm は最大 108。GPU は最大 51℃
- dekahamuntu の GPU 0 の `utilization.gpu` が、何も載っていないとき（2MiB、約 33W、ComfyUI を止めた状態）でも 100% と読める。原因は調べていない
- chibihamuntu: `lora-charactor pause`（10:39 UTC）→ 計測 → `resume`（10:51 UTC）。止めたのは次の学習を始めることだけで、途中の学習は切っていない（後処理が自分で終わった）。再開のあと次の学習が走っているのを確かめた
- dekahamuntu: ComfyUI を止めたのは 10:48〜10:59 UTC（束ねの計測のあいだ。キューが空で、art-studio に running のループがないのを確かめてから）。起動し直して `/system_stats` が 200

### 見立て（実測からの判断）

- Flash-Next を dekahamuntu に置く案（案 A）は、速さの面で裏づけられた。1 枚でも 3090 より速い（ただし llama.cpp の版が違う）
- 束ねが最も速く、RAM も約 13GB 少なく済むが、ComfyUI を止める（排他）。1 枚は ComfyUI と同居できるが、ComfyUI が RAM を 16GB 以上使うと SSD を読み直して遅くなる（SSD への負荷はここで出る）
- 選べた形と、本人が選んだもの（2026-11-13。下の「決定」）:
  - **(b) qwen38.service（1 枚、GPU 1）を常駐させ、重く使うときだけ束ねる**（選ばれた）。Router はモデルを載せるまで VRAM を使わない。画像と LLM を同時に使えるが、ComfyUI が RAM を多く使う生成と重なると、SSD を読み直して遅くなる
  - (a) ふだんは ComfyUI だけ、LLM を使うときに `ai-mode llm-dual` で束ねる。切り替えのあいだ画像は作れない
  - (c) chibihamuntu に残す。生成は 1 枚の dekahamuntu より約 1 割遅く、chibihamuntu の学習と 1 枚を取り合う形が続く
- 余裕を取るなら、束ねは n-cpu-moe 34（空き 1.9GB / 1.5GB、速さの差は約 1%）。画像の入力（mmproj）で GPU 0 の VRAM が足りるかは確かめていない

## 決定

### dekahamuntu の Flash-Next（2026-11-13）

本人の決め（2026-11-13、原文）:

> いや、画像生成のモデル類はほとんど16gbで収まると思うからとりあえずflash nextとcomfy常駐にしよう。nixで設定して

形（上の「見立て」の (b)）:

- dekahamuntu: GPU 0 = ComfyUI、GPU 1 = Flash-Next の Router（`qwen38.service`）を常駐。`ai-mode split` が既定
- 束ね（`qwen38-dual.service`）は `ai-mode llm-dual` で切り替える。既定にしない
- GPU 2 枚での画像の並列生成（案 C）は今回やらない
- dekahamuntu に常駐を足した（`install-qwen38-ubuntu.sh` を流した。「[入れた unit での確かめ](#入れた-unit-での確かめdekahamuntu)」）。chibihamuntu の Flash-Next はそのまま（chibihamuntu から外すか、27B だけにするかは本人がまだ決めていない）
- Tailscale Serve の 8443（tailnet への Qwen の公開）は、本人が sudo で流すまでない（`sudo tailscale serve --bg --https=8443 http://127.0.0.1:8080`。2026-11-13 の時点でまだ）

### 同居の心配（RAM。設定は変えていない）

- 本人の理由は「画像生成のモデル類はほとんど 16GB で収まる」で、VRAM の話。GPU は分かれているので VRAM は取り合わない
- RAM は別。Flash-Next を読み込むと llama-server が 47.5〜52.0GB を使い（RSS。入れた unit での値）、RAM 61.4GB から used と mmap を引いた残りは、UD-Q3_K_XL で約 6.7GB（61.4 − 4.3 − 50.4）、Uncensored 版で約 11.4GB（61.4 − 4.5 − 45.5）
- ComfyUI がモデルを RAM に持った状態での Flash-Next の速さは計れていない（本番のキューに生成を投げない決まり）。RAM が足りなくなったときの落ち方は、前の「[RAM の圧をまねた試し](#1-枚で-comfyui-と同居できるかram-の圧をまねた試し)」の値しかない（ほかに 16〜20GB を使われると、生成 17〜19 tok/s、入力 70〜85 tok/s に落ちた）
- 対策の案（どれもまだしていない）:
  - ComfyUI の RAM のキャッシュを絞る起動オプション（`COMFY_EXTRA_ARGS` は本人の決めで空のまま）
  - RAM の増設（ボードの最大は 256GB、空きスロット 2）
  - LLM を重く使うときは `ai-mode llm-dual` に切り替える（RSS が約 13GB 少ない）
  - Uncensored 版を使う（RSS が約 4.5GB 少ない）

## 次にやること

1. 本人が sudo で Tailscale Serve の 8443 を設定する（`sudo tailscale serve --bg --https=8443 http://127.0.0.1:8080`、または `configure-tailscale-serve-ubuntu.sh`）。それまで dekahamuntu の Qwen は tailnet から見えない
2. dekahamuntu の Flash-Next の残り: ComfyUI にモデルが載った状態（RAM を使っている状態）での速さ、Uncensored 版の束ねで GPU 1 を使い切る（モデルごとの tensor-split。スクリプトの変更が要る）、画像の入力（mmproj）を使ったときの VRAM、llama.cpp の版をそろえた比較、冷えた状態（ページキャッシュを捨てたあと）の読み込み時間
3. chibihamuntu の Flash-Next をどうするか（外す、27B だけにする、そのまま）を本人が決める
4. chibihamuntu の学習と Applio の VRAM を計る（`nvidia-smi --query-gpu=memory.used --format=csv -l 5` を学習中に流す）
5. 決まったら、モデルを置き直す（`~/ai/scripts/models` の台帳と restore。数百 GB の転送になる）
6. Mac の codex・pi の設定（`home/common.nix`）は chibihamuntu の 8443 番を指している。dekahamuntu の LLM を使うなら、そのプロファイルを足す
