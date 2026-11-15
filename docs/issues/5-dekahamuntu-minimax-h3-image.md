---
status: doing
created: 2026-11-15
updated: 2026-11-15
assignee: agent
goal:
  - text: dekahamuntu の ComfyUI が 0.45.0 以上で動き、入っている拡張が読み込めて、art-studio が使う主なレシピ(SDXL・Anima・Anima 2.9B・Qwen-Image・MOSS)で1枚ずつ出るのを確かめてある。前の版へ戻す手順が文書にある
    done: true
  - text: dekahamuntu で MiniMax H3 Image が、テキストエンコーダーを GPU 1・本体を GPU 0 に載せた形で1枚出て、プロンプトを変えた2枚目で入れ替えが起きない(各 GPU の VRAM で確かめる)。今までのワークフローは GPU 0 のまま動く
    done: true
  - text: qwen38.service(Router)を止めずに同居できる。Flash-Next が GPU 1 に載っているときの扱い(自動で降ろす・前に降ろす・分かる形で失敗する)が決まっていて、実機で確かめてある
    done: true
  - text: A(GPU 0 だけで入れ替え)と B の秒数・VRAM・RAM、本体の版(公式 int8 と GGUF)の速さと絵の差を計った表があり、既定にする版とその理由が書いてある。結果の絵を画像つきの spec(docs/specs/5/<名前>/index.html)に並べる
    done: true
  - text: 実機に入れた設定が hosts/ubuntu/dekahamuntu.env とスクリプトから作り直せ、chibihamuntu の設定と挙動が変わっていない。構成・計測・戻し方が docs に書いてある
    done: true
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
- 2026-11-15 08:15 [agent] 完了条件 1 を済みにした: 本番の ComfyUI(v0.45.2、CUDA_VISIBLE_DEVICES=0,1。2026-11-14 22:30 UTC に install-comfyui-ubuntu.sh --unit-only で切り替え)で確かめた。B = 本体の Select CLIP Device(gpu:1)。公式 int8・2048² が 1 枚出て(35.3 秒)、プロンプトを変えた 2・3 枚目(16.3 / 11.0 秒)で GPU 0 の VRAM の最小が 15,470〜15,502MiB のまま(本体が降りない。同じ条件の A では 3,238〜3,654MiB まで下がって読み直し、20.4〜20.5 秒)。テキストエンコーダーは GPU 1 で計算する(エンコード中 GPU 1 の使用率 87%、memory.used の最大 1,594MiB)が、VRAM には常駐せず重みは RAM に置かれる(ComfyUI の RSS 約 24.5GB、終わると GPU 1 は 346MiB)— 0.45.2 の動きで、依頼の「GPU 1 に載せたまま」とはここが違う。w4a8 でも同じ(B 11.1〜11.2 秒、GPU 0 の最小 13,186MiB)。今までのレシピ 5 つ(SDXL・Anima・Anima 2.9B・Qwen-Image・MOSS)は 2 枚見せたあとも GPU 1 が 138MiB のまま(min=peak=after)で、絵は切り替え前と画素が同じ、秒数も同じ。計測は comfybench(1 秒おきの nvidia-smi)。記録は /tmp/issue5-work/prod.jsonl と trace
- 2026-11-15 08:16 [agent] 完了条件 2 を済みにした: 決めた扱い: Router は止めない。(1) 自動で降ろす = QWEN_SLEEP_IDLE_SECONDS=600(install-qwen38-ubuntu.sh で本番の unit に入れた。unit の差は --sleep-idle-seconds 600 の 1 行)。本番で確かめた: UD-Q3_K_XL に問い「2」が返り、570 秒まで loaded、600 秒で sleeping・GPU 1 が 14,903 → 299MiB、次の問い「5」は 8 秒。(2) 前に降ろす = ai-mode image-dual(nix に入れた。switch は本人。いまは /models/unload の curl で同じことを実機で確かめた)。(3) 載っていたら分かる形で失敗 = 本番の B の形で確かめた: Qwen が GPU 1 に載ったまま H3 Image(B)を続けて投げると、1 枚目は通ることがあるが(26.0 秒)次は 0.3〜5 秒で torch.OutOfMemoryError: Allocation on device 1(MiniMaxH3ImageConditioning)。Qwen は落ちず、あとの問いに答えた。逆向き(H3 Image のあとに Qwen)は何もしなくても読み込めて答えた(GPU 1 15,103MiB)。Qwen を載せたまま使う逃げ道の A の形(w4a8、GPU 0 だけ)は 4 枚とも通った(18.6〜21.3 秒)。記録は /tmp/issue5-work/coexist.log・coexist.jsonl
- 2026-11-15 08:22 [agent] 完了条件 0 を済みにした: 本番を 2026-11-14 22:27 UTC に update-comfyui-ubuntu.sh で v0.45.2(6e8488ef)へ上げた(9 秒で応答、/system_stats が comfyui_version 0.45.2)。拡張: journal に IMPORT FAILED 0 件(--enable-manager 付き)、/object_info に ChibihamRecipeAnima・ChibihamRecipeSDXL・ChibihamSaveImageMeta・MiniMaxH3ImageConditioning・SelectCLIPDevice。主なレシピ 5 つ(SDXL・Anima・Anima 2.9B・Qwen-Image・MOSS)を本番で更新前・更新後・GPU 2 枚のあとに 1 枚ずつ出し、SDXL・Anima・Anima 2.9B・Qwen-Image は画素が同じ(差の最大 0)、MOSS は更新の前後で差の平均 0.195/255・最大 7(見た目は同じ)。art-studio は / が 307 → /?st=inbox で 200。戻す手順は docs/ubuntu-server.md「ComfyUIの更新と戻し」と docs/dekahamuntu-setup.md 2-9「戻し方」(34f21f6。控えは ~/.local/state/comfyui-update/20261114T222702Z-e3bee7ffc)。戻しは先に写しで通した(更新 → --restore で commit e3bee7ff・freeze が本番と一致)
- 2026-11-15 08:22 [agent] 完了条件 3 を済みにした: 表: docs/ai-server-placement.md「実測(2026-11-14): MiniMax H3 Image」(34f21f6)と spec。本番で A/B × 公式 int8・w4a8 × 2048²・2880²・4096² を 32 回、GGUF Q5_K_M・Q4_K_M の A/B を写し(2 枚見せる形)で 16 回、写し(1 枚)で 24 回。2048² のプロンプト替え: int8 A 20.4〜20.5 秒 / B 11.0 秒、w4a8 A 12.0 / B 11.1、Q5 A 39.2〜43.1 / B 35.6、Q4 A 35.8 / B 32.7、種だけはint8・w4a8 が 9.7〜9.8。VRAM(GPU ごとの最小・最大・終わったあと)、ComfyUI の RSS(A 8〜13GB、B 23〜28GB)、MemAvailable、温度(最大 74℃、fan2go は全回 active)も表にある。既定は公式 int8 を B の形(理由: B なら w4a8 と同じ速さ、重みが 8bit、公式のテンプレートの版、第三者のものが要らない)、w4a8 は A 用に置く、GGUF は使わない(約 3 倍遅い・第三者の重みと拡張)と書いた(エージェントの決め。本人が絵を見て変えうる)。絵は spec docs/specs/5/h3-image/index.html(45MB、画像 146 枚。版ごとの絵と文字の切り出し、A と B の差、大きい絵、更新の前後)。ヘッドレスの Chrome で開いて見た
- 2026-11-15 08:22 [agent] 完了条件 4 を済みにした: 実機の設定は agent/5 のスクリプトと dekahamuntu.env(実機の ~/issue5-stage/nix-config に写したもの)で入れた: update-comfyui-ubuntu.sh(COMFY_REF=v0.45.2)、install-comfyui-ubuntu.sh --unit-only(COMFY_CUDA_DEVICES=0,1)、install-qwen38-ubuntu.sh(QWEN_SLEEP_IDLE_SECONDS=600)、install-minimax-h3-image-ubuntu.sh(H3_IMAGE_MODELS=int8 w4a8)。最後の版(160abe9)で流し直し: comfyui.service は「変わりません」、qwen38.service・qwen38-dual.service・preset は cmp で同じ、H3 のファイルは 4 つとも取得済み(--verify で sha256 一致も確かめた。新しい場所への取得も 29GB・85 秒で通った)。chibihamuntu: nix eval の drvPath は mac-mini・macbook・ubuntu-server が develop と同じで、変わるのは dekahamuntu だけ。にせのコマンドの環境で、変更の前後に install-comfyui・install-qwen38 を UBUNTU_HOST=chibihamuntu とファイルのないホスト名で流し、unit・preset が同じ(サブエージェントの確かめ)。update-comfyui-ubuntu.sh だけは chibihamuntu でも控え・キューの確かめ・起動の待ちが足される(文書に書いた)。chibihamuntu の実機には触っていない。構成・計測・戻し方は docs/dekahamuntu-setup.md 2-9、docs/ai-server-placement.md、docs/ubuntu-server.md(34f21f6)。bash -n 全部通過、TODO(issue 5) 0 件
- 2026-11-15 08:23 [agent] 実装レビュー開始。develop..agent/5 の4コミット、14ファイルを読む。コード・コミット・実機設定は変更せず、更新/復元・モデル取得・GPU/Router共存の正しさと要求充足を検証する。
- 2026-11-15 08:27 [agent] ホスト設定を実際にsourceして確認: dekahamuntu は v0.45.2/GPU 0,1/int8+w4a8/sleep 600、chibihamuntu と未登録ホストは追加値が空。Nix変更のLSP診断は問題なし。計測specと画像の存在、GPU/Router共存・更新前後の比較・戻し方の記載を確認。更新/復元と取得スクリプトの障害時の挙動を並行レビュー中。
- 2026-11-15 08:28 [agent] 不具合を再現: scripts/lib/comfyui.sh:16-18 は /queue の5秒タイムアウトを「停止中」と扱って成功(return 0)する。ローカルHTTPサーバーで実行中ジョブを含む応答を6秒遅らせて確認した。生存中でも応答の遅いComfyUIを更新/--unit-onlyが再起動でき、キュー空確認の安全条件を破る。実機サービスは変更していない。
- 2026-11-15 08:32 [agent] レビュー結論はREVIEW_NG、修正3件。(P1) update-comfyui:138 の復元コマンドがCOMFY_DIRと--no-restartを保持せず、写しの確認後に表示どおり実行すると本番~/ComfyUIを復元・再起動する。(P1) lib/comfyui:16-18 のキュー取得失敗が再起動許可になる。(P2) install-comfyui:177-179 はunit書換え後のdaemon-reload/restart失敗から再実行しても一致判定で成功し、未適用状態を回復しない。後2種類の更新経路も使い捨て環境の再現で確認。モデル取得担当は固定元データ・manifest互換性・正常/不一致時の挙動に修正必須の不具合なし。変更したshell6ファイルのbash -n通過。コード・コミット・実機設定は変更していない。
- 2026-11-15 08:32 [agent] 実装レビュー(gpt-6.1-sol)が終わった: 修正が必要な不具合は3件。
- 2026-11-15 08:33 [agent] 実装レビューの差し戻し(1/3)を受けた。指摘 3 件を直す: (1) 写しで流した update-comfyui の「戻すなら」に COMFY_DIR と --no-restart を引き継ぎ、控えに対象のディレクトリを残して別の場所への --restore は止める (2) キューの確かめは、つながらないときだけ「止まっている」とし、タイムアウト・HTTP の誤りでは止まる (3) --unit-only は適用の途中の印と is-active を見て、失敗のあと流し直せば続きから適用する。サブエージェントに依頼中
- 2026-11-15 08:43 [agent] レビューの指摘 3 件を直した(agent/5 の 6339c60。載せ直しで前の commit は fd80022・cb4a669・7c99324・84124be になっている)。(1) 「戻すなら」に COMFY_DIR(と COMFY_PORT)・--no-restart を引き継ぎ、控えに comfy_dir を残して、別の場所の控えでの --restore は何も変えずに止まる (2) キューの確かめは curl の終了コード 7(つながらない)のときだけ進み、タイムアウト(28)・HTTP の誤り(22)では止まる (3) --unit-only は適用の途中の印(~/.local/state/comfyui-update/unit-apply-pending)と is-active を見て、失敗のあと流し直すと続きから適用する。確かめ: にせのコマンドの試験 30 件 + 前からの 33 件が通過(本物の curl と 6 秒遅れるサーバーでも 28 で止まる)、bash -n・shellcheck、chibihamuntu と dekahamuntu の引数なしの unit・preset は変わらず、nix eval は 4 つとも変わらず。実機: 本番で --unit-only は「変わらず、動いています。何もしません」、写しで流した update の「戻すなら」に COMFY_DIR=…/issue5-stage/ComfyUI と --no-restart が入り、その控えを COMFY_DIR なしで --restore すると rc=1 で止まって本番の HEAD(v0.45.2)も控えのフォルダも変わらなかった
- 2026-11-15 08:44 [agent] 再レビュー開始。develop..agent/5 の5コミット（先頭2a661f2）・14ファイルを対象に、前回3指摘の修正と残る正しさの不具合を確認する。コード・コミット・実機設定は変更しない。
- 2026-11-15 08:46 [agent] 前回3指摘の修正を確認。隔離環境で、写しの復元案内は空白・引用符を含むCOMFY_DIRとCOMFY_PORT・--no-restartを保持し、別対象への復元は変更前にrc=1で停止。unitのrestart失敗後は印が残り、再実行でrestart・起動待ちが通って印が消える。実curlとローカルHTTPで、空キュー/接続拒否は許可、実行中/HTTP500/5秒タイムアウトは拒否することを確認した。実機は変更していない。
- 2026-11-15 08:48 [agent] 計測要件の未達を確認: docs/ai-server-placement.md:404-405 は GGUF Q5_K_M/Q4_K_M の2880²・4096²を「計っていない」と明記し、大解像度のA/B表と画像specもint8/w4a8のみ。依頼5の「int8・GGUF Q5/Q4を2048²とより大きい解像度で比較」のうちGGUFの大解像度比較が欠ける。実行時のコード不具合とは区別して最終報告する。
- 2026-11-15 08:50 [agent] 再レビュー完了（develop..agent/5、先頭2a661f2）。前回3件は修正済みで、更新/復元・unit適用・キューガードの隔離実行と変更shell6ファイルのbash -nが通過。モデル取得/Router/ai-modeに追加の具体的コード不具合なし。ただしGGUF Q5/Q4の2048²超でのA/B比較が未実施で、依頼5の明示要件未達が残るためREVIEW_NG。少なくとも1つの大解像度で読み込み込み/プロンプト変更・VRAM/RAM・画像（載らなければ失敗結果）を補う必要がある。コード・コミット・実機設定は変更していない。
- 2026-11-15 08:50 [agent] 実装レビュー(gpt-6.1-sol)が終わった: 前回の不具合3件は修正済み。追加の具体的なコード不具合は見つかりませんでしたが、明示要件の未達が1件残っています。
- 2026-11-15 08:51 [agent] 実装レビューの差し戻し(2/3): GGUF Q5_K_M・Q4_K_M の 2048² 超での A/B が抜けていた。2880² と 4096² を A/B で計り始めた(写しの ComfyUI を CUDA_VISIBLE_DEVICES=1,0 で起動: 絵の本体は GPU 1、テキストエンコーダーは GPU 0。本番の ComfyUI が使う GPU 0 を空けておくため。本番には拡張を入れない)。始める前に本番のキューとループが空なのを確かめた(最後のループは 22:14 UTC に済み)
- 2026-11-15 09:17 [agent] 完了条件 3 を済みにした: 差し戻し(2/3)で抜けを埋めた: GGUF Q5_K_M・Q4_K_M を 2880²・4096² でも A/B で計った(写しを CUDA_VISIBLE_DEVICES=1,0 で起動して 16 回。2026-11-14 23:51〜11-15 00:13 UTC。前後 32 回の確かめで本番のキューとループは空)。Q5: 2880² A 75.8(1 枚目)/ 69.8(替え)、B 67.4 / 65.5 秒、4096² は A・B とも 4 回とも KSampler の OutOfMemoryError(5〜8 秒)で載らない。Q4: 2880² A 67.4 / 65.9、B 66.9 / 62.4、4096² A 147.2 / 146.9、B 144.0 / 144.0 秒。VRAM・RAM・温度(最大 65℃)も記録。表は docs/ai-server-placement.md(a61ed85)、絵 12 枚と失敗の記録は spec docs/specs/5/h3-image/index.html(作り直して 58MB、画像 164 枚)。既定の判断は変わらない(公式 int8 を B、w4a8 を A 用、GGUF は使わない)
- 2026-11-15 09:18 [agent] 再々レビュー開始。develop..agent/5 の6コミット（先頭18fccf9）・14ファイルを対象に、前回のGGUF大解像度比較の補完、前々回3修正、残る正しさと要件充足を確認する。コード・コミット・実機設定は変更しない。
- 2026-11-15 09:22 [agent] 前回未達のGGUF比較は補完済み。docs/ai-server-placement.md:357-409にQ5/Q4の2880² A/B初回・替え、4096²のQ5 OOM 4回/Q4成功、VRAM/RAM・温度・fan2goを確認。画像specをChromiumで開き、追加12画像と比較表示を目視。実HTTPのキューガードは空/接続拒否を許可し、実行中/HTTP500/5秒タイムアウトを拒否。モデル取得の固定URL/revision/hashにも追加指摘なし。Routerアンロード完了待ちの挙動を追加確認中。
- 2026-11-15 09:24 [agent] 追加P2を確認: home/hosts/dekahamuntu.nix:83-84 の image-dual は /models/unload のHTTP成功で終了し、モデルがunloadedになるのを待たない。固定されたllama.cpp v0.6.0のserver-models.cpp:1267-1287/2144-2159はSTOPを非同期キューへ積んで即successを返し、子の終了後にunloadedへ変わる。対応する隔離HTTP環境で、停止を2秒遅らせるとimage-dualは0.331秒・rc=0で終了し、その時点でモデルはloaded（再照会なし）。直後のH3 B生成がGPU 1解放と競合する。実GPUでのこの競合/OOM再現はしていない。変更shell6ファイルのbash -nは通過。コード・コミット・実機設定は変更していない。
- 2026-11-15 09:25 [agent] 再々レビュー完了（develop..agent/5、先頭18fccf9）。前回のGGUF大解像度比較は画像込みで補完済み、前々回3修正も維持。新規P2 1件: ai-mode image-dualが非同期アンロードの完了を待たず成功するため、直後のH3 B生成がQwenのGPU解放と競合する。unloadedを確認してから成功し、確認不能/タイムアウトは失敗させる必要がある。判定REVIEW_NG。実機の生成・停止・設定変更、コード変更、コミットはしていない。
- 2026-11-15 09:25 [agent] 実装レビュー(gpt-6.1-sol)が終わった: 修正が必要な不具合が1件あります。前回のGGUF大解像度比較の不足と、それ以前の3指摘は解消済みです。
- 2026-11-15 09:25 [agent] 実装レビューの差し戻し(3/3): ai-mode image-dual が /models/unload の HTTP の成功だけで戻り、Qwen の子プロセスが降りきる前に H3 Image を投げると OOM になる競合が残る、との指摘。全部のモデルの status が unloaded になるまで待ち、Router に聞けない・上限を超えたときは失敗で終わる形に直す(サブエージェントに依頼中)。直したら、取り出した ai-mode を実機の Router で流して、戻った時点で GPU 1 が空いているかを確かめる
- 2026-11-15 09:32 [agent] 完了条件 2 を済みにした: 差し戻し(3/3)で「前に降ろす」の穴を直した(bbc1389): ai-mode image-dual は全部のモデルの status が unloaded になるまで待ち(上限 60 秒)、Router に聞けない・unload が失敗・上限を超えたときは終了コード 1。実機で確かめた: /models/unload は 0.005 秒で戻るがその時点では loaded のままで、GPU 1 が空いて unloaded になるのは約 1.3 秒後(指摘の隙間は実機にもあった)。直した ai-mode(nix から取り出した本文。差し替えは shebang と curl・jq のパスだけ)を実機の Router で流すと、UD-Q3_K_XL が載った状態(GPU 1 15,071MiB)から 1.0 秒で rc=0、戻った時点で status は全部 unloaded・GPU 1 は 304MiB。直後に H3 Image(B、w4a8)をプロンプトを変えて 2 枚投げて 2 枚とも通った(31.3 秒(読み込み込み)/ 11.2 秒)。何も載っていないときは「載っていません」で rc=0。にせの Router の試験(2 秒遅れ・降りない・応答しない・500・sleeping/loading)も通過、split・llm-dual・applio・stop・status の呼び出しは変更前と同じ。nix eval は dekahamuntu だけが develop と違う。実機の ai-mode 自体は home-manager switch(本人)まで古いまま
- 2026-11-15 09:33 [agent] 再レビュー開始。develop..agent/5 の7コミット（先頭dbb0673）・14ファイルを対象に、image-dualのアンロード完了待ちと前回までの修正、要件充足を確認する。コード・コミット・実機設定は変更しない。
- 2026-11-15 09:36 [agent] image-dualの修正を隔離HTTPで確認: 1.7秒遅れる非同期アンロードは2.5秒後・unloaded確認後にrc=0、sleeping/loadingも完了待ち。降りない・HTTP500・不正JSON・unload失敗はrc=1（8ケース）。実curlのキューガードも空/接続拒否は許可、実行中/500/5秒タイムアウトは拒否。変更shell6ファイルのbash -n、dekahamuntuのnix eval通過。実機は変更していない。
- 2026-11-15 09:37 [agent] 追加P2を隔離実行で確認: scripts/lib/comfyui.sh:27-28 は HTTP200 の {} や queue_running/queue_pending が null の応答を jq の length(null)=0 により空キューと誤認する。実curlで両方ともrc=0。使い捨てHOME・systemctlスタブで install-comfyui --unit-only を流すと、/queue={}でもdaemon-reload/restartまで実行しrc=0。キュー状態を確認できない応答は拒否すべき。実機がこの応答を返した事実や実ジョブ中断は確認していない。
- 2026-11-15 09:37 [agent] 再レビュー完了（develop..agent/5、先頭dbb0673）。前回のimage-dual非同期アンロード競合は修正済み。GGUF大解像度の比較も補完済み。追加P2 1件: キュー応答が {} / null の場合に空キューと誤認して再起動を許すため、両フィールドが配列である確認が必要。隔離実行で確認、判定REVIEW_NG。モデル取得・Qwen設定の担当範囲に追加指摘なし。変更shell6ファイルのbash -nとdekahamuntuのnix eval通過。コード・コミット・実機設定は変更していない。
- 2026-11-15 09:37 [agent] 実装レビュー(gpt-6.1-sol)が終わった: 修正が必要な不具合が1件あります。前回の `image-dual` のアンロード完了待ちは修正済みです。
- 2026-11-15 09:37 [agent] 返事待ち: TASK_DONE を受けたが、まだ develop に入れていない: 実装レビューで指摘があった。worktree /Users/chibiham/.subako/worktrees/nix-config/5 で直して commit し、TASK_DONE で返す: 修正が必要な不具合が1件あります。前回の `image-dual` のアンロード完了待ちは修正済みです。 1. **[P2] 不完全なキュー応答を「空」と誤認し、再起動を許可する** `scripts/lib/comfyui.sh:27–28` `/queue` が HTTP 200 で `{}` または `{"queue_running":null,"queue_pending":null}` を返すと、jq の `length(null) = 0` により「実行中0・待ち0」と判定します。キュー状態を確認できていないのに、更新・`--unit-only` が再起動へ進め…(自動の差し戻しが上限 3 回に達した)
- 2026-11-15 09:43 [agent] 執事からの差し戻し(キューの確かめが {}・null を「空」と読む)を直した(agent/5 の 9bcfe34。変えたのは scripts/lib/comfyui.sh だけ)。queue_running・queue_pending の両方が配列のときだけ数え、そうでなければ「応答を読めませんでした」で止まる(jq は type を確かめ、python3 は list でなければ失敗。--force は今のまま)。確かめ: にせの curl で {}・null 2 つ・片方 null・文字列・オブジェクト・[]・null・0 の 8 通りを jq と python3 の両方で流し、update と --unit-only が git・unit・restart に触らず終了コード 1(47 件通過。直す前は 6 件で進んでしまうのを再現)、空のキューは進み、実行中あり・壊れた JSON・curl の 28・22 は止まる。前からの試験 33 件 + 30 件も通過、bash -n・shellcheck。私も手元で {}・null・[] が jq・python3 とも rc=1、空のキューが rc=0 を確かめ、実機の本物の /queue は「キューは空です」(rc=0)、--unit-only は「何もしません」。実機の計測のやり直しはしていない
- 2026-11-15 09:43 [agent] 再レビュー開始。git log / git diff develop..agent/5 の8コミット（先頭c566754）・14ファイルを対象に、キュー応答の型検証と前回までの修正、要件充足を確認する。コード・コミット・実機設定は変更しない。
- 2026-11-15 09:48 [agent] 前回のキュー応答の型検証を確認: 実curl＋ローカルHTTPでjq/python3両経路の不正型・空・実行中/待ち、HTTP500・タイムアウト・接続拒否の27ケースが期待どおり。隔離HOMEで更新/--unit-onlyは{}・null・[]・実行中の8ケースを変更前に拒否。unitのrestart失敗後は印を残し、再実行で適用・起動待ち後に印を消す。抽出したimage-dualも非同期アンロード・sleeping/loading・失敗系8ケースが期待どおり。実機は操作していない。
- 2026-11-15 09:48 [agent] 再レビュー完了（develop..agent/5、先頭c566754）。前回の不完全なキュー応答の誤認は修正済み。以前の復元先・unit再実行・Router完了待ちの修正とGGUF大解像度比較も維持。モデル取得/ホスト既定値/文書の独立レビューに追加指摘なし。変更shell6ファイルのbash -n通過。追加の具体的な正しさの不具合・要件未達は見つからずREVIEW_OK。コード・コミット・実機設定は変更していない。

## エージェントの結果(2026-11-15 08:32)

実装レビュー(gpt-6.1-sol)

修正が必要な不具合は3件。

1. **[P1] 写し用の復元コマンドが本番を変更・再起動する**
   `scripts/update-comfyui-ubuntu.sh:138`
   `COMFY_DIR="$HOME/ComfyUI-test" scripts/update-comfyui-ubuntu.sh --ref v0.45.2 --no-restart` を実行すると、表示される復元コマンドには `COMFY_DIR` も `--no-restart` も残りません。そのコマンドをそのまま実行すると、写しではなく本番の `~/ComfyUI` のcommit・Python依存を変更し、`comfyui.service` を再起動します。復元案内にも対象ディレクトリと再起動方針を引き継ぐ必要があります。使い捨て環境で対象の取り違えとrestart呼び出しを再現。

2. **[P1] キュー取得のタイムアウトを「停止中」と扱い、再起動を許可する**
   `scripts/lib/comfyui.sh:16-18`
   ComfyUIが生成中でも、`/queue` の応答に5秒以上かかると成功（return 0）します。HTTP 500も同じ扱いです。その結果、更新・`--unit-only` は `--force` なしでも生成中のサービスを再起動できます。停止を確認できる場合以外は、取得失敗時に中止する必要があります。実行中キューを返すHTTP応答を6秒遅らせ、ガードが成功することを再現。

3. **[P2] unit適用に失敗した後、再実行しても未適用状態を回復しない**
   `scripts/install-comfyui-ubuntu.sh:177-179`
   unitを書き換えた後に `daemon-reload`・`restart` が失敗すると、新しいファイルだけが残ります。原因を解消して再実行しても、ファイル一致で成功終了し、古いGPU設定のまま、またはサービス停止状態のままになります。適用失敗時のロールバックなど、再実行で回復できる処理が必要です。初回restart失敗後、再実行が終了コード0・systemctl呼び出しなしになることを再現。

確認済み：変更したshell 6ファイルの `bash -n`、ホスト別設定の読み込み、Nix変更のLSP診断。コード・コミット・実機設定は変更していません。発見事項は作業ログに記録済み。

REVIEW_NG

## エージェントの結果(2026-11-15 08:50)

実装レビュー(gpt-6.1-sol)

前回の不具合3件は修正済み。追加の具体的なコード不具合は見つかりませんでしたが、明示要件の未達が1件残っています。

1. **[P2・要件未達] GGUF Q5/Q4の大解像度でのA/B比較が未実施**
   `docs/ai-server-placement.md:380–405`
   Q5_K_M・Q4_K_Mは2048²だけで、2880²・4096²は「計っていない」と明記されています。大解像度の比較表・画像specもint8/w4a8のみです。依頼5の比較を完了するには、両GGUFについて少なくとも1つの2048²超の解像度で、A/Bの初回・プロンプト変更後の時間、VRAM/RAM、画像を補う必要があります。載らなければ、その失敗結果を記録してください。これは実行時のコード不具合とは別の指摘です。

確認：復元先・`--no-restart`の保持、別対象への復元拒否、unit適用失敗後の再実行、実HTTPでのキューガード、変更shell 6ファイルの`bash -n`。コード・コミット・実機設定は変更していません。作業ログ記録済み。

REVIEW_NG

## エージェントの結果(2026-11-15 09:25)

実装レビュー(gpt-6.1-sol)

修正が必要な不具合が1件あります。前回のGGUF大解像度比較の不足と、それ以前の3指摘は解消済みです。

1. **[P2] `image-dual` がGPU解放前に成功終了する**
   `home/hosts/dekahamuntu.nix:83–84`（呼び出す処理は36–44行）

   QwenがGPU 1にロード済みの状態で `ai-mode image-dual` を実行すると、`/models/unload` のHTTP成功だけで終了します。しかし、固定されている[llama.cpp v0.6.0の実装](https://github.com/ggml-org/llama.cpp/blob/v0.6.0/tools/server/server-models.cpp#L1267-L1287)は、停止を非同期で依頼するだけで、子プロセス終了・VRAM解放を待ちません。

   そのため、直後にH3 ImageのBワークフローを投げると、GPU 1がまだQwenに占有され、エンコードがOOMになる競合が残ります。対象モデルの状態が `unloaded` になるまで確認し、確認不能・タイムアウト時は失敗終了する必要があります。

   **確認:** 上流と同じ非同期応答の隔離HTTP環境では、停止完了を2秒遅らせると、`image-dual` は0.331秒・終了コード0で戻り、モデルはまだ `loaded` でした。実GPUでの競合・OOMは再現していません。

確認済み：追加12画像の表示、GGUF大解像度の計測表・失敗記録、実HTTPでのキューガード、変更shell 6ファイルの `bash -n`。コード・コミット・実機設定は変更していません。作業ログ記録済み。

REVIEW_NG

## エージェントの結果(2026-11-15 09:37)

実装レビュー(gpt-6.1-sol)

修正が必要な不具合が1件あります。前回の `image-dual` のアンロード完了待ちは修正済みです。

1. **[P2] 不完全なキュー応答を「空」と誤認し、再起動を許可する**  
   `scripts/lib/comfyui.sh:27–28`

   `/queue` が HTTP 200 で `{}` または `{"queue_running":null,"queue_pending":null}` を返すと、jq の `length(null) = 0` により「実行中0・待ち0」と判定します。キュー状態を確認できていないのに、更新・`--unit-only` が再起動へ進めます。両フィールドが配列であることを確認し、不正な応答では中止する必要があります。

   **再現:** 実curlとローカルHTTPサーバーで両応答ともガードが終了コード0。使い捨てHOME・systemctlスタブで `--unit-only` を実行すると、`/queue` が `{}` でも `daemon-reload`・`restart` が呼ばれました。実機での不正応答・ジョブ中断は確認していません。

確認済み：Routerの非同期アンロード・失敗系8ケース、キューの正常／実行中／HTTP 500／タイムアウト、変更shell 6ファイルの `bash -n`、dekahamuntuの `nix eval`。コード・コミット・実機設定は変更していません。作業ログ記録済み。

REVIEW_NG
