# どのモデルをどちらのマシンで動かすか（叩き台）

状態: 叩き台（2026-11-11）。決めるのは本人。決まったら「決定」の節に書き、各ホストの設定（`hosts/ubuntu/*.env`、`~/ai` のモデル台帳）に反映する。

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
| GPU 間 | — | NVLink なし。PCIe 5.0 x8 ×2（見込み。実機で確かめる。[dekahamuntu-setup.md](dekahamuntu-setup.md) の「PCIe の帯域」） |
| CPU | Intel i7-13700KF（24 スレッド） | AMD Ryzen（型番は要確認） |
| RAM | DDR4 64GB | DDR5 64GB（帯域は DDR4 より広い。推測で 1.5〜2 倍） |
| ディスク | 1.9TB（約 900GB 使用） | 未確認 |

読み方:

- **dense の LLM の生成**は VRAM の帯域で速さが決まる。1 枚あたりの帯域は 3090 が約 2 倍で、24GB に 27B の Q4 が収まる。dekahamuntu で 27B を動かすには 2 枚に分ける必要があり、PCIe 越しになる。dense は chibihamuntu が向く
- **MoE の LLM**（Qwen3.8-Flash-Next、125B-A6B）はエキスパートの多くを RAM に置いて動かす。RAM の帯域（DDR5）と、GPU に置ける量（束ねて 32GB）が効く。dekahamuntu が向く見込み（推測。実測して比べる）
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
| Qwen3.8-Flash-Next UD-Q3_K_XL（MoE 125B-A6B） | 86GB（3 分割） | 約 22GB（48 層中 38 層のエキスパートを RAM）。prompt 約 480 tok/s、生成 約 21 tok/s | 実測（スクリプトのコメント） |
| Qwen3.8-Flash-Next-Uncensored i1-IQ3_M | 84GB | 22.6GB（35 層を RAM）。生成 約 22 tok/s | 実測（同） |

Flash-Next は RAM をほぼ使い切る（ページキャッシュに約 90GB を読む）。ComfyUI のノードから LLM を使うのは 27B だけ。

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

1. Flash-Next を GPU 1 枚（16GB）で動かすと、chibihamuntu（24GB）より遅くなる見込み（GPU に置けるエキスパートが減り、帯域も半分）。束ねた 32GB で chibihamuntu より速くなるかを実測で比べる。遅ければ、Flash-Next は chibihamuntu に残す案（案 B）に寄せる
2. ComfyUI の主なワークフローが 16GB で回るか（Qwen-Image・ACE-Step はテキストエンコーダーの入れ替えで遅くなる）
3. dekahamuntu の n-cpu-moe（`hosts/ubuntu/dekahamuntu.env` の推測値 43 / 40、束ねて 33 / 30）

### 案 B（LLM を chibihamuntu に寄せる）

- chibihamuntu: LLM すべて（27B・Flash-Next）、Applio
- dekahamuntu: ComfyUI（GPU 0）、LoRA 学習（GPU 1。SDXL と Anima の LoRA は 16GB に収まる見込み、推測）

Flash-Next が dekahamuntu で遅かったときの案。学習を dekahamuntu に移すには `~/ai/scripts/lora-train` と `lora-charactor` の `Conflicts=` を GPU ごとに分ける変更が要る。

### 案 C（dekahamuntu を画像だけの 2 本立てにする）

- dekahamuntu: ComfyUI を 2 つ（GPU ごとに 1 つ。ポートを分ける）で並列に生成
- chibihamuntu: LLM と学習（いまの形から ComfyUI を外す）

大量に画像を作る使い方（データセットづくりなど）向け。ComfyUI を 2 つ動かす形はスクリプトにまだない（作るなら `install-comfyui-ubuntu.sh` にインスタンスの変数を足す）。

## 決定

（本人が決めたらここに書く）

## 次にやること

1. dekahamuntu の第2段（[dekahamuntu-setup.md](dekahamuntu-setup.md)）のあと、案 A で Flash-Next を 1 枚・束ねた形で計り、上の表に実測を足す
2. chibihamuntu の学習と Applio の VRAM を計る（`nvidia-smi --query-gpu=memory.used --format=csv -l 5` を学習中に流す）
3. 決まったら、モデルを置き直す（`~/ai/scripts/models` の台帳と restore。数百 GB の転送になる）
4. Mac の codex・pi の設定（`home/common.nix`）は chibihamuntu の 8443 番を指している。dekahamuntu の LLM を使うなら、そのプロファイルを足す
