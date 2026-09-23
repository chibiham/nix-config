# Ubuntu Serverセットアップ

ComfyUI専用機では、CLI環境をNix/Home Manager、OSサービスをapt/systemdで管理する。
NVIDIAドライバ、CUDA、ComfyUIはGPU装着後に追加する。

## 初回セットアップ

Ubuntuへログインし、HTTPSでこのリポジトリを取得する。

```bash
sudo apt-get update
sudo apt-get install -y git curl
git clone https://github.com/chibiham/nix-config.git ~/.config/nix-config
```

Nixを導入して一度ログインし直す。

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

その後、Ubuntu用bootstrapを実行する。

```bash
~/.config/nix-config/scripts/bootstrap-ubuntu.sh
~/.config/nix-config/scripts/install-tailscale-ubuntu.sh
```

## Claude Code

`bootstrap-ubuntu.sh`で[公式ネイティブインストーラ](https://code.claude.com/docs/en/quickstart)を使い、
Claude Codeを`~/.local/bin/claude`へ導入する。PATHはHome Managerで設定済み。
既存のUbuntu環境へClaude Codeだけを追加する場合:

```bash
curl -fsSL https://claude.ai/install.sh | bash
~/.local/bin/claude --version
claude
```

初回起動時は表示される案内に従って認証する。

## NVIDIAドライバ

GPUを装着した後、Ubuntuが推奨するドライバを導入する。

```bash
~/.config/nix-config/scripts/install-nvidia-driver-ubuntu.sh
sudo reboot
```

再起動後にGPU名、VRAM、ドライバを確認する。

```bash
nvidia-smi
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
```

スクリプトは既にドライバが正常動作していれば何も変更せず終了する。ドライバの導入後も自動では再起動しない。Secure Bootが有効な環境でMOK登録画面が出た場合は、再起動時に画面の指示に従う。

CUDA Toolkitはこの段階では導入しない。ComfyUI/PyTorchが必要とするCUDA runtimeは、ComfyUI専用Python環境で管理する。管理境界を決めた理由は [ADR 0001](adr/0001-ubuntu-serverの管理境界.md) を参照。

## HWEカーネルとGPU LED

HWEカーネルの追加と、GPU LEDの起動時消灯をまとめて反映する:

```bash
~/.config/nix-config/scripts/configure-ubuntu-hardware.sh
```

sudo認証が必要。スクリプトは再実行可能で、OSの再起動やNVIDIAドライバの再ロードは行わない。
LEDはその場で消灯し、カーネルの切り替えは次回の手動再起動時になる。
カーネル・OSサービスはこのリポジトリのスクリプトからapt/systemdで管理し、
`home-manager switch`のactivationには含めない。

### HWEカーネル

2026-09-10のクラッシュは、RTL8852BEの`rtw89_pci`で送信完了報告の番号を配列範囲外参照し、
NULL参照からカーネルパニックに至ったもの。
[CVE-2026-43213](https://ubuntu.com/security/CVE-2026-43213)の説明と一致し、
確認時点でUbuntu 24.04の標準6.8系は影響あり、HWE 7.0系は影響なしとされている。

カーネルだけを導入する場合:

```bash
# 現在のAPTキャッシュを使って依存関係を確認するだけ
~/.config/nix-config/scripts/install-hwe-kernel-ubuntu.sh --dry-run

# インストールする。再起動はしない
~/.config/nix-config/scripts/install-hwe-kernel-ubuntu.sh
```

`linux-generic-hwe-24.04`と、導入済みのNVIDIAドライバ世代に対応する
`linux-modules-nvidia-<世代>-generic-hwe-24.04`を追加する。
2026-09-10の環境ではHWE `7.0.0-31`とNVIDIA `595-open`。
HWEメタパッケージを使うため、以後の更新はUbuntuのHWEに追従する。
インストール時に動作中のカーネルとGPUモジュールを手動導入扱いにし、
`autoremove`で復旧用カーネルが削除されるのを防ぐ。パッケージ削除は許可しない。

後日、手動で再起動したら`uname -r`、`nvidia-smi`、Wi-Fi/SSH接続を確認する。
起動に問題があれば、本体でGRUBメニューの「Advanced options for Ubuntu」から残した6.8系を選ぶ。
メニューが非表示の場合は起動時にEsc（UEFI）またはShift（BIOS）で表示する。

### GPU LEDの起動時消灯

```bash
~/.config/nix-config/scripts/install-gpu-led-off-ubuntu.sh
systemctl status gpu-led-off.service --no-pager
journalctl -u gpu-led-off.service -b --no-pager
```

以前の`~/turn-off-gpu-led.sh`と同じOpenRGB `1.0rc3.1`を使う。
`~/OpenRGB.AppImage`があれば再利用し、なければ公式リリースから取得する。
どちらも固定SHA256で検証してから`/opt/openrgb-1.0rc3.1`へ展開する。

`systemd/gpu-led-off.service`がOS起動時にNVIDIAと`i2c-dev`をロードし、
`/usr/local/sbin/turn-off-gpu-led`を一度実行する。Gigabyte RTX 3090を名前で検出して
`Off`を設定し、機器番号・I2Cバス番号は固定しない。GPUが未検出・複数一致なら変更せず失敗し、
初期化遅延に備えてサービス側で再試行する。

root所有のsystem serviceとして動くため、SSHログインやユーザー領域の実行ファイルに依存しない。
I2Cデバイスを全ユーザーへ開放する設定も不要。OpenRGBの設定は`/var/lib/gpu-led-off`に分離する。
電源投入直後からサービス実行までの間は、GPU本体の既定の点灯状態になる場合がある。

## ComfyUI

NVIDIAドライバの再起動後、専用uv環境へComfyUIを導入する。

```bash
~/.config/nix-config/scripts/install-comfyui-ubuntu.sh
```

インストーラは次を行う。

- `~/ComfyUI`へ公式リポジトリをclone
- Python 3.12の`.venv`を作成
- NVIDIA向けPyTorchとComfyUI依存を導入
- PyTorchからRTX 3090とVRAMを確認
- `comfyui.service`をsystemd user serviceとして登録・起動
- lingerを有効にし、ログイン前から自動起動

ComfyUIは`127.0.0.1:8188`だけで待ち受ける。インストール後、Tailscale Serveを設定する。

```bash
~/.config/nix-config/scripts/configure-comfyui-tailscale-serve.sh
```

表示された`https://<hostname>.<tailnet>.ts.net`を、同じtailnetへ登録した端末から開く。`--bg`で登録したServe設定はTailscale daemonへ保存され、UbuntuやTailscaleの再起動後も復帰する。

Tailscale Serveはtailnet内だけの公開であり、インターネット公開するFunnelは使用しない。LAN全体へ公開する`--listen 0.0.0.0`も使用しない。tailnetのAccess Controlsを変更している場合は、接続元からUbuntuのHTTPSへの通信が許可されている必要がある。

Serveの状態:

```bash
sudo tailscale serve status
```

Serveを利用できない場合の代替として、SSHトンネルでも接続できる。

```bash
ssh -N -L 8188:127.0.0.1:8188 chibiham@<TAILSCALE_IP>
```

この場合はトンネルを開いたまま、ブラウザで <http://127.0.0.1:8188> を開く。

状態とログ:

```bash
systemctl --user status comfyui --no-pager
journalctl --user -u comfyui -f
```

ComfyUIを明示的に更新する場合:

```bash
~/.config/nix-config/scripts/update-comfyui-ubuntu.sh
```

モデルは自動取得しない。チェックポイントは`~/ComfyUI/models/checkpoints/`へ配置する。モデルごとにVAE、text encoder、diffusion modelなどの配置先が異なる場合は、そのモデルの公式手順に従う。

## Qwen3.8-27B

Home Manager設定を適用すると、CUDA対応llama.cppと、ComfyUI/Qwenを切り替える
`ai-mode`コマンドが導入される。Ubuntu管理のNVIDIAドライバから`libcuda`だけを
ユーザー領域へリンクするため、Nix製CUDAアプリのための追加sudo設定は不要。
その後、モデル取得とuser service作成を行う。

```bash
nix run ~/.config/nix-config#home-manager -- switch --flake ~/.config/nix-config#$USER@ubuntu-server
~/.config/nix-config/scripts/install-qwen38-ubuntu.sh
```

インストーラは、固定したリビジョンからQwen3.8-27B UD-Q4_K_M、UD-Q4_K_XLと
Qwen3.8-27B-Uncensored Q4_K_M、Uncensored-Heretic-v2 UD-Q4_K_XLを
`~/models/qwen3.8-27b/`へaria2で並列・再開可能な形で取得する。各モデルのVision Projectorも
取得してRouter presetで関連付け、画像入力を有効にする。
128K context、Q8 KV cache、単一モデルだけをVRAMへロードするRouterモードの
`qwen38.service`を作成する。内蔵Web UIでモデルを切り替えられ、再実行しても取得済みファイルは再取得しない。

RTX 3090を共有するため、`qwen38.service`と`comfyui.service`は排他的に起動する。

```bash
ai-mode qwen    # ComfyUIを止めてQwenを起動
ai-mode comfy   # Qwenを止めてComfyUIを起動
ai-mode stop    # 両方停止
ai-mode status  # 両サービスの状態
```

Qwenは再起動時に自動起動せず、既存のComfyUIを既定のままにする。APIは
`http://127.0.0.1:8080/v1`で待ち受ける。Tailscale接続済みの場合、内蔵Web UIは
HTTPS 8443番でもtailnet内限定で公開する。公開ポートは
`QWEN_TAILSCALE_HTTPS_PORT`で変更できる。

Home Managerだけを再適用する場合:

```bash
nix run ~/.config/nix-config#home-manager -- switch --flake ~/.config/nix-config#$USER@ubuntu-server
```

`bootstrap-ubuntu.sh`はsshdを有効化するが、UFWは自動で有効化しない。先にLANまたはTailscale経由のSSH接続を別端末から確認する。ファイアウォールを使う場合は、現在の接続経路を許可してから有効化する。

## 管理境界

| 対象 | 管理方法 |
|---|---|
| CLI、Zsh、Neovim、mise、llama.cpp | Nix / Home Manager |
| Codex CLI、Claude Code | Ubuntu用bootstrap / 公式インストーラ |
| Python、Node.js | mise |
| sshd、Tailscale daemon | apt / systemd |
| NVIDIAドライバ | Ubuntuの推奨ドライバ |
| HWEカーネル・対応NVIDIAモジュール | `scripts/install-hwe-kernel-ubuntu.sh` / apt |
| GPU LED消灯 | 固定版OpenRGB / systemd system service |
| ComfyUIとPython依存 | ComfyUI専用venvまたはuv環境 |
| Qwenモデル、Qwen user service | 専用の冪等インストールスクリプト |

GUIなしでもTailscaleは使える。`sudo tailscale up`が表示するURLをMacのブラウザで開いて認証する。CodexやClaude Codeも同様に、SSHセッションへ表示されたURLをMac側で開く方式を使える。
