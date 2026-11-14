---
status: doing
created: 2026-11-15
updated: 2026-11-15
goal:
  - text: dekahamuntu の ComfyUI が 0.45.0 以上で動き、入っている拡張が読み込めて、art-studio が使う主なレシピ(SDXL・Anima・Anima 2.9B・Qwen-Image・MOSS)で1枚ずつ出るのを確かめてある。前の版へ戻す手順が文書にある
    done: false
  - text: dekahamuntu で MiniMax H3 Image が、テキストエンコーダーを GPU 1・本体を GPU 0 に載せた形で1枚出て、プロンプトを変えた2枚目で入れ替えが起きない(各 GPU の VRAM で確かめる)。今までのワークフローは GPU 0 のまま動く
    done: false
  - text: qwen38.service(Router)を止めずに同居できる。Flash-Next が GPU 1 に載っているときの扱い(自動で降ろす・前に降ろす・分かる形で失敗する)が決まっていて、実機で確かめてある
    done: false
  - text: A(GPU 0 だけで入れ替え)と B の秒数・VRAM・RAM、本体の版(公式 int8 と GGUF)の速さと絵の差を計った表があり、既定にする版とその理由が書いてある。結果の絵を画像つきの spec(docs/specs/5/<名前>/index.html)に並べる
    done: false
  - text: 実機に入れた設定が hosts/ubuntu/dekahamuntu.env とスクリプトから作り直せ、chibihamuntu の設定と挙動が変わっていない。構成・計測・戻し方が docs に書いてある
    done: false
assignee: agent
---
# dekahamuntu の ComfyUI を更新し、MiniMax H3 Image を2枚の GPU に分けて使えるようにする

## 内容

本人(2026-11-15):

> minimax h3 imageをcomfyで使えるようにしたいんだけど、どういう構成で使うのがよさそうかな

(執事が3つの案を出した: A = dekahamuntu の GPU 0 だけでテキストエンコーダーと本体を入れ替える / B = dekahamuntu の2枚で、テキストエンコーダーを GPU 1・本体を GPU 0 に載せたままにする / C = chibihamuntu の 3090。B を勧めた)

> Bで構成しよう。comfy更新もやろう。flash nextはあんまり使わなそうなので大丈夫なんだけど、llamaから呼び出しなければメモリ取り合わない？llama停止しなくても大丈夫なのかな。

### 執事の読み(本人の言葉ではない)

- dekahamuntu(RTX 5060 Ti 16GB ×2)で MiniMax H3 Image を使えるようにする。形は B: テキストエンコーダー(Qwen3-VL-32B)を GPU 1、絵の本体(DiT)を GPU 0 に載せたままにして、プロンプトが変わっても入れ替えが起きないようにする。
- ComfyUI の更新もこの issue でやる。H3 Image は ComfyUI 0.45.0 以上が要る。いまは dekahamuntu・chibihamuntu とも 0.42.0(e3bee7ff、2026-10-20)。**更新するのは dekahamuntu だけ**(chibihamuntu の ComfyUI は disable 済みで、H3 の動画を手で使うときだけ起こす。そちらは触らない。版が分かれることは文書に書く)。
- llama(qwen38.service、Router)は止めない。本人は Flash-Next をあまり使わない見込み。ただし、執事が 2026-11-15 に実機で見たところ、**一度読み込んだモデルは自分では降りない**(本人が約8時間前に試した Uncensored 版が GPU 1 に 14.5GB、RAM に約 52GB 載ったままだった)。読み込まれていなければ Router は VRAM をほぼ使わない(4MiB、RSS 約 47MB)。なので「止めなくてよいが、使い終わったモデルを降ろす仕組みが要る」。llama-server に `--sleep-idle-seconds` がある(Router の形で効くかは未確認)。
- 調べたこと(Web。実機では未検証):
  - 公式のファイル(Comfy-Org): `diffusion_models/minimax_h3_image_pruned_int8_convrot.safetensors`(21GB)、テキストエンコーダーは Qwen3-VL-32B(H3 の動画と共通とされる。`text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors` 15GB が dekahamuntu にすでにある。公式の文書は int8 版 25.28GB を挙げている)、`vae/minimax_h3_image_vae_fp16.safetensors`(1.17GB)、任意のプロンプト拡張 `qwen3.5_9b_w4a8_gptq.safetensors`(7.34GB)。
  - 6 steps・cfg 1・euler / simple。既定 2048×2048、最大は約 4096×4096。画像の編集は入力16枚まで。
  - 第三者の GGUF(Abiray/MiniMax-H3-Image-GGUF): Q4_K_M 11.6GB、Q5_K_M 14.1GB。ComfyUI-GGUF のノードが要る。公式ではない。
  - 出どころ: https://docs.comfy.org/tutorials/image/minimax/minimax-h3-image 、https://blog.comfy.org/p/minimax-h3-image-is-now-available

### やること

1. **ComfyUI の更新(dekahamuntu)**: `scripts/update-comfyui-ubuntu.sh` の流儀で 0.45.0 以上へ。前の版(e3bee7ff)へ戻せる手順を先に確かめる。更新のあと、入っている拡張(chibiham-recipe・chibiham-save-meta・Anima 3.8B の橋渡しほか)が読み込めること、art-studio が使う主なレシピ(SDXL・Anima・Anima 2.9B・Qwen-Image・MOSS)で1枚ずつ出ること、art-studio の画面が 200 を返すことを確かめる。壊れたら戻して、何が壊れたかを報告する。
2. **ファイルの取得**: 本体と VAE(要ればプロンプト拡張)。既存の取得の流儀(版と sha256 の固定、manifest)に合わせる。テキストエンコーダーは手元の NVFP4 版が H3 Image でも使えるかを確かめ、使えなければ必要なものを取る。
3. **B の構成**: ComfyUI に2枚の GPU を見せる(`COMFY_CUDA_DEVICES`。既定のデバイスは GPU 0 のままで、今までのワークフローの挙動を変えない。モザイクの YOLO も GPU 0 のまま)。テキストエンコーダーを GPU 1 に固定する方法を決める(ComfyUI の本体の機能でできるか、拡張(ComfyUI-MultiGPU など)が要るか。第三者の拡張を入れるなら、版を固定し、このリポジトリの「公開から72時間未満のものは使わない」の方針に合わせる)。
4. **llama との同居**: Router は止めない。Flash-Next が GPU 1 に載っているときに H3 Image を使うとどうなるかを決めて確かめる: 使い終わったモデルを自動で降ろす(`--sleep-idle-seconds` など。ホストの設定の変数にする)、H3 Image の前に降ろす、載っていたら分かる形で失敗する、のどれか(組み合わせでもよい)。`ai-mode` に形を足すなら既存の形(split・llm-dual)に合わせる。
5. **計測**: A(GPU 0 だけで入れ替え)と B を、同じ絵・同じ設定で比べる。1枚目(読み込みを含む)と、プロンプトを変えた2枚目以降の秒数、各 GPU の VRAM、RAM。本体は公式の int8(21GB。16GB に載らない分の逃がし方を含めて)と、GGUF(Q5_K_M・Q4_K_M)を比べ、速さと絵の差を見て既定を決める。2048² と、より大きい解像度(載る範囲で)。結果は画像つきの spec に並べる。
6. **文書**: docs/dekahamuntu-setup.md・docs/ai-server-placement.md・docs/machines.md(要れば)に、構成・計測・戻し方を書く。

## 進め方

- この issue では、dekahamuntu の実機での操作(ComfyUI の更新・再起動、ファイルの取得、拡張の導入、qwen38.service の設定の書き換えと再起動、計測のための生成)をしてよい(本人の依頼)。sudo が要る操作、home-manager switch、push は、やらずに止まって聞く。
- ComfyUI を止める・起動し直すのは、キューが空で、art-studio に実行待ち・実行中のループがないのを確かめてから。計測の絵は art-studio が取り込まない形で出し(PreviewImage か inbox の外)、終わったら自分が作ったものだけ消す。
- 計測の絵は当たり障りのないもの(風景・静物など)。
- chibihamuntu は触らない(読むだけ)。
- 実機に入れた値は、このリポジトリのホストの設定(`hosts/ubuntu/dekahamuntu.env`)とスクリプトから同じものを作り直せること。dekahamuntu の `~/.config/nix-config` は develop にいる。値は環境変数で渡すか、取り込みのあとで本人が pull する(作業ツリーを勝手に書き換えない)。
- モデルのファイルと拡張の正本は chibiham-ai のリポジトリにある(dekahamuntu の `~/ai`): モデルは `models.lock.toml`(`scripts/models scan / resolve / restore / check`。取得元の URL と sha256)、拡張は `comfyui/custom-nodes.snapshot.json`、ワークフローは `comfyui/workflows/`。この issue では、比べるためのファイル・拡張を実機に直接入れてよいが、**何を・どこから・どの版で入れたか(URL、revision、sha256、拡張の commit)を報告と docs に残す**。台帳・拡張の一覧・ワークフロー・art-studio のレシピへの書き込みは chibiham-ai#74(この issue が済んでから始まる)でやるので、`~/ai` のリポジトリは書き換えない。比べ終わって使わないと決めた版のファイルは、消してよいかを報告に書く(勝手に消さない)。
- art-studio のレシピ(`~/ai` のワークフロー)は chibiham-ai#74 で作る。エージェント用のスキルは、この issue では作らない。ComfyUI の画面から使えるワークフローを1つ保存するところまで(保存先は ComfyUI の user のフォルダ。`~/ai` のリポジトリに commit しない)。
- 2026-11-14 に入れたケースファンの制御(fan2go)が動いている。2枚の GPU に負荷がかかるので、計測のあいだ温度と fan2go の状態を見て、83℃ を超える・failsafe になる・fan2go が落ちる、があれば止めて報告する。

## 作業ログ

- 2026-11-15 02:19 [me] 完了条件の案を有効にした(ゴールのタスクにした)
- 2026-11-15 02:28 [agent] 着手。実機で確かめた: (1) art-studio のループ 227 が実行中(残り約 400 組、1 組 約 15 秒)なので ComfyUI はまだ止めていない。終わるのを待つ (2) ComfyUI 0.45 系の本体に Select CLIP Device(gpu:N)があり、第三者の拡張なしで B が組める。上げる先は v0.45.2(v0.45.3 は公開から72時間未満) (3) 手元の NVFP4 のテキストエンコーダーは Comfy-Org/MiniMax-H3-Image のものと sha256 が同じ (4) llama-server 0.6.0 の Router で --sleep-idle-seconds が効く(別ポートの試験: 放置 45 秒で GPU 1 が 14,474 → 166MiB、次の問いで約 11 秒で戻る)。本番の Router に約 7 時間載ったままだった Uncensored 版は降ろした (5) 公式に 12.5GB の w4a8 版(minimax_h3_image_pruned_w4a8)があるので比べる対象に足す。スクリプトの変更はサブエージェントに依頼中
- 2026-11-15 02:40 [agent] ファイルの取得が済んだ(公式 int8・w4a8・VAE、第三者の GGUF Q5_K_M・Q4_K_M。revision 固定、5 つとも sha256 一致。手元の NVFP4 のテキストエンコーダーも sha256 一致)。本番に触れない写し(~/issue5-stage、GPU 1 だけ、port 4560、v0.45.2)で先に確かめた: 本番の freeze から venv を作り直すと freeze が一致(uv は --index-strategy unsafe-best-match が要る)、拡張は全部読み込めた(IMPORT FAILED なし)、H3 Image は NVFP4 のテキストエンコーダーで 2048² が出た。1 枚の GPU で入れ替える形(A)の粗い値(ループが GPU 0 で回っている最中): int8 は 1 枚目 約 24 秒、プロンプトを変えた 2 枚目 12〜15 秒、変えないと約 10 秒。w4a8 もほぼ同じ。GGUF Q5_K_M は 46 / 41 / 35 秒で 3 倍以上遅い。B の得は 1 枚あたり数秒の見込み(正式な計測はループが済んでから)
- 2026-11-15 03:06 [agent] スクリプトを agent/5 に入れた(5d44e65・84a3b15。update-comfyui の版の固定・控え・--restore、install-comfyui --unit-only、install-minimax-h3-image、QWEN_SLEEP_IDLE_SECONDS、ai-mode image-dual)。写しで確かめた: (1) 新しい update-comfyui で e3bee7ff → v0.45.2 → --restore で戻すと、commit と freeze が本番と一致 (2) 主なレシピ 5 つが v0.45.2 で出て、SDXL・Anima・Anima 2.9B・Qwen-Image は前の版と PNG がバイト単位で同じ、MOSS は差の平均 0.2/255・最大 7(上流の MOSS の変更。見た目は同じ) (3) 1 枚の GPU の形(A)の粗い値: int8 2048² は 1 枚目 21 秒・プロンプト替え 13〜15 秒・替えなし 10 秒、w4a8 は 17 / 12.5 / 10 秒、GGUF Q5 は 46 / 40 / 35 秒、Q4 は 44 / 37 / 32 秒。4096² は int8 60 秒・w4a8 51 秒 (4) 取り合い: LLM が GPU 1 に載っているとき H3 Image は 1 秒で OutOfMemoryError、ComfyUI が GPU 1 を使っているとき LLM は 1 秒で HTTP 500「failed to load」(Router は落ちない)。本番の qwen38.service には --sleep-idle-seconds 600 をスクリプトで入れた(unit の差はその 1 行だけ)。本番の ComfyUI は、本人が art-studio のループ(231、残り約 310 組)を回しているのでまだ触っていない
- 2026-11-15 03:32 [agent] 待ち: 本番の ComfyUI の更新・GPU 2 枚への切り替え・A/B の計測は、art-studio のループ(231 と 233、残り約 1,000 組、いまの速さで 3〜4 時間)が済み、10 分静かになってから始める(起動し直しが 2 回、計測に 20〜30 分、そのあいだ本番の ComfyUI を使う)。早く進めたいときはループを止めてもらえれば、静かになって 10 分で始める。それまでに済んだこと: 本番の Router で --sleep-idle-seconds 600 を確かめた(問いのあと 600 秒で sleeping、GPU 1 が 14,903 → 299MiB、次の問いは 8 秒)。install-minimax-h3-image-ubuntu.sh を実機で流し、置いたファイル 5 つの sha256 一致と、新しい場所への取得(29GB、85 秒)を確かめた。文書の 1 回目(未 commit)と、画面用のワークフローの JSON(未配置)ができている
