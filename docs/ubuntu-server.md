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

Home Managerだけを再適用する場合:

```bash
nix run ~/.config/nix-config#home-manager -- switch --flake ~/.config/nix-config#$USER@ubuntu-server
```

`bootstrap-ubuntu.sh`はsshdを有効化するが、UFWは自動で有効化しない。先にLANまたはTailscale経由のSSH接続を別端末から確認する。ファイアウォールを使う場合は、現在の接続経路を許可してから有効化する。

## 管理境界

| 対象 | 管理方法 |
|---|---|
| CLI、Zsh、Neovim、mise | Nix / Home Manager |
| Python、Node.js | mise |
| sshd、Tailscale daemon | apt / systemd |
| NVIDIAドライバ | Ubuntuの推奨ドライバ |
| ComfyUIとPython依存 | ComfyUI専用venvまたはuv環境 |

GUIなしでもTailscaleは使える。`sudo tailscale up`が表示するURLをMacのブラウザで開いて認証する。CodexやClaude Codeも同様に、SSHセッションへ表示されたURLをMac側で開く方式を使える。
