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
| `NVIDIA_EXPECTED_GPUS` | `0` | install-nvidia-driver | 期待するGPUの枚数（0は確かめない） |
| `NVIDIA_REQUIRE_OPEN` | `0` | install-nvidia-driver, install-hwe-kernel, check-nvidia-kernel-modules | `nvidia-driver-*-open` 以外を拒む（Blackwellは1） |
| `NVIDIA_MIN_DRIVER` | `0` | install-nvidia-driver | 推奨ドライバの世代の下限（Blackwellは570） |
| `GPU_LED_OFF` | `1` | configure-ubuntu-hardware | 0ならGPU LEDの消灯を入れない |
| `GPU_LED_MATCH` | `gigabyte.*rtx ?3090` | turn-off-gpu-led | OpenRGBの一覧の行（小文字）に当てる正規表現 |
| `GPU_LED_COUNT` | `1` | turn-off-gpu-led | 一致すべき台数。違えば何も変えずに失敗 |
| `CPU_POWER_READ` | `1` | configure-ubuntu-hardware | 0ならpowercap（RAPL）の読み取り権限を入れない |
| `COMFY_CUDA_DEVICES` | 空 | install-comfyui | comfyui.serviceの `CUDA_VISIBLE_DEVICES` |
| `COMFY_EXTRA_ARGS` | 空 | install-comfyui | comfyui.serviceの main.py に足す起動オプション（例: `--fast fp16_accumulation`。どちらのホストも付けない） |
| `LLM_CUDA_DEVICES` | 空 | install-qwen38 | qwen38.serviceの `CUDA_VISIBLE_DEVICES` |
| `LLM_DUAL_CUDA_DEVICES` | 空 | install-qwen38 | 空でなければ、束ねて使う qwen38-dual.service を作る |
| `LLM_DUAL_SPLIT_MODE` | `layer` | install-qwen38 | llama.cppの `--split-mode` |
| `LLM_DUAL_TENSOR_SPLIT` | 空 | install-qwen38 | llama.cppの `--tensor-split` |
| `TRAIN_CUDA_DEVICES` | 空 | install-diffusion-pipe | 学習スクリプトの `CUDA_VISIBLE_DEVICES` と `--num_gpus` |
| `APPLIO_CUDA_DEVICES` | 空 | install-applio | applio.serviceの `CUDA_VISIBLE_DEVICES` |
| `APPLIO_CONFLICTS` | `comfyui.service qwen38.service` | install-applio | applio.serviceの `Conflicts=` |
| `QWEN_WANTED_BY` | `comfyui.service` | install-qwen38 | qwen38.serviceを何と一緒に起動するか |
| `QWEN_STOP_COMFY_ON_INSTALL` | `1` | install-qwen38 | 導入時にComfyUIを止めるか |
| `QWEN_INSTALL_27B` | `1` | install-qwen38 | Qwen3.8-27B（dense）を取得するか |
| `QWEN_FLASH_N_CPU_MOE` など | 38 / 35 | install-qwen38 | Flash-Nextのエキスパートを置くRAMの層数 |

`CUDA_VISIBLE_DEVICES` を書くときは、番号を `nvidia-smi` と揃えるため `CUDA_DEVICE_ORDER=PCI_BUS_ID` も書く。

`sudo` で自分を起動し直すスクリプト（configure-ubuntu-hardware、install-hwe-kernel、install-gpu-led-off、install-rapl-power-access）では、呼び出し側の環境変数は落ちる。値はこのファイルに書く。

新しいホストを足すときは、`<ホスト名>.env`、`home/hosts/<ホスト名>.nix`、`flake.nix` の `mkLinuxHome` のエントリの3つを足す（ADR 0002）。
