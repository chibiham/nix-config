# dekahamuntu のセットアップ

dekahamuntu は chibihamuntu と同じく AI サーバーとして使う 2 台目の Ubuntu 機。管理の境界は chibihamuntu と同じ（[ADR 0001](adr/0001-ubuntu-serverの管理境界.md)）。ホストごとの差の持ち方は [ADR 0002](adr/0002-ubuntu機ごとの設定.md)。

| | chibihamuntu | dekahamuntu |
|---|---|---|
| CPU | Intel Core i7-13700KF | AMD Ryzen（型番は要確認。AM5） |
| マザーボード | — | ASUS ProArt B850-Creator WiFi か …WiFi Neo（型番は要確認） |
| GPU | RTX 3090 24GB ×1（Ampere、sm_86） | RTX 5060 Ti 16GB ×2（Blackwell、sm_120）。合計 32GB、NVLink なし |
| RAM | DDR4 64GB | DDR5 64GB |
| Home Manager | `chibiham@ubuntu-server` | `chibiham@dekahamuntu` |
| スクリプトの設定 | `hosts/ubuntu/chibihamuntu.env` | `hosts/ubuntu/dekahamuntu.env` |
| 1Password Vault | `chibihamuntu` | `dekahamuntu`（作る） |

セットアップは 2 段に分ける。

- **第1段**（本人がやる。この文書の前半）: Ubuntu を入れ、Nix・Home Manager・シークレット・エージェント（Claude Code、Codex）・Tailscale まで。GPU がなくても通る。終われば、Mac から `ssh chibiham@dekahamuntu` して、マシンの上で Claude Code を動かせる
- **第2段以降**（マシンの上のエージェントに任せる。後半）: NVIDIA ドライバ、HWE カーネル、ComfyUI、LLM、学習。sudo・再起動・ディスクの操作の前には、必ず本人に確かめる

---

## 第1段: 最初から Claude Code が動くまで

### 0. 始める前に本人が決めること・用意するもの

| 項目 | 既定（`hosts/ubuntu/dekahamuntu.env`） | 違うときに直す場所 |
|---|---|---|
| ホスト名 | `dekahamuntu`（Ubuntu のインストールで付ける） | ファイル名 `hosts/ubuntu/<名前>.env` と `flake.nix` |
| ユーザー名 | `chibiham` | `UBUNTU_USER` と `flake.nix` の `"chibiham@dekahamuntu"` |
| 1Password の Vault | `dekahamuntu` | `OP_VAULT` と `home/hosts/dekahamuntu.nix` の `chibiham.ubuntu.opVault` |
| Tailscale の名前 | `dekahamuntu`（`https://dekahamuntu.<tailnet>.ts.net`） | `TAILSCALE_HOSTNAME` |

用意するもの（値はどこにも書かない）:

1. **1Password**: Vault `dekahamuntu` を作り、chibihamuntu の Vault と同じ名前のアイテムを入れる
   - `CIVITAI_TOKEN`（credential フィールド）
   - `R2_CHIBIHAM_AI`（`access_key_id`・`secret_access_key`・`endpoint` フィールド）
   - `op inject` は参照先が 1 つでも欠けると全体が失敗するので、bootstrap の前に揃えておく。中身を chibihamuntu と同じにするか、dekahamuntu 用に分けた鍵にするかは本人が決める
2. **1Password の Service Account**: Vault `dekahamuntu` だけを読めるものを作る（[my.1password.com/developer/serviceaccounts](https://my.1password.com/developer/serviceaccounts)）。トークンは bootstrap の入力にだけ使う
3. **このリポジトリの変更が GitHub にあること**: bootstrap は GitHub から clone したリポジトリで動く。`feat/dekahamuntu` が develop・main に入るまでは、clone の後にその枝へ切り替える（下の 3.）

### 1. Ubuntu Server 24.04 LTS を入れる（本人、本体の画面で）

- インストーラは Ubuntu Server 24.04.x の最新の ISO を使う
- **有線 LAN が見えないとき**: 5GbE のチップ（Realtek RTL8126 の見込み）は GA カーネル 6.8 では動かないことがある。インストーラの起動メニューで HWE カーネルの項目を選ぶか、Wi-Fi で入れて後で直す（[ネットワーク](#ネットワーク) を参照）
- **ストレージ**: どのディスクに入れるか・パーティション・LVM は本人が画面で決める。この文書とスクリプトはディスクを消さない・フォーマットしない。エージェントにもさせない
  - 参考: chibihamuntu は 1.9TB の LVM に `/` 1 つ（モデル類で約 900GB 使用）。Windows の入った別の NVMe は触っていない
- Your name / server's name / username: サーバー名 `dekahamuntu`、ユーザー `chibiham`
- **OpenSSH server をインストールする** にチェック。「Import SSH key」で GitHub の `chibiham` を選ぶと、GitHub に登録した公開鍵が `~/.ssh/authorized_keys` に入る（Mac から鍵で入れる）
- 追加の snap は入れない

再起動したら、本体の画面で `ip -br addr` を見て LAN の IP を控える。

### 2. Mac から入り、Nix を入れる

```bash
ssh chibiham@<LANのIP>

sudo apt-get update
sudo apt-get install -y git curl
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
exit   # 一度ログアウトして、Nix の PATH を読み直す
```

### 3. リポジトリを取る

```bash
ssh chibiham@<LANのIP>
git clone https://github.com/chibiham/nix-config.git ~/.config/nix-config
# feat/dekahamuntu がまだ develop に入っていないあいだだけ:
git -C ~/.config/nix-config switch feat/dekahamuntu
hostname -s   # dekahamuntu と出ること（hosts/ubuntu/dekahamuntu.env を読むため）
```

### 4. bootstrap

```bash
~/.config/nix-config/scripts/bootstrap-ubuntu.sh
```

- 最初に、ホスト名・ユーザー・Vault を表示する。`hosts/ubuntu/<ホスト名>.env` がない、ユーザーが違う、値が `TODO` のままのときは、何もせずに理由を出して止まる
- Home Manager の初回の switch は、CUDA 版 llama.cpp（sm_120）を手元でビルドするので時間がかかる（chibihamuntu と同じ。GPU は要らない）
- **OP_SERVICE_ACCOUNT_TOKEN** を聞かれたら、上の Service Account のトークンを貼る（`~/.secrets/.env` に 600 で保存される）
- そのあと `update-secrets`、mise（Node.js・Python）、pnpm、Qwen Code、Pi、Codex CLI、Claude Code が入る
- 途中で失敗しても、原因を直して再実行すればよい（冪等）

### 5. Tailscale

```bash
~/.config/nix-config/scripts/install-tailscale-ubuntu.sh
```

表示された URL を Mac のブラウザで開いて認証する（認証キーは使わない）。`--hostname=dekahamuntu` で登録される。tailnet の管理画面で、鍵の期限（Key expiry）を切るかは本人が決める。

Mac から tailnet 経由で入れることを確かめる。

```bash
ssh chibiham@dekahamuntu
```

### 6. ログインし直して、エージェントにログインする

ログインシェルは bash のまま。Home Manager が `~/.bashrc`・`~/.profile`・`~/.bash_profile` を持ち、bash でも zsh と同じ PATH が通る（[ADR 0003](adr/0003-ubuntuのbashにもpathを通す.md)。元の Ubuntu 標準のファイルは bootstrap の `-b backup` で `~/.bashrc.backup` などに退避される）。ログインし直して、まず PATH を確かめる。

```bash
exit
ssh chibiham@dekahamuntu
which pnpm node              # 両方とも出ること
type -a pnpm | head -2       # 先頭が関数か …-safe-chain-shims/bin/pnpm（Safe Chain 経由）
bash -lc 'command -v pnpm'   # エージェントの経路。…-safe-chain-shims/bin/pnpm
exit
ssh chibiham@dekahamuntu 'command -v pnpm node'   # ssh の非対話。shim と mise の shim が出ること
```

```bash
ssh chibiham@dekahamuntu
claude --version && codex --version && node --version
echo "$CIVITAI_TOKEN" | head -c 4; echo   # シークレットが読めていれば先頭だけ出る
claude          # 表示された URL を Mac で開いてログイン
codex login     # 使うなら
```

ここまでで第1段は終わり。

**第1段で入るもの**: apt の基礎パッケージ、sshd、Nix と Home Manager の設定（CLI・zsh・Neovim・mise・CUDA 版 llama.cpp・`ai-mode`）、1Password の Service Account とシークレット、Node.js・Python、pnpm、Qwen Code、Pi、Codex CLI、Claude Code、Tailscale。

**第1段で入らないもの**: NVIDIA ドライバ、HWE カーネル、GPU LED、CPU 電力の読み取り権限、ComfyUI、Qwen（llama.cpp のサービス）、diffusion-pipe、Applio、`~/ai`（private repo）とモデル、ネットワークの固定設定。

---

## 第2段以降: マシンの上のエージェントに任せる

`ssh chibiham@dekahamuntu` で入り、`cd ~/.config/nix-config && claude` で起動して、下の指示を順に渡す。

エージェントに守らせること（どの指示にも付ける）:

- **ディスクの消去・フォーマット・パーティションの変更はしない**（本人が行う）
- sudo が要る操作、再起動、サービスの停止は、実行する前に本人に確かめる。再起動は本人が行う
- 秘密（トークン・鍵・パスワード）を入力・保存しない
- 恒久的な変更はこのリポジトリのスクリプトか Nix の設定に入れる（その場限りの `apt install`・unit の手編集で終わらせない）。変更はコミットまでで、push は本人に確かめる

### 2-1. NVIDIA ドライバ

> docs/ubuntu-server.md の「NVIDIAドライバ」の章と docs/dekahamuntu-setup.md の「GPU」の節に従って、`scripts/install-nvidia-driver-ubuntu.sh` で入れて。このホストは RTX 5060 Ti ×2（Blackwell）なので、オープンカーネルモジュール版（`nvidia-driver-<世代>-open`、R570 以降）でなければならない。スクリプトはそれ以外なら止まるので、止まったら一覧を見せて私に聞いて。入れたら再起動が要るので、再起動の前に必ず私に確かめて。再起動後に `nvidia-smi` で 2 枚が見えること、各 16GB であることを確かめて。

### 2-2. HWE カーネル・CPU 電力の読み取り

> docs/ubuntu-server.md の「HWEカーネル・GPU LED・RAPL」と「カーネル更新の前に」の章を読んでから、`scripts/install-hwe-kernel-ubuntu.sh --dry-run` を流して結果を見せて。問題なければ `scripts/configure-ubuntu-hardware.sh`（HWE カーネル、CPU 電力の読み取り権限。GPU LED は dekahamuntu.env で切ってある）を流して。カーネルを上げる前と再起動の前に、`scripts/check-nvidia-kernel-modules-ubuntu.sh` で、入るカーネルと同じ版の `linux-modules-nvidia-*-open` があることを確かめて。✗ が出たら再起動しないで私に知らせて。再起動は私がする。再起動後に `uname -r`・`nvidia-smi`・有線 LAN・Tailscale を確かめて。

### 2-3. 2 枚の PCIe の確かめ

> docs/dekahamuntu-setup.md の「PCIe の帯域」の節のコマンドで、2 枚の PCIe の世代・幅（Gen5 x8 の見込み）、`nvidia-smi topo -m`、P2P の可否を読んで、結果を docs/dekahamuntu-setup.md の「実機で確かめた値」に書いて。設定は何も変えないで。

### 2-4. ComfyUI（GPU 0）

> docs/ubuntu-server.md の「ComfyUI」の章に従って `scripts/install-comfyui-ubuntu.sh` を流して。dekahamuntu.env の `COMFY_CUDA_DEVICES=0` で GPU 0 だけを使う。終わったら `scripts/configure-comfyui-tailscale-serve.sh` で tailnet に公開して。モデルは自動で取らない。どのモデルを置くかは docs/ai-server-placement.md の案を私と決めてから。

`~/ai`（private repo）の clone には GitHub の認証が要る。どう認証するか（chibihamuntu と同じ方法か、gh の認証か）は本人が決める。

### 2-5. Qwen（GPU 1。束ねるときは 2 枚）

> docs/ubuntu-server.md の「Qwen3.8」の章を読んで、Home Manager の設定が入っていることを確かめてから、`scripts/install-qwen38-ubuntu.sh` を流して。dekahamuntu.env では dense の 27B は取らず（`QWEN_INSTALL_27B=0`）、Flash-Next（MoE）だけを取る。qwen38.service は GPU 1、qwen38-dual.service は 2 枚を層ごとに分ける。n-cpu-moe の値は推測なので、`ai-mode split` と `ai-mode llm-dual` のそれぞれでモデルをロードし、`nvidia-smi` で各 GPU の空きが 1GB 前後になるところまで詰めて、決まった値を hosts/ubuntu/dekahamuntu.env に書いてコミットして。計った速度（prompt と生成の tok/s）も docs/ai-server-placement.md に書いて。

### 2-6. 学習・Applio（必要になったら）

> 学習を dekahamuntu でもするなら、`scripts/install-diffusion-pipe-ubuntu.sh` を流して（GPU 0）。`~/ai/scripts/lora-train` の `Conflicts=` は chibihamuntu の 1 枚を前提に comfyui・qwen38・applio を止めるので、dekahamuntu で使う前に ~/ai 側の変更が要るかを確かめて私に聞いて。

### 2-7. 見張り（subako）

subako の `subako.config.json` の `machines` に dekahamuntu を足すと、GPU の温度（`alerts.gpuTempC`）・CPU 電力が見える。nvidia-smi の行ごとに読むので 2 枚とも見張られる。CPU 電力は `/sys/class/powercap/intel-rapl:0` を読む（AMD でも同じ名前で出る見込み）。subako 側の作業なので、subako のエージェントに頼む。

---

## ハードウェアごとの注意

### GPU（RTX 5060 Ti 16GB ×2、Blackwell）

| 項目 | 要るもの | 根拠 |
|---|---|---|
| カーネルモジュール | オープン版だけ（`nvidia-driver-*-open`）。プロプライエタリ版は Blackwell を扱わない | NVIDIA のドライバの README（Blackwell 以降はオープンカーネルモジュールのみ） |
| ドライバ | R570 以降（CUDA 12.8 GA の最小は Linux 570.117）。5060 Ti は 575 系で出た。chibihamuntu と同じ Ubuntu の推奨（2026-11 時点で 595-open）で足りる見込み | CUDA 12.8 のリリースノート |
| CUDA | 12.8 以降（sm_120 に初めて対応） | CUDA 12.8 のリリースノート |
| PyTorch | cu128 以降の wheel（ComfyUI は cu130、diffusion-pipe・Applio は cu128。どれも sm_120 を含む） | — |
| llama.cpp（Nix） | `cudaCapabilities = [ "12.0" ]`（`flake.nix`）。nixpkgs-unstable の CUDA 13.x でビルドする | `nix eval` で `CMAKE_CUDA_ARCHITECTURES=120` を確かめた |
| nvcc（Nix、diffusion-pipe の JIT 用） | nixpkgs 25.11 の CUDA 12.8.93。sm_120 を扱える | — |

カーネルを上げる前に、同じ版の `linux-modules-nvidia-<世代>-open` があるかを確かめる運用は chibihamuntu と同じ（[ubuntu-server.md の「カーネル更新の前に」](ubuntu-server.md#カーネル更新の前に)）。

GPU の割り当て（`hosts/ubuntu/dekahamuntu.env`）:

| unit | GPU | 備考 |
|---|---|---|
| comfyui.service | 0 | 既定で起動 |
| qwen38.service | 1 | 既定で起動（ComfyUI とは独立） |
| qwen38-dual.service | 0,1 | `ai-mode llm-dual`。comfyui・qwen38 と排他。`--split-mode layer --tensor-split 1,1` |
| applio.service | 0 | comfyui・qwen38-dual と排他 |
| diffusion-pipe の学習 | 0 | `TRAIN_CUDA_DEVICES=0,1` にすると 2 枚のデータ並列（`--num_gpus=2`） |

番号は `CUDA_DEVICE_ORDER=PCI_BUS_ID` で `nvidia-smi` と揃える。

GPU LED: カードのメーカーが分からないので、消灯は切ってある（`GPU_LED_OFF=0`）。同じカード 2 枚は名前で区別できないので、`turn-off-gpu-led` は `GPU_LED_COUNT=2` なら一覧の番号で 2 枚とも消す。OpenRGB がそのカードを扱えるかを確かめてから 1 にする。

### PCIe の帯域

ASUS の製品ページによれば（実機では未確認）、ProArt B850 には CPU 直結の PCIe 5.0 x16 スロット（SafeSlot）が 2 本あり、2 本とも使うと x8/x8 になる。ほかに PCIe 4.0 の x16 形状のスロット（x4 動作）が 1 本ある。RTX 5060 Ti はもともと x8 のカードなので、2 枚を上の 2 本に挿せば、どちらも **PCIe 5.0 x8（片方向 約 32GB/s、PCIe 4.0 x16 と同じ程度）** で動く見込み。3 本目（x4）に挿すと帯域が 1/2 になるので使わない。

NVLink はない。2 枚を束ねる形（LLM の分割、学習のデータ並列）は GPU 間の通信が PCIe 越しになる。

- llama.cpp の層ごとの分割（layer）は、層の境目の活性値だけを渡すので、PCIe でも遅くなりにくい
- 行ごとの分割（row）や tensor parallel は通信が多い。PCIe だけの構成では遅くなりやすいので、既定にしない
- GeForce は P2P（GPU 間の直接転送）が使えないことが多い。使えなければ CPU のメモリを経由する。学習の NCCL は `NCCL_P2P_DISABLE=1` にしてある（chibihamuntu と同じ）

実機で確かめる（読むだけ）:

```bash
nvidia-smi -q | grep -A12 'GPU Link Info'        # Current/Max の Generation と Link Width（Gen5・x8 の見込み）
nvidia-smi --query-gpu=index,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max --format=csv
nvidia-smi topo -m                                # GPU0-GPU1 の経路（PHB/NODE/SYS。NV# なら NVLink）
nvidia-smi topo -p2p r                            # P2P の読み取りの可否（OK / NS など）
```

アイドル中は省電力で Gen1 などに下がることがある。負荷をかけた状態で読むか、`Max` の値を見る。

### CPU（AMD Ryzen）

| 項目 | chibihamuntu（Intel） | dekahamuntu（AMD） |
|---|---|---|
| 電力の読み取り | `/sys/class/powercap/intel-rapl:0/energy_uj` | 同じパス（AMD も `intel_rapl_msr` が出す。Zen 4 は 5.11 から、Zen 5（Family 1Ah）は 6.12 から。HWE 7.0 なら両方入っている） |
| 権限 | `power` グループ + udev（`udev/99-rapl-power.rules`） | 同じ。ゾーンが出なければスクリプトは何も変えずに警告して終わる。読めなければ `CPU_POWER_READ=0` |
| マイクロコード | `intel-microcode`（Ubuntu の既定で入る） | `amd64-microcode`（同じく既定で入る） |
| 周波数の制御 | `intel_pstate` | `amd-pstate`（カーネルの既定。EPP の `balance_performance`） |
| thermald | 動いている | Intel 専用なので AMD では何もしない（入っていても害はない） |

周波数・省電力は、カーネルの既定のまま（`amd-pstate` の active モード、EPP は `balance_performance`）にする。常時稼働の AI サーバーで、負荷の大きい処理は GPU 側にあり、CPU の既定で足りる。カーネルの引数（`amd_pstate=` など）は足さない。確かめるだけなら:

```bash
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver                 # amd-pstate-epp の見込み
cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference  # balance_performance
ls /sys/class/powercap/                                                  # intel-rapl:0 があるか
```

### RAM（DDR5 64GB）

- chibihamuntu と同じ 64GB。swap はインストーラの既定（`/swap.img` 8GB）のままでよい。hugepages は使っていない（llama.cpp は mmap、PyTorch は既定）
- Qwen3.8-Flash-Next（約 86GB）は RAM に収まらず、ページキャッシュに読みながら動く（chibihamuntu の実測で RAM をほぼ使い切る）。dekahamuntu では VRAM が 32GB あるぶん、束ねたときはエキスパートを多く GPU に置ける
- DDR5 の EXPO（メモリのオーバークロックの設定）は、4 枚挿しで不安定になりやすい。常時稼働なので、EXPO を使うなら最初にメモリの検査（memtest86+ など）を本人がする

### ネットワーク

- 有線 5GbE ×2（Realtek RTL8126 の見込み。チップは要確認）と Wi-Fi 7
- RTL8126 は標準カーネルの `r8169` が 6.9 から扱う。24.04 の GA カーネル 6.8 では見えないことがあり、HWE カーネルなら動く見込み。`lspci -nnk` で `Kernel driver in use: r8169` になり、リンクが上がるかを確かめる。上がらないときだけ Realtek の `r8126`（DKMS、ADR 0001 の管理境界の外）を検討し、入れるかは本人が決める
- 雛形: [`hosts/ubuntu/dekahamuntu-netplan.yaml.example`](../hosts/ubuntu/dekahamuntu-netplan.yaml.example)（インターフェース名・MAC は実機で確かめる）。インストーラの作った設定で動いていれば置き換えなくてよい
- Wi-Fi は、有線で足りるなら設定しない（chibihamuntu は Wi-Fi のドライバの不具合でカーネルパニックの前歴がある）

### ディスク

構成は未確認（M.2 が 3 本: PCIe 5.0 x4 ×2、PCIe 4.0 x4 ×1。SATA ×4）。モデルは chibihamuntu で約 900GB ある。どのディスクに何を置くか（`/` に全部か、モデル用に別のディスクをマウントするか）は本人が決め、パーティション・フォーマットも本人が行う。決まったらこの節に書く。

---

## 実機で確かめた値

（第2段でエージェントが書く。まだ何も確かめていない）

| 項目 | 値 | 確かめた日 |
|---|---|---|
| マザーボードの型番 | | |
| CPU の型番 | | |
| GPU のメーカー・型番、VRAM | | |
| PCIe（GPU 0 / GPU 1） | | |
| `nvidia-smi topo -m` の GPU0-GPU1 | | |
| P2P | | |
| 有線 LAN のチップ・ドライバ・名前 | | |
| ディスク | | |
| ドライバの版 | | |
| powercap のゾーン | | |
