# Ubuntu機ごとの設定（scripts用）

`scripts/*-ubuntu.sh` は `scripts/lib/ubuntu-host.sh` を読み、ホスト名（`UBUNTU_HOST`、なければ `hostname -s`）と同じ名前の `<ホスト名>.env` をここから読む。
ファイルがないホストでは、chibihamuntu と同じ既定値で動く。

Nix（Home Manager）の側のホストの違いは `flake.nix` と `home/hosts/<ホスト名>.nix` に書く。ここは命令的なスクリプトの設定だけ。

| ファイル | マシン |
|---|---|
| `chibihamuntu.env` | Intel i7-13700KF / RTX 3090 24GB ×1 / DDR4 64GB |
| `dekahamuntu.env` | AMD Ryzen / RTX 5060 Ti 16GB ×2 / DDR5 64GB |
| `dekahamuntu-netplan.yaml.example` | dekahamuntu のネットワークの雛形（実機のNIC名を確かめてから使う） |

書き方は `: "${VAR:=値}"`。呼び出し側の環境変数が優先されるので、一度だけ変えたいときは `COMFY_CUDA_DEVICES=1 scripts/install-comfyui-ubuntu.sh` のように渡す。

## 変数

| 変数 | 既定 | 使うスクリプト | 意味 |
|---|---|---|---|
| `FLAKE_HOST` | `ubuntu-server` | bootstrap-ubuntu | `homeConfigurations."$USER@<FLAKE_HOST>"` |
| `OP_VAULT` | `chibihamuntu` | bootstrap-ubuntu | このマシン専用の1Password Vault（表示と照合。参照の正本は `home/hosts/<ホスト>.nix` の `chibiham.ubuntu.opVault`） |
| `UBUNTU_USER` | 空 | bootstrap-ubuntu | このホストのユーザー。`$USER` と違えば止まる（bootstrap はこれが空でも止まる） |
| `TAILSCALE_HOSTNAME` | 空 | install-tailscale | `tailscale up --hostname` に渡す名前（空ならOSのホスト名） |
| `TAILSCALE_SERVE` | 空 | configure-tailscale-serve | tailnet内のHTTPS公開。「HTTPSのポート=127.0.0.1のポート」を空白区切り（例: `443=8188 4520=4520`）。一覧にないServeは `--prune` のときだけ外す |
| `NVIDIA_EXPECTED_GPUS` | `0` | install-nvidia-driver | 期待するGPUの枚数（0は確かめない） |
| `NVIDIA_REQUIRE_OPEN` | `0` | install-nvidia-driver, install-hwe-kernel, check-nvidia-kernel-modules | `nvidia-driver-*-open` 以外を拒む（Blackwellは1） |
| `NVIDIA_MIN_DRIVER` | `0` | install-nvidia-driver | 推奨ドライバの世代の下限（Blackwellは570） |
| `GPU_LED_OFF` | `1` | configure-ubuntu-hardware | 0ならGPU LEDの消灯を入れない |
| `GPU_LED_MATCH` | `gigabyte.*rtx ?3090` | turn-off-gpu-led | OpenRGBの一覧の行（小文字）に当てる正規表現 |
| `GPU_LED_COUNT` | `1` | turn-off-gpu-led | 一致すべき台数。違えば何も変えずに失敗 |
| `CPU_POWER_READ` | `1` | configure-ubuntu-hardware | 0ならpowercap（RAPL）の読み取り権限を入れない |
| `CASE_FAN_CONTROL` | `0` | configure-ubuntu-hardware, install-case-fan-control | 1ならケースファンをGPU（とCPU）の温度で回す（fan2go）。0なら入れない（入れたものは `--uninstall` で外す） |
| `CASE_FAN_MODULE` | `nct6775` | install-case-fan-control | Super I/O のドライバ。`/etc/modules-load.d/case-fan-control.conf` に書いて起動のたびに読み込む |
| `CASE_FAN_HWMON` | 空 | install-case-fan-control | 操る hwmon の name（例: `nct6799`）。同じ name が2つあれば止まる |
| `CASE_FAN_CHANNELS` | 空 | install-case-fan-control | 操る pwm のチャネル（空白区切り。fan の番号が違えば `pwm:rpm`、例 `2 3` / `2:4`）。CPU_FAN は入れない |
| `CASE_FAN_MIN_DUTY` | `30` | install-case-fan-control | 最低のデューティ（%、10〜100）。止めない（3pin のファンは高めにする） |
| `CASE_FAN_GPU_CURVE` | `45:30 60:45 70:65 78:85 83:100` | install-case-fan-control | GPU の温度（全 GPU の最大、℃）→ デューティ（%）。最初の点より下は最初の値、最後の点より上は最後の値。最後の温度は 100℃ 未満、最後の点は 100%（GPU が読めないときに全開にするため。そうでなければ入れるスクリプトが止まる） |
| `CASE_FAN_CPU_CURVE` | 空 | install-case-fan-control | CPU の温度 → デューティ。ケースファン = max(GPU, CPU)。空なら GPU だけ |
| `CASE_FAN_CPU_HWMON` | `k10temp` | install-case-fan-control | CPU の温度の hwmon の name（Intel なら `coretemp`） |
| `CASE_FAN_CPU_TEMP_CHANNEL` | `1` | install-case-fan-control | `temp<N>_input` の N（k10temp の 1 は Tctl） |
| `CASE_FAN_RAD_CHANNELS` | 空 | install-case-fan-control | ラジエーターの組: CPU の簡易水冷のラジエーターのファンの pwm のチャネル（書き方は `CASE_FAN_CHANNELS` と同じ。`CASE_FAN_HWMON` の中）。ケースファンとは別の曲線で、ファン = max(GPU, CPU[, CPU の保険])。空なら組を使わない（設定はケースファンだけで、出力は組を足す前と同じ）。`CASE_FAN_CHANNELS` と重なれば止まる。BIOS が全開（BIOS のモード `pwmN_enable` が 0）・SmartFan IV（5）でないチャネルは入れられない（止まる。モードは、いまが 1 なら `/etc/fan2go/case-fan-restore.conf` の記録で見る）。組から外したチャネルは、入れ直しのときに記録の値（BIOS の制御）へ戻してから記録を書き直す（戻せなければ止まる）。chibihamuntu は 2026-11-15 22:59 JST から `2` で試し、2026-11-16 に空へ戻した（ほかの `CASE_FAN_RAD_*` は試した値のまま。env では `:=` でなく `=` で書き、`CASE_FAN_RAD_CHANNELS=2` を渡せば組ありの設定を見られる） |
| `CASE_FAN_RAD_MIN_DUTY` | `20` | install-case-fan-control | ラジエーターのファンの最低のデューティ（%、10〜100）。止めない |
| `CASE_FAN_RAD_GPU_CURVE` | 空 | install-case-fan-control | ラジエーターのファンの GPU の曲線（組を使うなら必須）。決まりは `CASE_FAN_GPU_CURVE` と同じ（最後の温度は 100℃ 未満、最後の点は 100%） |
| `CASE_FAN_RAD_CPU_CURVE` | 空 | install-case-fan-control | ラジエーターのファンの CPU の曲線（組を使うなら必須。CPU のクーラーのファンを CPU の曲線なしで操らせない）。最後の点は 100%。温度の源が BIOS と同じ（`CASE_FAN_RAD_CPU_HWMON` が `CASE_FAN_HWMON` と同じで、`pwmN_temp_sel` が `CASE_FAN_RAD_CPU_TEMP_CHANNEL` と同じ）なら、sysfs の BIOS の曲線（`pwmN_auto_pointM_temp`・`_pwm`）と両方の点の温度の全部で比べ、1 か所でも BIOS より小さければ止まる（BIOS の曲線が同じ温度に 2 点以上ある段差では、その温度で高いほうと比べる）。源が違う・BIOS の曲線がないときは注意を出して進める。比べる前に BIOS のモードを見て、全開・SmartFan IV でない・分からないチャネルは止まる |
| `CASE_FAN_RAD_CPU_HWMON` | 空 | install-case-fan-control | ラジエーターの CPU の曲線の温度の hwmon の name（BIOS と同じ源を指せるように、`CASE_FAN_CPU_HWMON` とは別。chibihamuntu は `nct6798`） |
| `CASE_FAN_RAD_CPU_TEMP_CHANNEL` | 空 | install-case-fan-control | その `temp<N>_input` の N（chibihamuntu は `9`。`pwm2_temp_sel=9`） |
| `CASE_FAN_RAD_CPU_BACKUP_CURVE` | 空 | install-case-fan-control | 任意。別の温度の源での保険の CPU の曲線（主の源が固まった・0 を返すようになったとき用）。あれば最後の点は 100%。空なら使わない |
| `CASE_FAN_RAD_CPU_BACKUP_HWMON` | 空 | install-case-fan-control | 保険の曲線の温度の hwmon の name（保険の曲線があるときは必須。曲線が空なのにこれがあれば止まる） |
| `CASE_FAN_RAD_CPU_BACKUP_TEMP_CHANNEL` | 空 | install-case-fan-control | その `temp<N>_input` の N |
| `CASE_FAN_ACPI_LAX` | `0` | install-case-fan-control | 1なら GRUB に `acpi_enforce_resources=lax` を足す（`/etc/default/grub.d/60-case-fan-acpi-lax.cfg`。再起動が要る）。0 に戻して流すと外す |
| `COMFY_CUDA_DEVICES` | 空 | install-comfyui | comfyui.serviceの `CUDA_VISIBLE_DEVICES`。複数を書くと最初のGPUが既定のデバイス（`cuda:0`）になり、ほかのGPUはノード（`Select CLIP Device` など）で指定したときだけ使われる（dekahamuntu は `0,1`。GPU 1 は H3 Image のテキストエンコーダーの計算だけに使い、重みは RAM に置かれる） |
| `COMFY_REF` | 空 | update-comfyui, install-comfyui | ComfyUIの版（タグかcommit）。update-comfyui が `git checkout --detach` する（`--ref` が優先）。空なら `git pull --ff-only`（master）。install-comfyui は新しく clone するときだけ使う |
| `H3_IMAGE_MODELS` | 空 | install-minimax-h3-image | 置く MiniMax H3 Image の DiT の版（空白区切り: `int8` `w4a8` `gguf-q5` `gguf-q4`）。空で引数もなければ何もしない。dekahamuntu は `int8 w4a8`（GGUF は約 3 倍遅く、第三者の重みと拡張なので入れない） |
| `ART_STUDIO_COMFYUI_URL` | 空 | configure-art-studio | art-studio の unit の drop-in に書く `COMFYUI_URL`（空なら書かない）。ComfyUI が 2 つ以上あるホストでは `,` で並べ、1 つ目が主（dekahamuntu は `http://127.0.0.1:8188,http://127.0.0.1:8189`。並べた値を読むのは chibiham-ai の issue 96 の art-studio から） |
| `ART_STUDIO_CUDA_DEVICES` | 空 | configure-art-studio | art-studio（モザイクの YOLO）の `CUDA_VISIBLE_DEVICES`（空なら書かない） |
| `COMFY_EXTRA_ARGS` | 空 | install-comfyui | comfyui.serviceの main.py に足す起動オプション（例: `--fast fp16_accumulation`。どちらのホストも付けない）。2 つ目以降の常駐にも同じものを足す |
| `COMFY_EXTRA_INSTANCES` | 空 | install-comfyui, update-comfyui, install-qwen38 | 2 つ目以降の ComfyUI の常駐。「名前:ポート:見せるGPU」を空白区切り（dekahamuntu は `gpu1:8189:1`）。install-comfyui が `comfyui-<名前>.service` を書いて enable する（`127.0.0.1:<ポート>`、`CUDA_VISIBLE_DEVICES=<GPU>`、`--temp-directory <ComfyUI>/temp-<名前>`、ComfyUI-Manager なし。置き場は comfyui.service と同じ）。update-comfyui は全部の常駐のキューを確かめて全部を起こし直す。install-qwen38 は GPU が重なる常駐を qwen38-dual.service の `Conflicts=` に入れる。空なら作らない（unit も出力も今までと同じ）。外すときは設定から消して `install-comfyui-ubuntu.sh --remove <名前>` |
| `LLM_CUDA_DEVICES` | 空 | install-qwen38 | qwen38.serviceの `CUDA_VISIBLE_DEVICES` |
| `LLM_DUAL_CUDA_DEVICES` | 空 | install-qwen38 | 空でなければ、束ねて使う qwen38-dual.service を作る |
| `LLM_DUAL_SPLIT_MODE` | `layer` | install-qwen38 | llama.cppの `--split-mode` |
| `LLM_DUAL_TENSOR_SPLIT` | 空 | install-qwen38 | llama.cppの `--tensor-split`（各GPUへの層の比。dekahamuntu は `39,10`）。n-cpu-moe を使うモデルでは重い層が後ろに固まるので、半々（`1,1`）にすると後ろのGPUに寄る。n-cpu-moe を変えたら合わせて変える。Router の全部のモデルに同じ値が効く |
| `TRAIN_CUDA_DEVICES` | 空 | install-diffusion-pipe | 学習スクリプトの `CUDA_VISIBLE_DEVICES` と `--num_gpus` |
| `APPLIO_CUDA_DEVICES` | 空 | install-applio | applio.serviceの `CUDA_VISIBLE_DEVICES` |
| `APPLIO_CONFLICTS` | `comfyui.service qwen38.service` | install-applio | applio.serviceの `Conflicts=` |
| `QWEN_WANTED_BY` | `comfyui.service` | install-qwen38 | qwen38.serviceを何と一緒に起動するか |
| `QWEN_STOP_COMFY_ON_INSTALL` | `1` | install-qwen38 | 導入時にComfyUIを止めるか |
| `QWEN_SLEEP_IDLE_SECONDS` | 空 | install-qwen38 | 空でなければ qwen38.service・qwen38-dual.service の llama-server に `--sleep-idle-seconds <値>` を付ける（その秒数だけ使われなかったモデルを sleeping にしてVRAMを空け、次の要求で戻す）。dekahamuntu は `600`（本番で GPU 1 14,903 → 299MiB、次の問いは 8 秒） |
| `QWEN_INSTALL_27B` | `1` | install-qwen38 | Qwen3.8-27B（dense）を取得するか |
| `QWEN_FLASH_N_CPU_MOE` など | 38 / 35 | install-qwen38 | Flash-Nextのエキスパートを置くRAMの層数 |

`CUDA_VISIBLE_DEVICES` を書くときは、番号を `nvidia-smi` と揃えるため `CUDA_DEVICE_ORDER=PCI_BUS_ID` も書く。

`sudo` で自分を起動し直すスクリプト（configure-ubuntu-hardware、install-hwe-kernel、install-gpu-led-off、install-rapl-power-access、install-case-fan-control）では、呼び出し側の環境変数は落ちる。値はこのファイルに書く。install-case-fan-control の `--identify` は、`CASE_FAN_HWMON` が空なら pwm のある Super I/O の hwmon（1 つのときだけ）を使うので、値を書く前でも使える（`--identify <N> --stop` の止めるモードも同じ。BIOS の曲線が全点 255 のチャネルと、BIOS が全開にしている（`pwmN_enable` が 0）チャネルはポンプなどと見て、`--allow-pump` がなければ断る）。

新しいホストを足すときは、`<ホスト名>.env`、`home/hosts/<ホスト名>.nix`、`flake.nix` の `mkLinuxHome` のエントリの3つを足す（ADR 0002）。
