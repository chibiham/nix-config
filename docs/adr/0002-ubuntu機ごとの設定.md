# Ubuntu機ごとの設定

- Status: Accepted
- Date: 2026-11-11

## Context

2 台目の Ubuntu 機 dekahamuntu（AMD Ryzen / RTX 5060 Ti 16GB ×2 / DDR5 64GB）を足す。これまでのスクリプトと Home Manager の設定は、chibihamuntu（Intel / RTX 3090 ×1）1 台を前提に書かれていた（GPU の世代、LED の対象、GPU を 1 枚で排他にすること、1Password の Vault 名、`ubuntu-server` という Home Manager の名前）。

管理の境界（ADR 0001）は変えない。変えるのは、ホストごとに違う値をどこに置くか。

## Decision

- Home Manager の差は `flake.nix` の `mkLinuxHome` の引数（`hostModule`、`cudaCapabilities`）と `home/hosts/<ホスト>.nix` に置く。`home/linux.nix` は `chibiham.ubuntu.*` のオプション（`opVault`、`aiMode`）を持ち、既定は chibihamuntu の値にする
- 命令的なスクリプトの差は `hosts/ubuntu/<ホスト名>.env` に置く。スクリプトは `scripts/lib/ubuntu-host.sh` を読み、ホスト名（`hostname -s`、または `UBUNTU_HOST`）でファイルを選ぶ。ファイルの値は `: "${VAR:=値}"` の形で書き、呼び出し側の環境変数を優先する
- 既定値は chibihamuntu の挙動と同じにする。chibihamuntu の Home Manager の出力（`activationPackage` の drvPath）と、スクリプトが書く unit・設定ファイルは変えない
- `bootstrap-ubuntu.sh` だけは、ホストのファイルがない・ユーザーが違う・値が `TODO` のときに止まる（既定のまま別のマシンを chibihamuntu として入れないため）
- chibihamuntu の Home Manager の名前は `ubuntu-server` のまま残す（`~/ai` の手順などが参照している）。新しいホストはホスト名を名前にする
- GPU が複数あるホストでは、unit ごとに `CUDA_VISIBLE_DEVICES`（と `CUDA_DEVICE_ORDER=PCI_BUS_ID`）を書いて GPU を分けるのを既定にし、束ねる形（llama.cpp の分割）は別の unit（`qwen38-dual.service`）として選べるようにする

## Alternatives considered

### ホストごとにスクリプトを複製する

読みやすいが、直したときに片方だけ直す事故が起きる。採用しない。

### Nix（Home Manager）で unit まで宣言する

systemd user service は Home Manager でも書けるが、ComfyUI・Qwen の unit は今のスクリプトが作っており、移すと chibihamuntu の動いている形を作り直すことになる。ADR 0001 の境界も動く。今回はしない。

### ホストの値をすべて環境変数で渡す

スクリプトを流すたびに値を覚えておく必要がある。ファイルにすると、何で動いているかを読める。

## Consequences

- 新しい Ubuntu 機を足すときは、`hosts/ubuntu/<名前>.env`、`home/hosts/<名前>.nix`、`flake.nix` のエントリの 3 つを足す
- ホスト名を変えると、スクリプトが読む設定が変わる。`sudo` 越しでは呼び出し側の環境変数（`UBUNTU_HOST` など）が落ちるので、root で動くスクリプトはファイルの値だけで決まる
- CI の評価に dekahamuntu を足す
