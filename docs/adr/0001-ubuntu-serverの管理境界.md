# Ubuntu Serverの管理境界

- Status: Accepted
- Date: 2026-08-27

## Context

ComfyUI専用サーバーを再構築可能にしつつ、NVIDIA GPUに関するUbuntu向けの一般的な運用情報をそのまま利用したい。Macで利用中のHome Manager構成も再利用する。

すべてをNixへ寄せると管理方法は統一できるが、カーネル、OSサービス、GPUドライバまでHome Managerの責務に含めると、Ubuntu標準の診断・復旧手順との距離が大きくなる。

## Decision

- OSにはUbuntu Server 24.04 LTSを使用する
- CLIとdotfilesはNix/Home Managerで管理する
- PythonとNode.jsはmiseで管理する
- sshdとTailscale daemonはapt/systemdで管理する
- NVIDIAドライバはUbuntuの`ubuntu-drivers`で管理する
- NVIDIAドライバのバージョンはスクリプトへ固定せず、Ubuntuが推奨する署名済みパッケージへ追従する
- CUDA Toolkitをホストへ一律導入せず、ComfyUI/PyTorchのCUDA runtimeと分離する
- ComfyUIとPython依存は専用環境で管理する
- ComfyUIはlocalhostだけで待ち受け、Tailscale Serveでtailnet内だけにHTTPS公開する
- SSHポートフォワーディングはTailscale Serveを利用できない場合の代替手段とする
- ComfyUIはsystemd user serviceとして動かし、lingerでOS起動時から実行する

## Alternatives considered

### NixOS

再現性は高いが、GPUやComfyUIの問題をUbuntu向け情報で診断しにくくなるため採用しない。

### aptのみ

単純だが、MacとCLI環境を共有できず、ユーザー環境の再現性も弱くなるため採用しない。

### NVIDIA公式runfile

Ubuntuのカーネル更新とパッケージ管理から外れ、更新・削除・復旧が複雑になるため採用しない。

### ドライババージョンの固定

再現性は高まるが、新しいUbuntuカーネルとの互換性やセキュリティ更新を自分で追跡する必要がある。特定バージョンを要求する問題が発生するまではUbuntuの推奨へ追従する。

## Consequences

- Ubuntu標準の`nvidia-smi`、`ubuntu-drivers`、aptによる診断・更新が使える
- Home Managerの適用だけではOS全体を再構築できない
- 初期構築はOS別スクリプトを順番に実行する必要がある
- ドライバ導入後は再起動が必要だが、SSH接続を切断するためスクリプトから自動再起動しない
- tailnetのAccess Controlsを変更した場合、ComfyUIへのHTTPS通信も明示的な許可が必要になる
