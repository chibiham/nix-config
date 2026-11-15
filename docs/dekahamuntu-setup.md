# dekahamuntu のセットアップ

dekahamuntu は chibihamuntu と同じく AI サーバーとして使う 2 台目の Ubuntu 機。管理の境界は chibihamuntu と同じ（[ADR 0001](adr/0001-ubuntu-serverの管理境界.md)）。ホストごとの差の持ち方は [ADR 0002](adr/0002-ubuntu機ごとの設定.md)。

| | chibihamuntu | dekahamuntu |
|---|---|---|
| CPU | Intel Core i7-13700KF | AMD Ryzen 7 9700X（Zen 5、8 コア） |
| マザーボード | ASUS TUF GAMING B760M-PLUS D4 | ASUS ProArt B850-CREATOR WIFI NEO |
| GPU | RTX 3090 24GB ×1（Gigabyte。Ampere、sm_86） | RTX 5060 Ti 16GB ×2（Palit Infinity 3。Blackwell、sm_120）。合計 32GB、NVLink なし |
| RAM | DDR4 64GB | DDR5 64GB |
| Home Manager | `chibiham@ubuntu-server` | `chibiham@dekahamuntu` |
| スクリプトの設定 | `hosts/ubuntu/chibihamuntu.env` | `hosts/ubuntu/dekahamuntu.env` |
| 1Password Vault | `chibihamuntu` | `dekahamuntu`（作る） |

部品・仕様の正は [machines.md](machines.md)。この表は要約。

セットアップは 2 段に分ける。実機の今の状態と、それをどのスクリプトで再現するかは [dekahamuntu の状態（2026-11-12）](#dekahamuntu-の状態2026-11-12)。

- **第1段**（本人がやる。この文書の前半）: Ubuntu を入れ、Nix・Home Manager・シークレット・エージェント（Claude Code、Codex）・Tailscale まで。GPU がなくても通る。終われば、Mac から `ssh chibiham@dekahamuntu` して、マシンの上で Claude Code を動かせる
- **第2段以降**（マシンの上のエージェントに任せる。後半）: NVIDIA ドライバ、HWE カーネル、ComfyUI、LLM、学習。sudo・再起動・ディスクの操作の前には、必ず本人に確かめる

### 実機で本人が最初にやる順（2026-11 の実績）

エージェントには任せられない（画面・パスワード・ログイン・秘密が要る）ので、本人がこの順に行う。細かい手順は下の各節。

1. Ubuntu Server 24.04.5 を、インストーラの起動メニューで **HWE カーネル** を選んで入れる（下の 1.。GA カーネルでは有線も Wi-Fi も見えない）。OpenSSH server を入れ、GitHub の公開鍵を取り込む
2. 1Password に Vault `dekahamuntu` とアイテム（`CIVITAI_TOKEN`・`R2_CHIBIHAM_AI`）、その Vault だけを読める Service Account を作る（下の 0.）
3. Nix を入れ、このリポジトリを clone して `bootstrap-ubuntu.sh` を流す。Service Account のトークンを聞かれたら貼る（下の 2.〜4.）
4. `install-tailscale-ubuntu.sh` で Tailscale に入れ、ブラウザで認証する（下の 5.）
5. `claude` と `codex login` にログインする（下の 6.）
6. GitHub に `gh auth login` で入る（https。`~/ai` の clone に使う。下の 6.）。ssh の鍵で push したいなら、鍵を作って GitHub に登録する（任意。2026-11 時点では作っていない）
7. 第2段の sudo（ドライバ、`build-essential` など、linger、Tailscale serve、ディスクの拡張）は、エージェントが出したコマンドを本人が流す（エージェントは sudo のパスワードを持たない）。Tailscale serve の Qwen の 8443（`sudo tailscale serve --bg --https=8443 http://127.0.0.1:8080`）は本人が sudo で流した（2026-11-14。tailnet から答えが返るのを確かめた。下の 2-5）

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

- インストーラは Ubuntu Server 24.04.x の最新の ISO を使う（2026-11 は 24.04.5）
- **最初から HWE カーネルを選ぶ**: インストーラの起動メニュー（GRUB）で「Ubuntu Server with the HWE kernel」を選ぶ。24.04.5 の GA カーネル 6.8 では、有線の RTL8126（5GbE）も Wi-Fi の RTL8922AE も見えず、ネットワークが使えなかった。HWE（2026-11 は 7.0）なら両方見える（`r8169`、`rtw89_8922ae`）。HWE で入れると `linux-generic-hwe-24.04` が入り、以後のカーネルも HWE で上がる
- **ストレージ**: どのディスクに入れるか・パーティション・LVM は本人が画面で決める。この文書とスクリプトはディスクを消さない・フォーマットしない。エージェントにもさせない
  - 参考: chibihamuntu は 1.9TB の LVM に `/` 1 つ（モデル類で約 900GB 使用）。Windows の入った別の NVMe は触っていない
  - dekahamuntu: インストーラの既定の LVM は `/` が 100GB だけだった。あとで本人が `sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv` で 1.9TB 全部に広げた。最初から「Custom storage layout」で LV を全部にしておけば、この手間は要らない
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

表示された URL を Mac のブラウザで開いて認証する（認証キーは使わない）。`--hostname=dekahamuntu` で登録される。続けて `tailscale set --operator=$USER` を流すので、以後の `tailscale serve` は sudo なしで設定できる（chibihamuntu と同じ）。tailnet の管理画面で、鍵の期限（Key expiry）を切るかは本人が決める。

tailnet 内への公開（Tailscale Serve）は、サービスを入れたあとに `scripts/configure-tailscale-serve-ubuntu.sh` で、`hosts/ubuntu/dekahamuntu.env` の `TAILSCALE_SERVE`（`443=8188 4520=4520 8443=8080`）のとおりにする（第2段の 2-4・2-5）。

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
gh auth login   # GitHub.com、HTTPS、ブラウザで認証。~/ai（private repo）の clone に使う
gh auth status
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
- **エージェントは sudo を使えない**（パスワードが要り、エージェントには渡さない）。sudo が要るところで止まり、本人が流すコマンドを正確に、順に出す。本人が流したあとの確かめはエージェントがする
- **再起動の前に、長い転送（rsync・モデルの取得・`npm ci` など）が終わっていることを確かめる**。長い処理は tmux か nohup で動かし、ssh が切れても続くようにする
- 秘密（トークン・鍵・パスワード）を入力・保存しない
- 恒久的な変更はこのリポジトリのスクリプトか Nix の設定に入れる（その場限りの `apt install`・unit の手編集で終わらせない）。変更はコミットまでで、push は本人に確かめる

### 2-1. NVIDIA ドライバ

> docs/ubuntu-server.md の「NVIDIAドライバ」の章と docs/dekahamuntu-setup.md の「GPU」の節に従って、`scripts/install-nvidia-driver-ubuntu.sh` で入れて（sudo が要るので、私が流すコマンドを出して）。このホストは RTX 5060 Ti ×2（Blackwell）なので、オープンカーネルモジュール版（`nvidia-driver-<世代>-open`、R570 以降）でなければならない。スクリプトはそれ以外なら止まるので、止まったら一覧を見せて私に聞いて。入れたら再起動が要るので、再起動の前に必ず私に確かめて（動いている転送があれば、終わるのを待つ）。再起動後に `nvidia-smi` で 2 枚が見えること、各 16GB であることを確かめて。

2026-11-12 の実績: `ubuntu-drivers install` が `nvidia-driver-595-open` と `linux-modules-nvidia-595-open-generic-hwe-24.04` を入れ、595.99.02（CUDA 13.2）で 2 枚が見えた。

### 2-2. HWE カーネル・CPU 電力の読み取り

HWE カーネルはインストーラで入っている（第1段の 1.）ので、ここでは確かめと RAPL だけになる。2026-11-12 の実績: カーネル 7.0.0-43、`install-rapl-power-access-ubuntu.sh` で `power` グループと udev の規則を入れた（`intel-rapl:0` が出る）。

> docs/ubuntu-server.md の「HWEカーネル・GPU LED・RAPL」と「カーネル更新の前に」の章を読んでから、`scripts/install-hwe-kernel-ubuntu.sh --dry-run` を流して結果を見せて。問題なければ `scripts/configure-ubuntu-hardware.sh`（HWE カーネル、CPU 電力の読み取り権限。GPU LED は dekahamuntu.env で切ってある）を流して。カーネルを上げる前と再起動の前に、`scripts/check-nvidia-kernel-modules-ubuntu.sh` で、入るカーネルと同じ版の `linux-modules-nvidia-*-open` があることを確かめて。✗ が出たら再起動しないで私に知らせて。再起動は私がする。再起動後に `uname -r`・`nvidia-smi`・有線 LAN・Tailscale を確かめて。

### 2-3. 2 枚の PCIe の確かめ

> docs/dekahamuntu-setup.md の「PCIe の帯域」の節のコマンドで、2 枚の PCIe の世代・幅（Gen5 x8 の見込み）、`nvidia-smi topo -m`、P2P の可否を読んで、結果を docs/dekahamuntu-setup.md の「実機で確かめた値」に書いて。設定は何も変えないで。

### 2-4. ComfyUI（既定のデバイスは GPU 0）

> docs/ubuntu-server.md の「ComfyUI」の章に従って `scripts/install-comfyui-ubuntu.sh` を流して（apt と linger に sudo が要るので、その部分は私が流すコマンドを出して）。dekahamuntu.env の `COMFY_CUDA_DEVICES=0,1` で 2 枚とも見せる（既定のデバイスは GPU 0 で、今までのワークフローは GPU 0 だけを使う。GPU 1 は MiniMax H3 Image のテキストエンコーダーの計算を回すためだけ。2-9）。版は `COMFY_REF`（v0.45.2）。終わったら `scripts/configure-tailscale-serve-ubuntu.sh` で tailnet に公開して（`TAILSCALE_SERVE`）。モデルは自動で取らない。どのモデルを置くかは docs/ai-server-placement.md の案を私と決めてから。

`~/ai`（private repo）は `gh repo clone chibiham/chibiham-ai ~/ai -- -b develop`（https。`gh auth login` 済みであること）。

2026-11-12 の実績（chibihamuntu からの引っ越し。手順の全体は subako 側の手順書にある）:

1. `install-comfyui-ubuntu.sh` の中身を、chibihamuntu と同じ版に揃えて手で流した: ComfyUI の commit（`e3bee7ff`）を checkout、`uv venv --python 3.12`（mise の 3.12.16 が選ばれた）、chibihamuntu の venv の `uv pip freeze` を cu130 の index で入れた（torch 2.13.0+cu130）。apt（`build-essential`・`python3.12-dev`・`ffmpeg`・`git-lfs`）と linger は本人が sudo で流した
2. カスタムノード: cnr と git のものは chibihamuntu の `~/ComfyUI/custom_nodes` から rsync で写した（`~/ai/comfyui/custom-nodes.snapshot.json` と `cm-cli restore-snapshot` でも作れる）。自作の 5 つ（`chibiham-*`）と `user/default/{workflows,comfy.settings.json}` は `~/ai/comfyui/` への symlink（`~/ai` の README の手順）
3. モデル（`~/ComfyUI/models`、約 427GB）は chibihamuntu から rsync で写し、`~/ai/scripts/models check --hash` で確かめた
4. art-studio: `~/ai/scripts/install-art-studio`（unit 本体）と `scripts/configure-art-studio-ubuntu.sh`（このホストの drop-in。`ART_STUDIO_COMFYUI_URL`・`ART_STUDIO_CUDA_DEVICES`）。モザイクの `.venv` は `~/ai/apps/art-studio` の README の手順。作品と DB は chibihamuntu から写した
5. Tailscale Serve は本人が sudo で `443 → 8188`、`4520 → 4520` を設定した（いまは `configure-tailscale-serve-ubuntu.sh` で同じ形になる）

このときの unit は GPU 0 だけ（`CUDA_VISIBLE_DEVICES=0`）、本体は `e3bee7ff`。v0.45.2 への更新と、GPU 1 も見せる変更（2026-11-14）は「[2-9](#2-9-comfyui-の更新v0452と-minimax-h3-image)」。

### 2-5. Qwen（GPU 1。束ねるときは 2 枚）

> docs/ubuntu-server.md の「Qwen3.8」の章を読んで、Home Manager の設定が入っていることを確かめてから、`scripts/install-qwen38-ubuntu.sh` を流して。dekahamuntu.env では dense の 27B は取らず（`QWEN_INSTALL_27B=0`）、Flash-Next（MoE）だけを取る。qwen38.service は GPU 1、qwen38-dual.service は 2 枚を層ごとに分ける。n-cpu-moe の値は推測なので、`ai-mode split` と `ai-mode llm-dual` のそれぞれでモデルをロードし、`nvidia-smi` で各 GPU の空きが 1GB 前後になるところまで詰めて、決まった値を hosts/ubuntu/dekahamuntu.env に書いてコミットして。計った速度（prompt と生成の tok/s）も docs/ai-server-placement.md に書いて。

2026-11-13 の実績（n-cpu-moe を詰め、速さを chibihamuntu と比べ、入れて常駐させた。細かい値は [ai-server-placement.md の「実測（2026-11-13）」](ai-server-placement.md#実測2026-11-13-qwen38-flash-next)）:

1. モデルは UD-Q3_K_XL（3 分割）と `mmproj-BF16.gguf`、Uncensored 版（mradermacher の i1-IQ3_M、約 89.5GB）と `Qwen3.8-Flash-Next-Uncensored.mmproj-f16.gguf` を `~/models/qwen3.8-flash-next` に取った（`install-qwen38-ubuntu.sh` の `download_model` と同じ取り方。UD-Q3_K_XL は約 87GB を約 3 分 50 秒、Uncensored 版は約 473MiB/s）。Uncensored 版のファイルの大きさは chibihamuntu と同じ（sha256 は照らしていない）。27B は取っていない（`QWEN_INSTALL_27B=0`）
2. n-cpu-moe は llama-server を一時の user unit（systemd-run）で、qwen38.service と同じ引数で立てて詰めた。値は dekahamuntu.env: UD-Q3_K_XL は 1 枚 45・束ね 33、Uncensored 版は 1 枚 42・束ね 31。`LLM_DUAL_TENSOR_SPLIT` は 39,10（1,1 では読み込めない）。Uncensored 版の束ねは 39,10 のままだと GPU 1 に約 3.1GB 余る（tensor-split はモデルごとに変えられない）
3. `install-qwen38-ubuntu.sh` を流した（実機の作業ツリーが古いので、env の値は環境変数 `QWEN_FLASH_N_CPU_MOE=45 QWEN_FLASH_UNCENSORED_N_CPU_MOE=42 QWEN_DUAL_FLASH_N_CPU_MOE=33 QWEN_DUAL_FLASH_UNCENSORED_N_CPU_MOE=31 LLM_DUAL_TENSOR_SPLIT=39,10` で渡した）。入ったもの: `qwen38.service`（enabled、`WantedBy=default.target`、GPU 1、Router、ポート 8080）、`qwen38-dual.service`（enable しない。`Conflicts=qwen38.service comfyui.service`、GPU 0,1、`--split-mode layer --tensor-split 39,10`）、`~/.config/llama.cpp/qwen38-models.ini`（45 / 42）、`qwen38-dual-models.ini`（33 / 31）、`qwen38-flash-chat-template.jinja`。home-manager switch は要らなかった（llama-server 0.6.0 と `ai-mode` は入っていた）
4. スクリプトは最後の Tailscale Serve の段だけ「Access denied: serve config denied」で失敗した（終了コード 1。operator を設定していないので sudo が要る）。本人が sudo で流した（2026-11-14）。tailnet から答えが返るのを確かめた（下の 8.）。流したコマンド:

   ```bash
   sudo tailscale serve --bg --https=8443 http://127.0.0.1:8080
   ```

   `configure-tailscale-serve-ubuntu.sh` でも同じ形になる（`TAILSCALE_SERVE` に `8443=8080` を入れた。operator がなければ sudo に落ちる）
5. 入れた unit で確かめた: Router 経由で UD-Q3_K_XL と Uncensored 版を読み込んで答えが返った（長い問いの温まったあとの生成 約 25.7 / 約 29.3 tok/s。GPU 1 に 14,822 / 14,526MiB。GPU 0 は ComfyUI の 138MiB だけ）。`ai-mode llm-dual` で束ねに切り替えて 2 つとも答えが返り、`ai-mode split` で戻した。そのあいだ ComfyUI は `/system_stats` 200、fan2go は active
6. いまの形（本人の決め、2026-11-13）: `ai-mode split` が既定。GPU 0 = ComfyUI、GPU 1 = Flash-Next の Router を常駐（モデルは最初の問いで読み込む）。束ね（`ai-mode llm-dual`）は必要なときに切り替える
7. ComfyUI で画像（Anima、Qwen-Image 2.1）を 1 枚ずつ続けて作りながら計った（2026-11-14 の本人の依頼）: 長い問いの温まったあとの生成は UD-Q3_K_XL 20.62〜22.26、Uncensored 版 22.15〜25.79 tok/s（単独より 1〜2 割遅い）、画像の 1 枚あたりは +1〜2%。SSD の大きな読み直しは起きなかった。細かい値は [ai-server-placement.md の「ComfyUI で画像を作りながらの同居」](ai-server-placement.md#comfyui-で画像を作りながらの同居dekahamuntu2026-11-14)
8. 本人が 4. の `sudo tailscale serve --bg --https=8443 http://127.0.0.1:8080` を流した（2026-11-14）。確かめた（2026-11-13 19:06 UTC = 日本時間 11-14 4:06）: `tailscale serve status` に 443 → 8188、4520 → 4520、8443 → 8080 の 3 つ（どれも tailnet only）。Mac から tailnet 経由で 8443 の `/health` が 200、`/models` に 2 つのモデルが出て、`/v1/chat/completions`（Uncensored 版、「1+1 は？数字だけで答えて。」）に「2」が返った。そのあとモデルをアンロードした（2 つとも unloaded、Router は常駐、ComfyUI は `/system_stats` 200）。これで第2段の Qwen（常駐の qwen38.service と tailnet への公開）は通った
9. 2026-11-14: 使い終わったモデルを 600 秒で降ろすようにした（`QWEN_SLEEP_IDLE_SECONDS=600` → `--sleep-idle-seconds 600`。`install-qwen38-ubuntu.sh` を流し直した）。Qwen のモデルが GPU 1 に載ったままだと、MiniMax H3 Image のテキストエンコーダーの計算（GPU 1）が OutOfMemoryError になるため。確かめた値は「[2-9](#2-9-comfyui-の更新v0452と-minimax-h3-image)」の「llama との同居」

### 2-6. 学習・Applio（必要になったら）

> 学習を dekahamuntu でもするなら、`scripts/install-diffusion-pipe-ubuntu.sh` を流して（GPU 0）。`~/ai/scripts/lora-train` の `Conflicts=` は chibihamuntu の 1 枚を前提に comfyui・qwen38・applio を止めるので、dekahamuntu で使う前に ~/ai 側の変更が要るかを確かめて私に聞いて。

### 2-7. 見張り（subako）

subako の `subako.config.json` の `machines` に dekahamuntu を足すと、GPU の温度（`alerts.gpuTempC`）・CPU 電力が見える。nvidia-smi の行ごとに読むので 2 枚とも見張られる。CPU 電力は `/sys/class/powercap/intel-rapl:0` を読む（AMD でも同じ名前で出る見込み）。subako 側の作業なので、subako のエージェントに頼む。

### 2-8. ケースファンを GPU の温度で回す

本人が順に流す（sudo が要る）。中身と手順は下の「[ケースファン](#ケースファンgpu-の温度で回す)」。

### 2-9. ComfyUI の更新（v0.45.2）と MiniMax H3 Image

issue 5（docs/issues/5-dekahamuntu-minimax-h3-image.md）。作業は 2026-11-14 UTC（日本時間 11-15 の未明〜朝）。本人の依頼（2026-11-15 日本時間、原文）:

> Bで構成しよう。comfy更新もやろう。flash nextはあんまり使わなそうなので大丈夫なんだけど、llamaから呼び出しなければメモリ取り合わない？llama停止しなくても大丈夫なのかな。

（B = テキストエンコーダーを GPU 1、絵の本体（DiT）を GPU 0 に分けて、プロンプトが変わっても本体の入れ替えが起きない形。ほかの案は A = GPU 0 だけで入れ替える、C = chibihamuntu の 3090。比べた値は [ai-server-placement.md の「実測（2026-11-14）: MiniMax H3 Image」](ai-server-placement.md#実測2026-11-14-minimax-h3-imagedekahamuntu)。）

#### 構成（B）

| | GPU 0 | GPU 1 |
|---|---|---|
| ComfyUI | 既定のデバイス（`cuda:0`）。今までのワークフロー全部と、H3 Image の本体（DiT）・VAE。本体はプロンプトを変えても降りない | H3 Image のテキストエンコーダー（Qwen3-VL 32B NVFP4）の**計算だけ**。ノード `Select CLIP Device`（`gpu:1`）で回す。重み（約 15GB）は RAM に置かれ、GPU 1 を使うのはエンコードのあいだだけ（最大 1.5〜1.6GB、終わると 336〜348MiB） |
| Qwen | — | `qwen38.service`（Router）。モデルが載っているあいだは、H3 Image（B）のエンコードが OutOfMemoryError になる（下の「llama との同居」） |
| art-studio のモザイク（YOLO） | GPU 0 のまま（`ART_STUDIO_CUDA_DEVICES=0` は変えていない） | — |

- ComfyUI に 2 枚を見せる（`COMFY_CUDA_DEVICES=0,1`、unit の `CUDA_DEVICE_ORDER=PCI_BUS_ID`）。v0.45.2 の本体は、ノードで指定しない限り既定のデバイスしか使わない（コードで確かめた: テキストエンコーダー・VAE・本体とも `get_torch_device()`）。本番でも、2 枚見せたあとの主なレシピ 5 つは GPU 1 を使わなかった（GPU 1 は 138MiB のまま。下の「確かめたこと」）
- テキストエンコーダーを GPU 1 で回すのは、本体のノード `Select CLIP Device`（`SelectCLIPDevice`、category advanced/multigpu）。第三者の拡張（ComfyUI-MultiGPU など）は入れていない。このノードは `e3bee7ff` にもあったが、H3 Image への対応は 0.45.0 から。GPU が 1 枚しか見えないときは `gpu:N` の選択肢が出ず、指定があっても素通しになる。本番で 2 枚を見せたあとの選択肢は `default / cpu / gpu:0 / gpu:1`
- B の実際の動き（v0.45.2、本番で見た）: `gpu:1` にしても、テキストエンコーダーは GPU 1 の VRAM に常駐しない。ログは「Creating deepclone of MiniMaxH3TEModel_ for cuda:1.」「Model MiniMaxH3TEModel_ prepared for dynamic VRAM loading. 14956MB Staged.」で、重みは RAM に置かれる（ComfyUI の RSS は A の 8〜13GB に対して B は 23〜28GB）。エンコードの 1 秒ほど GPU 1 の使用率が 87% になる。1 枚目はテキストエンコーダーの用意に約 17 秒かかる回があった（GPU 1 に 1,072MiB、使用率 4〜20% の時間が続く）。2 回目からは約 1 秒
- ワークフローのノード: `UNETLoader` → `KSampler`（6 steps・cfg 1・euler / simple・denoise 1）、`CLIPLoader`（type `minimax`）→ `Select CLIP Device`（`gpu:1`）→ `MiniMaxH3ImageConditioning`（prompt・width・height。positive と latent を出す）→ `ConditioningZeroOut`（negative）、`VAELoader` → `VAEDecode`
- テキストエンコーダーは、公式の文書（docs.comfy.org）が挙げる int8 版（27.1GB）ではなく、同じ公式リポジトリにある NVFP4 版（15.7GB。H3 の動画と同じファイルで、前から置いてあった）を使う。H3 Image で使えた（Blackwell は NVFP4 をそのまま計算できる。ログに `Native ops: … nvfp4`）
- 既定は **公式 int8 を B の形で**。w4a8 も置き、Qwen を載せたまま使うとき・GPU 1 を空けておきたいとき・4096² を速く出したいときに A の形（`Select CLIP Device` なし）で使う。GGUF は使わない。エージェントの決め（2026-11-14）で、本人が spec の絵を見て変えるかもしれない。理由は [ai-server-placement.md の「決定」](ai-server-placement.md#dekahamuntu-の-minimax-h3-image2026-11-15-日本時間)
- ComfyUI の画面用のワークフロー: `~/ComfyUI/user/default/workflows/MiniMax-H3-Image/minimax_h3_image_t2i_dual_gpu.json`（公式 int8、`Select CLIP Device` = `gpu:1`、2048²、6 steps、SaveImage の prefix は `minimax_h3_image/h3`、使い方の注記つき）。dekahamuntu では `user/default/workflows` が `~/ai/comfyui/workflows` への symlink なので、実体は `~/ai/comfyui/workflows/MiniMax-H3-Image/` の未追跡のファイル（`~/ai` には commit していない）。art-studio のレシピ・台帳（`~/ai` の `models.lock.toml`）・拡張の一覧への書き込みと、このワークフローの扱いは chibiham-ai#74 でやる

#### 入れたもの

| もの | 版・値 | 本番 | 作り直すもの |
|---|---|---|---|
| ComfyUI の本体 | v0.45.2（`6e8488ef986067631e9c86e2a14360644b105663`、タグの日付 2026-11-11T02:25:54Z）。前は `e3bee7ff`（`git describe` は v0.42.0-7-ge3bee7ffc、2026-10-20） | 上げた（2026-11-14 22:27 UTC = 日本時間 11-15 7:27） | `COMFY_REF=v0.45.2` と `update-comfyui-ubuntu.sh` |
| Python のパッケージ | 下の 8 つが変わった | 同上 | 同上 |
| comfyui.service | `CUDA_VISIBLE_DEVICES=0,1`（前は `0`。unit の差はこの 1 行） | 書き換えた（22:30 UTC = 日本時間 7:30） | `COMFY_CUDA_DEVICES=0,1` と `install-comfyui-ubuntu.sh --unit-only`（sudo なし） |
| H3 Image の重み | 下の表 | 置いた（2026-11-14 17:29〜17:31 UTC = 日本時間 11-15 2:29〜2:31、約 300MiB/s） | `install-minimax-h3-image-ubuntu.sh`（`H3_IMAGE_MODELS=int8 w4a8` か引数） |
| ComfyUI-GGUF（city96、GGUF の本体を読む第三者の拡張） | commit `6ea2651e7df66d7585f6ffee804b20e92fb38b8a`（2026-01-12）、依存で `gguf==0.19.0` が入った | **入れていない**（比べるために写しにだけ入れた） | 使わない。`install-minimax-h3-image-ubuntu.sh gguf-q5`（か `gguf-q4`）を引数で選んだときだけ `custom_nodes/ComfyUI-GGUF` に置く |
| qwen38.service・qwen38-dual.service | `--sleep-idle-seconds 600`（unit の差はどちらもこの 1 行。preset は変わらない） | 入れた（2026-11-14、`install-qwen38-ubuntu.sh`） | `QWEN_SLEEP_IDLE_SECONDS=600` と `install-qwen38-ubuntu.sh` |
| `ai-mode image-dual`、`split` での ComfyUI の `/free` | `home/hosts/dekahamuntu.nix` | **まだ古い**（home-manager switch は本人がやる） | home-manager switch |

v0.45.0 以上が要る（H3 Image の対応が 0.45.0 から）。v0.45.3（2026-11-12T20:58:31Z）は、作業した時点で公開から 72 時間たっていなかったので使わない（このリポジトリの「公開から 72 時間未満のものは使わない」に合わせた）。chibihamuntu は触らない（ComfyUI は disable 済みで、H3 の動画を手で使うときだけ起こす）ので、**2 台で版が分かれた**（chibihamuntu は `e3bee7ff`、`COMFY_REF` は空で master を pull）。

更新で変わった Python のパッケージ（本番の `uv pip freeze` との差。torch 2.13.0+cu130 などは変わらない。更新のあとの `/system_stats` の版もこのとおり）:

| パッケージ | e3bee7ff | v0.45.2 |
|---|---|---|
| comfyui-frontend-package | 1.55.18 | 1.58.5 |
| comfyui-workflow-templates | 0.11.89 | 0.11.106 |
| comfyui-workflow-templates-core | 0.3.380 | 0.3.397 |
| comfyui-workflow-templates-json | 0.1.115 | 0.1.132 |
| comfyui-workflow-templates-media-assets-02 | 0.1.17 | 0.1.31 |
| comfyui-embedded-docs | 0.5.14 | 0.5.16 |
| comfy-aimdo | 0.5.6 | 0.6.0 |
| comfy-kitchen | 0.2.39 | 0.2.41 |

H3 Image の重み（`~/ComfyUI/models/` の下。URL は `https://huggingface.co/<リポジトリ>/resolve/<revision>/<パス>`）:

| 置き場所 | 大きさ（bytes） | sha256 | 取得元 |
|---|---|---|---|
| `vae/minimax_h3_image_vae_fp16.safetensors` | 1168505312 | `d80e9c2e5cfc9844869961ff5a58c9a9e52182df6bfb30b26018dd7f348721af` | Comfy-Org/MiniMax-H3-Image @ `0bb149f51e3156ed4b90dd45d5620346bfe1df8f` |
| `diffusion_models/minimax_h3_image_pruned_int8_convrot.safetensors`（既定） | 20979314802 | `83eb140f1ff95c068f8a6886e6d3f3d0d4ab2e07bb2fe6d2ef992a51146ee622` | 同上 |
| `diffusion_models/minimax_h3_image_pruned_w4a8.safetensors` | 12549794530 | `517cc19b85348386f4df7c806dce80d839d0899e7cdaa3e1dbb09de964381dbb` | 同上（公式。issue を書いた時点では知られていなかった 12.5GB の版） |
| `diffusion_models/MiniMax-H3-Image-Pruned-Q5_K_M.gguf`（使わない。消してよい候補） | 14077892224 | `f4e139d7aa5cd67727b6645a5b1c17d1c931f7289d46a3b1ea183d7a9b8ce44b` | Abiray/MiniMax-H3-Image-GGUF @ `fec7ec774db49d0c785bdc2174a488576b7396dd`（第三者） |
| `diffusion_models/MiniMax-H3-Image-Pruned-Q4_K_M.gguf`（使わない。消してよい候補） | 11573106304 | `e545379320e533f9d60e2d831a9489d94889158e88cd681ea7940da47882015f` | 同上 |
| `text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors`（前からあった。取り直していない） | 15687142551 | `35a88d51044231fe332301d7a62aa81e3f2cba62febeb446e2c1e3e0ef76f2c6` | Comfy-Org/MiniMax-H3-Image の同じ revision にあるものと sha256 が同じ（H3 の動画の Comfy-Org/MiniMax-H3 と同じファイル） |
| `text_encoders/qwen3.5_9b_w4a8_gptq.safetensors`（前からあった。任意のプロンプト拡張） | 7343591088 | `4cc6a1543ad2061806da46f35f90cadb4801dcba246c44782cf42ec0feb6407c` | 同上。sha256 一致 |

- Comfy-Org/MiniMax-H3-Image のファイルの upload は 2026-11-10、リポジトリの最後の commit は 2026-11-11T12:10Z。Abiray の GGUF は 2026-11-10〜11（最後の commit 2026-11-11T14:28Z）。どちらも取得の時点で 72 時間を過ぎていた
- `install-minimax-h3-image-ubuntu.sh` は revision・大きさ・sha256 を固定している。`--verify` で置いたファイルの sha256 が一致し、新しい場所への取得（VAE・テキストエンコーダー・w4a8、29GB を 85 秒）も通った。終わりに、台帳（`~/ai` の `models.lock.toml`）に写す `[[model]]` の行を出す。`~/ai` のリポジトリは書き換えていない
- VAE とテキストエンコーダーはいつも置く。プロンプト拡張は `--with-expander` のときだけ
- 引数なしで流すと `H3_IMAGE_MODELS`（dekahamuntu は `int8 w4a8`）を置く。GGUF も ComfyUI-GGUF も置かない

#### 手順（本番で流したもの）

ComfyUI を起動し直す前に、ComfyUI のキューが空で、art-studio に実行待ち・実行中のループがないことを確かめる（本人の決め。issue の「進め方」）。スクリプトが見るのはキューだけなので、art-studio のループは自分で見る（[ubuntu-server.md の「ComfyUIの更新と戻し」](ubuntu-server.md#comfyuiの更新と戻し)）。

```bash
cd ~/.config/nix-config   # この変更（スクリプトと hosts/ubuntu/dekahamuntu.env）が入っていること
# 1. キューと art-studio のループ（どちらも 0 であること）
curl -fsS http://127.0.0.1:8188/queue | jq '[.queue_running, .queue_pending] | map(length)'
sqlite3 ~/.local/share/art-studio/studio.db "select count(*) from loops where state in ('running','stopping');"
# 2. 本体を v0.45.2 へ（COMFY_REF。控えを取り、終わりに戻すコマンドを表示する）
scripts/update-comfyui-ubuntu.sh
# 3. GPU 1 も見せる（unit の差を表示してから書き、起動し直す）
scripts/install-comfyui-ubuntu.sh --unit-only
# 4. 重み（置いてあれば大きさだけ確かめる。--verify で sha256 も）
scripts/install-minimax-h3-image-ubuntu.sh
```

2. と 3. はそれぞれ ComfyUI を起動し直す（どちらもキューを確かめる。進むのはキューが空か、ComfyUI につながらないときだけ。タイムアウトや HTTP の誤りでは止まる）。3. が途中で失敗したら、原因を直して同じコマンドを流し直せば続きから適用する（印 `~/.local/state/comfyui-update/unit-apply-pending`）。dekahamuntu の `~/ComfyUI` には未追跡の `.chibihamuntu-freeze.txt` があり、前の `update-comfyui-ubuntu.sh` は「未コミットの変更」で止まった。新しい版は未追跡のファイルでは止まらない。

本番での実績（2026-11-14 UTC。日本時間は +9 時間で 11-15）:

1. 本人の art-studio のループ（231・233、計 1,200 組）が 22:14 に済み、キューもループも空の状態が 10 分続いたのを確かめてから始めた（22:24:22）
2. 22:25〜22:27: 更新の前（`e3bee7ff`）の本番で、主なレシピ 5 つを 1 枚ずつ作った（比べる元）
3. 22:27:02〜22:27:14: `update-comfyui-ubuntu.sh`。実機の `~/.config/nix-config` は develop のままで触らず、このブランチのスクリプトを `~/issue5-stage/nix-config/` に写して流した（値は写した dekahamuntu.env の `COMFY_REF=v0.45.2`）。控えは `~/.local/state/comfyui-update/20261114T222702Z-e3bee7ffc`（describe は v0.42.0-7-ge3bee7ffc）。8 つのパッケージが入れ替わり、起動し直しから 9 秒で応答して `comfyui_version 0.45.2`
4. 22:30:17〜22:30:26: `install-comfyui-ubuntu.sh --unit-only`。出力に「ComfyUIに見せるGPU: 0,1」「既定のデバイス: cuda:0 = NVIDIA GeForce RTX 5060 Ti」。unit の差は `CUDA_VISIBLE_DEVICES=0` → `0,1` の 1 行。6 秒で応答し、`/system_stats` の devices に cuda:0・cuda:1 が出た
5. 22:33:17〜22:50:31: H3 Image の A/B。22:51〜23:00: Qwen との同居の確かめ。23:01〜23:13: GGUF の A/B（写しを 2 枚見せる形で起動して計った。本番の ComfyUI のモデルは降ろしておいた）。23:51〜翌 00:13（日本時間 8:51〜9:13）: GGUF の 2880²・4096² の A/B（写しを `CUDA_VISIBLE_DEVICES=1,0` で起動。Q5_K_M は 4096² が OutOfMemoryError で載らなかった。値は ai-server-placement.md）
6. 4. の重みは 17:29〜17:31 UTC に置いてあった（ここでは流し直していない）
7. 計測のあいだの温度の最大は 74℃（GPU 0、4096²）、電力の最大 183W、fan2go は全部の回で active（failsafe なし）。83℃ には届いていない。sudo は使っていない。chibihamuntu には触っていない

#### 戻し方

```bash
# 本体と依存を e3bee7ff の控えに戻す
scripts/update-comfyui-ubuntu.sh --restore ~/.local/state/comfyui-update/20261114T222702Z-e3bee7ffc
# GPU 0 だけに戻す
COMFY_CUDA_DEVICES=0 scripts/install-comfyui-ubuntu.sh --unit-only
```

- 控え `~/.local/state/comfyui-update/20261114T222702Z-e3bee7ffc` は戻すのに要るので残してある。この控えには `comfy_dir` がない（確かめを足す前に取った）ので、`--restore` は警告を 1 行出して `~/ComfyUI` のものとして戻す。いまのスクリプトで取る控えには `comfy_dir` が入り、別の場所の控えでは止まる
- 写し（`COMFY_DIR=~/issue5-stage/ComfyUI … --no-restart`）で流したときに表示される戻すコマンドには、`COMFY_DIR=…` と `--no-restart` が付く（そのまま貼っても本番は変わらない）
- 戻したままにするなら、`hosts/ubuntu/dekahamuntu.env` の `COMFY_REF`・`COMFY_CUDA_DEVICES` も直す（直さないと、次に流したとき v0.45.2・`0,1` に戻る）
- `--sleep-idle-seconds` を外すなら、env の `QWEN_SLEEP_IDLE_SECONDS` の行を空にして `install-qwen38-ubuntu.sh`。env は `: "${VAR:=値}"` なので、環境変数で空を渡しても 600 になる（空の値も上書きされる）
- 戻しで戻らないもの: `freeze.txt` にない（新しい版で足された）パッケージは消さない。ComfyUI の `user/`（設定・ワークフロー）は触らない。新しいフロントエンドで保存し直したワークフローを古いフロントエンドで開けるかは確かめていない
- 置いた重みは戻しても残る（消すなら手で消す）

戻しは先に、本番に触れない写しで確かめた（`~/issue5-stage/ComfyUI`。本番の `~/ComfyUI` を `git clone` し、本番の `uv pip freeze` から venv を作った。作り直した venv の freeze は本番と一致した）。写しで、新しい `update-comfyui-ubuntu.sh --no-restart`（`COMFY_REF=v0.45.2`）→ `update-comfyui-ubuntu.sh --restore <控え> --no-restart` と流し、戻したあとの commit が `e3bee7ff`、`uv pip freeze` が本番の freeze と 1 行も違わないことを確かめた。`--restore` の `uv pip install -r freeze.txt` は、`--extra-index-url https://download.pytorch.org/whl/cu130 --index-strategy unsafe-best-match` を付けないと「certifi was found on …/whl/cu130, but not at the requested version」で失敗した（実機で見た。スクリプトには入っている）。本番では戻していない。

#### llama との同居

決めたこと: Router（`qwen38.service`）は止めない。

1. **使い終わったモデルは自動で降ろす**: `QWEN_SLEEP_IDLE_SECONDS=600`（dekahamuntu.env）→ unit の `--sleep-idle-seconds 600`。Qwen は使い終わって 10 分で降りるので、ふだんは「Qwen が載ったまま H3 Image（B）を投げる」状態にならない
2. **Qwen が載っているときに H3 Image を使うなら**: `ai-mode image-dual` で Qwen のモデルを降ろす（switch の前は下の `/models/unload` の curl）か、A の形（`Select CLIP Device` なし、か `default`。w4a8 が速い）のワークフローを使う
3. **載ったまま B を投げると、黙って遅くなるのではなく、OutOfMemoryError（device 1）で止まる**（1 枚目は通ることがある）。Qwen は落ちない
4. H3 Image（B）を使ったあとは、何もしなくても Qwen を読み込める（`ai-mode split` は要らない）

| `ai-mode` | 動く unit | すること |
|---|---|---|
| `split`（既定） | comfyui・qwen38 | ComfyUI に `/free`（モデルを降ろさせる。実行中のものが終わってから）。B のテキストエンコーダーの重みは RAM にあるので、これは主に RAM を Qwen（Flash-Next は RAM に約 52GB）に空ける意味になる |
| `image-dual` | comfyui・qwen38 | Qwen のモデルを `/models/unload` で降ろす（Router は止めない。次に問うと読み込み直す）。GPU 1 を H3 Image のエンコードに空ける。Router の unload は停止を頼むだけで戻るので、`/models` の status が全部 `unloaded` になるまで待ってから戻る（上限 60 秒、`AI_MODE_UNLOAD_TIMEOUT`）。Router に聞けない・unload を頼めない・上限までに降りないときは終了コード 1（その場合は H3 Image を投げない） |
| `llm-dual` | qwen38-dual | 2 枚を束ねた Qwen（前と同じ） |

`image-dual` と `split` の `/free` は `home/hosts/dekahamuntu.nix` に入れたが、home-manager switch をしていないので、実機の `ai-mode` はまだ古い（switch は本人がやる）。それまでの手での代わり（どちらも実機で使って確かめた）:

```bash
# Qwen のモデルを降ろす（image-dual の代わり）。unload は頼むだけで戻るので、
# 下の /models の status が unloaded になるのを見てから H3 Image を投げる
curl -fsS -H 'Content-Type: application/json' -d '{"model":"<モデル名>"}' http://127.0.0.1:8080/models/unload
curl -fsS http://127.0.0.1:8080/models | jq -r '.data[] | "\(.id) \(.status.value)"'
# ComfyUI のモデルを降ろす（split の /free の代わり）
curl -fsS -X POST -H 'Content-Type: application/json' -d '{"unload_models":true,"free_memory":true}' http://127.0.0.1:8188/free
```

sleep-idle で確かめたこと（2026-11-14 UTC）:

- 入れる前: 一度読み込んだモデルは自分では降りなかった（本人が試した Uncensored 版が約 7 時間、GPU 1 に 14.5GB 載ったままだった。最後の問いは 10:23 UTC = 日本時間 19:23）
- 別のポートの試し（`--sleep-idle-seconds 45`）: Router の引数が子プロセスに渡り、放置 45〜60 秒で子が sleeping になった。GPU 1 は 14,474 → 166MiB、子の RSS は 22.6GB → 0.9GB。次の問いは 11.4 秒で答えが返った。Router の `/models` の status は `sleeping`。`/models` を 12 秒おきに見ていても sleeping になった（見るだけでは放置の時計は戻らない）
- 本番の unit（`install-qwen38-ubuntu.sh` を流した。最後の Tailscale Serve の段は前と同じく「Access denied」で、公開は前のまま 8443 → 8080）: 18:05:21 UTC（日本時間 11-15 3:05）に UD-Q3_K_XL へ「1+1 は？」→「2」（読み込み込み 47 秒、GPU 1 14,903MiB）。そのまま 30 秒おきに見て、570 秒まで loaded、600 秒で `sleeping`・GPU 1 299MiB。次の問い「2+3 は？」→「5」が 8 秒。`/models/unload` で 138MiB（138MiB は写しの ComfyUI の分）

本番の B の形での同居（22:51〜23:00 UTC = 日本時間 7:51〜8:00）:

1. H3 Image（B）を使ったあと（GPU 1 に 336MiB）、何もせずに Qwen へ問う → 読み込めて答えた。UD-Q3_K_XL は「1+1 は？」→「2」、読み込み込み 46 秒、GPU 1 は 15,103MiB。Uncensored 版は 39 秒、14,807MiB
2. Qwen が GPU 1 に載ったまま（空き約 1.2〜1.5GB）、H3 Image（B）をプロンプトを変えて続けて投げる → 不安定だった。どれもノードは `MiniMaxH3ImageConditioning`、誤りは `torch.OutOfMemoryError: Allocation on device 1 would exceed allowed memory. (out of memory)`
   - UD-Q3_K_XL が載っているとき: 1 枚目は通った（26.0 秒）、2 枚目は 4.9 秒で誤り
   - Uncensored 版が載っているとき: 1 枚目は 11.9 秒で通り、2 枚目は 0.6 秒で誤り
   - int8 でも 1 枚目は 32.6 秒で通り、2・3 枚目は 0.3 / 3.9 秒で誤り
   - Qwen が答えている最中に投げると、0.3〜1.5 秒で誤り
   - 誤りのあと、ComfyUI は GPU 0 のモデルも降ろす（次は読み込みから）
3. そのあいだも Qwen は落ちず、誤りのあとの問い（「2+3 は？」→「5」）に 4〜18 秒で答えた
4. Qwen を載せたまま A の形（`Select CLIP Device` なし、w4a8）なら 4 枚とも通った: 21.3（1 枚目）/ 18.7 / 18.6 秒、Qwen が長い答えを書いている最中は 28.1 秒。GPU 1 は 15,071MiB のまま動かない。Qwen なしの A（12.0 秒）より遅いのは、RAM を Qwen（約 52GB）が使い、ComfyUI が重みを RAM に持てず（RSS 約 6GB）、プロンプトを変えるたびに読み直すため（GPU 0 の最小 4.2〜4.3GB）
5. RAM: B の ComfyUI は RSS 23〜28GB、Flash-Next は約 52GB を RAM に置く（64GB の機械）。両方を載せると片方のページキャッシュが追い出されて読み直しが起きる（4. の遅さ、1. の読み込み 46 秒）

写しでの取り合いの試し（1 枚の GPU にテキストエンコーダーも本体も載せたときの結果。B の形ではない）:

- Qwen（Uncensored 版、14,817MiB）が載っている GPU で H3 Image を投げると、1.2 秒で `MiniMaxH3ImageConditioning` が `torch.OutOfMemoryError: Allocation on device 0 would exceed allowed memory. (out of memory)` で止まった（写しは GPU 1 だけを見せて動かしたので、ここの device 0 は GPU 1）
- 逆に、写しの ComfyUI がその GPU に 15.5GB 載せているときに Qwen に問うと、1 秒で HTTP 500 `{"error":{"code":500,"message":"model name=… failed to load","type":"server_error"}}`（journal に `cudaMalloc failed: out of memory`）。Router は落ちず、空けたあとの問いには答えた。本番の B では ComfyUI が GPU 1 に重みを載せたままにしないので、この形にはならなかった（上の 1.）

気をつけること:

- Qwen が載っているあいだ（最後の問いから 600 秒）は、B のワークフローが OutOfMemoryError で止まることがある。H3 Image を続けて作るなら、先に `ai-mode image-dual`（か `/models/unload`）
- 何も載せていないときの ComfyUI は、GPU 0・GPU 1 とも 138MiB（CUDA のコンテキスト）。一度 GPU 1 を使ったあとは 304〜348MiB 残る。この状態で Flash-Next（UD-Q3_K_XL・Uncensored 版）は今の n-cpu-moe のまま GPU 1 に読み込めた（上の 1.）
- RAM は取り合う。Qwen と H3 Image（B）を同時に重く使うと、どちらかが読み直しで遅くなる

#### 確かめたこと

更新の前後で絵が変わらないか（art-studio の主なレシピ 5 つ、同じ種、1 枚ずつ）:

- レシピの設定は art-studio のループが実際に投げた形（`studio.db` の `loops.prompt`）を使い、プロンプトだけ風景・静物に替えた。保存は inbox の外
- 写し（`~/issue5-stage/ComfyUI`、GPU 1）で先に確かめ、本番で同じことをした。本番は、更新の前（`e3bee7ff`）、更新のあと GPU 0 だけ、2 枚見せたあと、の 3 回

本番（秒は実行時間、読み込み込み）:

| レシピ | モデル | e3bee7ff | v0.45.2（GPU 0 だけ） | v0.45.2（2 枚見せたあと） | 絵 |
|---|---|---|---|---|---|
| SDXL（ChibihamRecipeSDXL、hires あり） | rinFlanimeIllustrious_v50 | 23.7 | 23.8 | 24.2 | 3 つとも画素が同じ（差の最大 0） |
| Anima（ChibihamRecipeAnima） | anima_turboV11 | 12.8 | 14.6 | 14.7 | 同じ |
| Anima 2.9B | Anima-2.9B-preview-v1 | 30.6 | 31.2 | 31.2 | 同じ |
| Qwen-Image 2.1（qwen-image スキルと同じワークフロー） | — | 23.1 | 23.1 | 23.0 | 同じ |
| MOSS-Image（moss-image スキルと同じワークフロー） | — | 25.9 | 25.9 | 25.8 | e3bee7ff と v0.45.2 で差の平均 0.195/255・最大 7（写しと同じ。見た目は同じ）。v0.45.2 の 2 つは同じ |

- 本番は画素で比べた（取り出した PNG が保存ノードのものかプレビューのものかでメタデータが違うことがあるため）。写しでは SDXL・Anima・Anima 2.9B・Qwen-Image の PNG がバイト単位で同じ（sha256 一致）だった
- MOSS の差は、上流で MOSS のコードが変わったため（「Lower peak MOSS memory a bit (#17338)」など）
- 2 枚見せたあと、5 つとも GPU 1 は 138MiB のまま（最小・最大・終わったあとが同じ）。GPU 0 だけを使った
- 写しの秒（v0.45.2 / e3bee7ff）: SDXL 24.1 / 24.3、Anima 14.6 / 15.6、Anima 2.9B 32.2 / 32.2、Qwen-Image 23.9 / 22.8、MOSS 26.0 / 22.1（GPU 0 では本人のループが回っていた）。どれも 1 回ずつ

拡張と画面（本番、更新のあと）:

- `IMPORT FAILED` は 0 件（`--enable-manager` 付き）。読み込めた拡張: chibiham-image-prompt・chibiham-llm-prompt・chibiham-lora-meta・chibiham-recipe・chibiham-save-meta、ComfyUI-Anima-3.8B-LoRA-Bridge、comfyui-anima-3-8B、comfyui-custom-scripts、comfyui-easy-use、comfyui-image-saver、comfyui-impact-pack、comfyui-impact-subpack、comfyui-kjnodes、comfyui-lora-manager、comfyui-wd14-tagger、comfyui_ipadapter_plus、comfyui_smznodes、comfyui_ultimatesdupscale、rgthree-comfy。`[smZNodes] Failed to install compel.` は前の版の本番のログにも出ている（更新とは関係ない）
- `/object_info` に 1,854 ノード（ChibihamRecipeAnima・ChibihamRecipeSDXL・ChibihamSaveImageMeta・MiniMaxH3ImageConditioning・SelectCLIPDevice がある）
- art-studio は `http://127.0.0.1:4520/` が 307 → `/?st=inbox` で 200

H3 Image（本番、B）: テキストエンコーダーを GPU 1 で回し、本体を GPU 0 に載せて 2048²〜4096² で出た。プロンプトを変えた 2 枚目以降で GPU 0 の VRAM は 15,470〜15,502MiB から下がらず、本体の入れ替えは起きなかった（A では 3.2〜3.7GB まで下がる）。秒数・VRAM・RAM の表は [ai-server-placement.md](ai-server-placement.md#実測2026-11-14-minimax-h3-imagedekahamuntu)。

#### 残っているもの

消してよいかは本人が決める。

- 写し `~/issue5-stage/`（約 7GB。このブランチのスクリプトの写し `~/issue5-stage/nix-config/` を含む）、`/tmp/issue5/`（計測の道具 `comfybench.py`・記録・絵）
- GGUF の 2 ファイル（`~/ComfyUI/models/diffusion_models/MiniMax-H3-Image-Pruned-Q5_K_M.gguf`・`…Q4_K_M.gguf`、14,077,892,224 + 11,573,106,304 bytes = 約 25.7GB）。使わないので消してよい候補。消すなら `rm ~/ComfyUI/models/diffusion_models/MiniMax-H3-Image-Pruned-Q{5,4}_K_M.gguf`
- 控え `~/.local/state/comfyui-update/20261114T222702Z-e3bee7ffc`（戻すのに要るので残す）
- 計測の絵と表は spec（`docs/specs/5/h3-image/index.html`。git に入らない使い捨て）にある

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
| comfyui.service | 0,1 | 既定で起動。既定のデバイス（`cuda:0`）は GPU 0 で、今までのワークフローは GPU 0 だけを使う。GPU 1 はノードで指定したもの（MiniMax H3 Image のテキストエンコーダーの計算、`Select CLIP Device`。重みは RAM に置かれ、GPU 1 はエンコードのあいだだけ使う）だけ（[2-9](#2-9-comfyui-の更新v0452と-minimax-h3-image)）。2026-11-14 に `0` から `0,1` にした |
| qwen38.service | 1 | 既定で起動（ComfyUI とは独立）。600 秒問いのなかったモデルを降ろす（`QWEN_SLEEP_IDLE_SECONDS`）。モデルが載っているあいだは、H3 Image（B）のエンコードが GPU 1 で OutOfMemoryError になる（`ai-mode image-dual` で降ろす） |
| qwen38-dual.service | 0,1 | `ai-mode llm-dual`（既定にしない。`ai-mode split` で戻す）。comfyui・qwen38 と排他。`--split-mode layer --tensor-split 39,10`（UD-Q3_K_XL の n-cpu-moe 33 と組。1,1 は後ろの GPU に寄って落ちる） |
| applio.service | 0 | comfyui・qwen38-dual と排他 |
| diffusion-pipe の学習 | 0 | `TRAIN_CUDA_DEVICES=0,1` にすると 2 枚のデータ並列（`--num_gpus=2`） |

番号は `CUDA_DEVICE_ORDER=PCI_BUS_ID` で `nvidia-smi` と揃える。

GPU LED: カードは Palit GeForce RTX 5060 Ti Infinity 3 16GB（サブシステム 1569:f328。2026-11-13 に分かった）。OpenRGB で消せるかをまだ確かめていないので、消灯は切ってある（`GPU_LED_OFF=0`）。同じカード 2 枚は名前で区別できないので、`turn-off-gpu-led` は `GPU_LED_COUNT=2` なら一覧の番号で 2 枚とも消す。OpenRGB がそのカードを扱えるかを確かめてから 1 にする。

### PCIe の帯域

ASUS の製品ページによれば、ProArt B850 には CPU 直結の PCIe 5.0 x16 スロット（SafeSlot）が 2 本あり、2 本とも使うと x8/x8 になる。ほかに PCIe 4.0 の x16 形状のスロット（x4 動作。M.2_3 を使うと無効）が 1 本ある。RTX 5060 Ti はもともと x8 のカードなので、2 枚を上の 2 本に挿せば、どちらも **PCIe 5.0 x8（片方向 約 32GB/s、PCIe 4.0 x16 と同じ程度）** で動く。実機では 2 枚とも幅 x8、最大 Gen5（アイドルでは 2.5GT/s に下がる。負荷時の current は未確認。下の「[実機で確かめた値](#実機で確かめた値)」）。3 本目（x4）に挿すと帯域が 1/2 になるので使わない。

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

### ケースファン（GPU の温度で回す）

使うのは CPU より GPU が多いので、ケースファンを GPU の温度に合わせて回す。CPU のクーラーのファン（CPU_FAN）は BIOS のまま触らない。

ケースファンは合わせて 10 個（本人の答え）: Thermalright TL-C14C（140mm）×7 と TL-C12C（120mm）×3。底 140mm ×3 吸気・側面 120mm ×3 吸気・天面 140mm ×3 排気・背面 140mm ×1 排気（吸気 6・排気 4）。fan4 = 側面の 120mm ×3（本人が確認）。140mm の 7 個が fan1・3・6 にどう分かれているかは未確認。仕様・食い違い・電流は [machines.md](machines.md#dekahamuntu)。

| 項目 | 決めたこと |
|---|---|
| 道具 | [fan2go](https://github.com/markusressel/fan2go) 0.15.0（公式の配布バイナリの `fan2go-linux-amd64-no-nvml` を、版と SHA256 で固定して `/usr/local/bin` に置く）。設定は YAML で宣言でき、hwmon のファンと、コマンドの出力の温度を組み合わせられる |
| 回し方 | ケースファン = max(GPU の曲線, CPU の曲線)。GPU の入力は 2 枚の温度の最大 |
| GPU の温度 | `case-fan-gpu-temp`（root 所有、`/usr/local/sbin`）が `nvidia-smi` で読み、最大をミリ度で出す。fan2go の NVML（GPU を直に読む）は使わない |
| 揺れを抑える | 温度は 1 秒ごとに読み、直近 10 回の平均で曲線を引く。PWM は 1 回（200ms）に 3 まで動かす（0→255 に約 17 秒） |
| 止めない | `neverStop`。最低は `CASE_FAN_MIN_DUTY`（30%） |
| 止めたとき・落ちたとき | BIOS の制御に戻す。fan2go 自身（`controlMode.onExit: restore`）と、unit の `ExecStopPost`（`case-fan-restore-bios`。入れたときに読んだ `pwmN_enable` の値に戻す。強制終了のときの保険） |
| GPU の温度が読めないとき | `nvidia-smi` の失敗・1.2 秒で返らない（TERM を無視しても 0.3 秒後に KILL。fan2go の cmd センサーの時間切れ 2 秒より手前で終える）・枚数が `NVIDIA_EXPECTED_GPUS`（2）でない・数でない値のとき、100℃ を出す。曲線は 83℃ で 100% なので全開になる。GPU の曲線の最後の点が 100% でなければ、入れるスクリプトが止まる（2026-11-14、実装レビューの指摘で足した。dekahamuntu の設定で作られる YAML は変わっていないので、入れ直しは要らない） |
| 値の置き場所 | `hosts/ubuntu/dekahamuntu.env` の `CASE_FAN_*`（意味は `hosts/ubuntu/README.md`）。スクリプトの既定は切（`CASE_FAN_CONTROL=0`）。dekahamuntu は 1 |

曲線（たたき台。`CASE_FAN_GPU_CURVE`・`CASE_FAN_CPU_CURVE`。「温度:デューティ%」）:

| GPU（2 枚の最大） | デューティ | | CPU（Tctl） | デューティ |
|---|---|---|---|---|
| 45℃ 以下 | 30% | | 60℃ 以下 | 30% |
| 60℃ | 45% | | 75℃ | 45% |
| 70℃ | 65% | | 85℃ | 65% |
| 78℃ | 85% | | 95℃ | 100% |
| 83℃ 以上 | 100% | | | |

点の間は直線でつなぐ。GPU は subako の見張りの警告（85℃）の手前で全開にする。CPU の曲線は緩くしてある（Tctl は負荷ですぐ上がり、CPU は自分のクーラーで冷やすので、ケースファンは補助）。

なぜ fan2go か:

- lm-sensors の `fancontrol` は hwmon の温度しか読めない。NVIDIA の GPU の温度は hwmon に出ない
- CoolerControl も GPU の温度でケースファンを回せるが、設定が Web の画面寄りで、このリポジトリから宣言しにくい
- Nix（Home Manager）では入れない。root のサービスがユーザーの Nix のストアのパスを指すと、世代の掃除（GC）で消えうる。ADR 0001 の境界どおり、OS のサービスはスクリプトで入れる。Home Manager の出力は変わらない
- GPU の温度を fan2go の NVML でなくコマンドで読むのは、読めないときに全開へ倒すことをこちらで決められるから（0.15.0 は、センサーが読めないと最後の平均のまま動く。全開に倒す `onSensorFailure` は、まだリリースされていない版にしかない）。NVML を使わないので、配布バイナリも NVML なしの版にした

#### Super I/O（ファンのヘッダーの制御）

ProArt B850-CREATOR WIFI NEO のファンのヘッダーは、Super I/O（Nuvoton）が持つ。ドライバは `nct6775`、hwmon の name は `nct6799`（2026-11-13 に実機で確かめた）。

- Ubuntu は `nct6775` を自動で読み込まない（読み込む前は hwmon に pwm も fan もない）。入れるスクリプトが `/etc/modules-load.d/case-fan-control.conf` に書く（実機で `nct6775` が書かれたことを確かめた）
- カーネル 7.0 の `nct6775` の「ASUS の WMI 経由で読むボード」の一覧に、このボードはない（ProArt は B550/B650/B660/B760/X570/X670E/X870E/Z490/Z690/Z790 だけ）。なので ISA を直に読みに行き、BIOS（ACPI）がその場所を握っていると掴めない。BIOS 1002・カーネル 7.0.0-43-generic では、`acpi_enforce_resources=lax` なしで掴めた（2026-11-13）
- BIOS やカーネルを上げて掴めなくなったときの回避は起動オプション `acpi_enforce_resources=lax`（ACPI と同じ I/O をドライバも触ることを許す。BIOS とドライバが同時に触ると読み違いが起きうる。広く使われている回避）。`--probe` が要りそうと言ったときだけ、本人が `CASE_FAN_ACPI_LAX=1` にする
- `asus-ec-sensors`・`asus_wmi_sensors` は温度などを読むだけで、ファンを操れない（このボードも一覧にない）

#### 本人がやる順

```bash
cd ~/.config/nix-config

# 1. 調べる（読むだけ。sudo 不要）
scripts/install-case-fan-control-ubuntu.sh --probe

# 2. nct6775 を一時的に読み込んでから調べる（sudo。再起動で消える。ファンは変えない）
scripts/install-case-fan-control-ubuntu.sh --probe --load-module
#    「見立て」が次のどれか:
#    ✓ Super I/O nct67xx を掴めていて、pwm がある → 3. へ
#    ⚠ ACPI が握っていて掴めない → 本人が決めて CASE_FAN_ACPI_LAX=1 → 5. を流す（GRUB を書き換えて止まる）→ 再起動 → 2. から
#    ⚠ Super I/O が見つからない → 執事に出力を渡す（nct6683 の系統か、このやり方では操れない）

# 3. どのチャネルがどのファンか（--probe の fanN の RPM が 0 でないものが、つながっているヘッダー）
#    CPU_FAN がどれかを必ず確かめる。そのチャネルを 10 秒だけ全開にして RPM を見せ、元に戻す（sudo）
#    （env の CASE_FAN_HWMON を使う。dekahamuntu.env は nct6799。--probe の name と違えば、先に env を直す。
#     空なら pwm のある Super I/O の hwmon が 1 つのときそれを使う。--probe の「--identify が使う hwmon」の行で分かる）
scripts/install-case-fan-control-ubuntu.sh --identify 2

# 4. hosts/ubuntu/dekahamuntu.env を埋める
#    CASE_FAN_HWMON=<--probe の name、例 nct6799>
#    CASE_FAN_CHANNELS="<ケースファンのチャネル。CPU_FAN は入れない>"
#    3pin（--probe で mode=0）のファンなら CASE_FAN_MIN_DUTY を 50 前後に
#    CASE_FAN_CONTROL=1
scripts/install-case-fan-control-ubuntu.sh --print-config   # 書く予定の fan2go.yaml を見る（sudo 不要）

# 5. 入れる（sudo）。GPU が暇なときに流す（下の「初回の解析」）
scripts/install-case-fan-control-ubuntu.sh
```

入れるスクリプトがすること: `libsensors5`（なければ apt）、`/etc/modules-load.d/case-fan-control.conf`、fan2go を止めた状態で BIOS の `pwmN_enable` を `/etc/fan2go/case-fan-restore.conf` に記録、fan2go と 2 つのスクリプトを置く、`/etc/fan2go/fan2go.yaml` を書いて `fan2go config validate` を通す（通らなければ何も起動しない）、`fan2go.service` を有効にして起動、15 秒後の状態を出す。

初回の解析: fan2go 0.15.0 は、初めて見るファンの PWM と RPM の関係を一度だけ測る（ファンを止めたり全開にしたりする）。dekahamuntu では 4 チャネルが同時に始まり、全体で約 1 分 45 秒で終わった（下の「実機で確かめた値」）。結果は `/var/lib/fan2go/fan2go.db` に残り、2 回目からは測らない。測っているあいだは温度で回らないので、ComfyUI・LLM を動かしていないときに入れる。

#### 確かめ方

```bash
systemctl status fan2go                           # active (running)
journalctl -u fan2go -f                           # 初回の解析の進み、警告
cat /run/fan2go/case-fan-gpu-temp.status          # 「ok <最大の℃> gpus=2」。failsafe なら GPU が読めず全開
scripts/install-case-fan-control-ubuntu.sh --probe   # pwmN の値（enable=1 は fan2go が操っている）と RPM
sudo fan2go -c /etc/fan2go/fan2go.yaml curve      # 曲線の今の値（fan2go の CLI）
```

GPU に負荷をかけて（ComfyUI で数枚生成など）、`nvidia-smi` の温度が 60℃・70℃ を超えたあたりで pwm が上がり、負荷を止めると 10〜20 秒かけて下がることを見る。

#### 戻し方

```bash
sudo systemctl stop fan2go        # 一時的に BIOS の制御へ（起動すればまた操る）
sudo systemctl disable --now fan2go   # 次の起動からも操らない
scripts/install-case-fan-control-ubuntu.sh --uninstall   # 全部外す（unit・設定・fan2go・modules-load・GRUB の lax）。そのあと env の CASE_FAN_CONTROL=0
```

`CASE_FAN_ACPI_LAX` だけ戻すときは、env を 0 にして入れるスクリプトを流す（GRUB の drop-in を消して `update-grub`。次の起動から）。

#### 実機で確かめた値（2026-11-13）

本人が入れたときの出力と、読むだけで見た値。

- 環境: ProArt B850-CREATOR WIFI NEO、BIOS 1002、カーネル 7.0.0-43-generic。起動オプションに `acpi_enforce_resources=lax` はない。hwmon の name は `nct6799`
- `/etc/modules-load.d/case-fan-control.conf` に `nct6775` が書かれた
- `fan2go config validate` が通った（一時の設定 `/etc/fan2go/fan2go.new.yaml`）。`fan2go.service` は 10:18:55 UTC に active (running)、再起動 0 回、メモリ約 13MB
- systemd の制限（`MemoryDenyWriteExecute`・`SystemCallFilter` など。公式の unit のまま）の中で `nvidia-smi` が動いた。`/run/fan2go/case-fan-gpu-temp.status` は「ok 33 gpus=2」
- pwm は 1・2・3・4・6・7（pwm5 はない）。`pwmN_mode` はすべて 1（PWM。4pin の制御）。DC（3pin）のチャネルはない
- 入れる前の BIOS の `pwmN_enable` は、1・3・4・6 とも 5（`/etc/fan2go/case-fan-restore.conf` に `nct6799 <ch> 5` と記録された）
- `pwmMap: identity`・`setPwmToGetPwmMap: identity` のままで動いた（ログに「Using identity pwm map」）

チャネル:

| チャネル | 役割 | 制御 | PWM 31/255（解析の途中） | PWM 77（30%。解析のあと、GPU 33℃・28℃ のアイドル） | max の境の閾値（fan2go の threshold） |
|---|---|---|---|---|---|
| 1 | ケースファン（140mm。位置は未確認） | fan2go（`pwm1_enable=1`） | 406 RPM | 約 530 RPM | 1356.6 RPM |
| 2 | CPU のクーラー（本人の見分け。「たぶん」）。約 830 RPM | BIOS のまま（`pwm2_enable=5`） | — | — | — |
| 3 | ケースファン（140mm。位置は未確認） | fan2go（`pwm3_enable=1`） | 435 RPM | 約 520 RPM | 1318.6 RPM |
| 4 | ケースファン（側面の 120mm ×3。本人が確認、2026-11-13） | fan2go（`pwm4_enable=1`） | 529 RPM | 約 660 RPM | 1475.3 RPM |
| 5 | pwm がなく回転数だけ。約 840 RPM（2 とほぼ同じ回転数） | — | — | — | — |
| 6 | ケースファン（140mm。位置は未確認） | fan2go（`pwm6_enable=1`） | 390 RPM | 約 537 RPM | 1369.9 RPM |
| 7 | RPM 0 | — | — | — | — |

- max の境の閾値は fan2go が「threshold」と出した値で、最大の回転数そのものではない
- 30%（PWM 77）で 4 チャネルとも回り続けている。`CASE_FAN_MIN_DUTY=30` のままでよい

初回の解析:

- 4 チャネルが同時に始まった。設定は `runFanInitializationInParallel: false` だが、ログでは 4 チャネルとも 10:18:58 に始まった
- 1 チャネルあたり 1 分 40 秒〜1 分 44 秒。全体でも約 1 分 45 秒（10:18:58 → 10:20:42）
- 結果: 4 チャネルとも「start/min boundary detected at PWM 0」（PWM 0 でも止まらない）、「max boundary confirmed at PWM 255」。解析の境は Start 1・Max 255、設定の上書きのあと Min 77・Start 77・Max 255

負荷をかけたとき（執事が確かめた。10:26〜10:29 UTC）:

- GPU 0 に約 160 秒の計算の負荷をかけた。GPU の温度は 33℃ → 70℃
- pwm 1・3・4・6 が 77 → 164 に上がり、約 990〜1,180 RPM
- 曲線（70℃ で 65% = PWM 約 166）とほぼ合う
- 負荷が消えて 30 秒で pwm 89 まで下がった
- pwm2（CPU のクーラー）は BIOS のまま変わらなかった

2 枚の GPU が同時に働いたとき（ComfyUI で画像を作りながら Flash-Next を回した計測。2026-11-13 15:42〜16:18 UTC、10 秒おき 218 回の記録の最大。[ai-server-placement.md](ai-server-placement.md#comfyui-で画像を作りながらの同居dekahamuntu2026-11-14)）:

- GPU 0（画像）72℃・180W、GPU 1（LLM）44℃・82W、CPU の Tctl 82℃（画像だけのときは 64〜68℃）
- pwm 1・3・4・6 は最大 168〜169（約 66%）。回転数は fan1 1,019・fan3 1,028・fan4 1,201・fan6 1,051 RPM。CPU クーラーのファン（fan2）は最大 2,061 RPM
- `case-fan-gpu-temp.status` はずっと ok、fan2go は active のまま。終わったあと pwm は 77（30%）に戻った

#### まだ確かめていないこと

- 83℃ 以上で全開（PWM 255）になること（GPU は 72℃ までしか上がっていない。2 枚が同時に働いたときも同じ）
- `systemctl stop fan2go` で BIOS の制御（`pwmN_enable=5`）に戻ること、起動し直したときに解析をやり直さないこと
- 再起動のあと、`nct6775` が自動で読み込まれ、fan2go が自分で立ち上がること
- GPU が読めないとき（failsafe）に全開になること（実機では起こしていない）
- チャネル 2 が CPU のクーラーという見分け（本人「たぶん」）と、fan5 が CPU_OPT で 2 に連動しているという見込み
- 実機の `/usr/local/sbin/case-fan-gpu-temp` はまだ古い版（`timeout -k 0.5 1.5`）。新しい版（`-k 0.3 1.2`）にするには入れるスクリプトの流し直しが要る（本人に頼んである。2026-11-13）

### RAM（DDR5 64GB）

- chibihamuntu と同じ 64GB。swap はインストーラの既定（`/swap.img` 8GB）のままでよい。hugepages は使っていない（llama.cpp は mmap、PyTorch は既定）
- Qwen3.8-Flash-Next（UD-Q3_K_XL、約 87GB）は、ほかに RAM を使うものがアイドルなら収まる（2026-11-13 の実測）。温まったあとの llama-server の RSS は 1 枚 54.5GB（うち mmap 51.8GB）、束ね 41.2GB（38.4GB）で、問いのあいだのディスクの読みはほぼ止まる。束ねるとエキスパートを多く GPU に置けるぶん、RAM が約 13GB 少なく済む
- 1 枚で ComfyUI と同居させると RAM の残りは約 5GB。ほかのプロセスに 16〜20GB を使われると、モデルのページキャッシュが追い出され、問いのたびに SSD を数十 GB 読み直して遅くなる（RAM の確保でまねた試し。[ai-server-placement.md](ai-server-placement.md#実測2026-11-13-qwen38-flash-next)）
- DDR5 の EXPO（メモリのオーバークロックの設定）は、4 枚挿しで不安定になりやすい。常時稼働なので、EXPO を使うなら最初にメモリの検査（memtest86+ など）を本人がする

### ネットワーク

- 有線 5GbE ×2（Realtek RTL8126、`10ec:8126`。`eno1`・`eno2`）と Wi-Fi 7（Realtek RTL8922AE、`wlp10s0`）
- RTL8126 は標準カーネルの `r8169` が 6.9 から扱う。24.04 の GA カーネル 6.8 では見えず、HWE カーネル（7.0）で `r8169` が動いた。Wi-Fi も HWE の `rtw89_8922ae` で見える。Realtek の `r8126`（DKMS）は要らない
- いまは `eno2` に有線をつないで DHCP（192.168.1.154）。`eno1` と Wi-Fi は使っていない。設定はインストーラ（cloud-init）の作った `/etc/netplan/50-cloud-init.yaml` のまま
- 雛形: [`hosts/ubuntu/dekahamuntu-netplan.yaml.example`](../hosts/ubuntu/dekahamuntu-netplan.yaml.example)（インターフェース名・MAC は実機で確かめる）。インストーラの作った設定で動いているので、置き換えていない
- Wi-Fi は、有線で足りるなら設定しない（chibihamuntu は Wi-Fi のドライバの不具合でカーネルパニックの前歴がある）

### ディスク

M.2 が 3 本（PCIe 5.0 x4 ×2、PCIe 4.0 x4 ×1）と SATA ×4 のうち、いまは NVMe 1 本（XG7000-2TB、1.9TB）だけ。

決めたこと（2026-11-12、本人）: `/` に全部置く。インストーラの既定では LV が 100GB だったので、本人が `sudo lvextend -r -l +100%FREE /dev/ubuntu-vg/ubuntu-lv` で 1.9TB に広げた。モデル（約 427GB）・art-studio の作品（約 39GB）も `/` の下（chibihamuntu と同じパス）。

---

## 実機で確かめた値

（第2段でエージェントが書く。読むだけで確かめた値）

| 項目 | 値 | 確かめた日 |
|---|---|---|
| マザーボードの型番 | ASUS ProArt B850-CREATOR WIFI NEO（DMI） | 2026-11-12 |
| CPU の型番 | AMD Ryzen 7 9700X 8-Core | 2026-11-12 |
| GPU のメーカー・型番、VRAM | NVIDIA GeForce RTX 5060 Ti ×2、各 16311MiB、VBIOS 98.06.4E.00.1B。サブシステム 1569:f328（Palit。本人の一覧では GeForce RTX 5060 Ti Infinity 3 16GB、NE7506T019T1-GB2061S）。電力の上限 180W | 2026-11-12（メーカーは 2026-11-13） |
| PCIe（GPU 0 / GPU 1） | 最大 Gen5 x8 / Gen5 x8（`pcie.link.*.max`。負荷時の current は未確認）。バス 01:00.0 / 03:00.0 | 2026-11-12 |
| `nvidia-smi topo -m` の GPU0-GPU1 | PHB | 2026-11-12 |
| P2P | 未確認 | |
| 有線 LAN のチップ・ドライバ・名前 | RTL8126 ×2、`r8169`、`eno1`・`eno2`（`eno2` を使用）。Wi-Fi は RTL8922AE、`rtw89_8922ae`、`wlp10s0` | 2026-11-12 |
| ディスク | NVMe XG7000-2TB 1 本、LVM の `/` 1.9TB | 2026-11-12 |
| ドライバの版 | 595.99.02（`nvidia-driver-595-open`）、CUDA 13.2 | 2026-11-12 |
| カーネル | 7.0.0-43-generic（`linux-generic-hwe-24.04`） | 2026-11-12 |
| powercap のゾーン | `intel-rapl:0`、`intel-rapl:0:0` | 2026-11-12 |
| ケースファン（Super I/O・チャネル） | `nct6775`（hwmon の name `nct6799`。BIOS 1002 で `lax` なし）。1・3・4・6 がケースファン（fan2go）、2 は CPU のクーラー（本人「たぶん」。BIOS のまま）。pwm はすべて mode=1（PWM）。細かい値は「[ケースファン](#ケースファンgpu-の温度で回す)」の「実機で確かめた値」 | 2026-11-13 |
| Qwen3.8-Flash-Next の n-cpu-moe・tensor-split | UD-Q3_K_XL: 1 枚（GPU 1）45、束ね 33。Uncensored 版（i1-IQ3_M）: 1 枚 42、束ね 31。束ねは `--tensor-split 39,10`。llama.cpp 0.6.0。`qwen38.service`（GPU 1）を常駐、束ねは `ai-mode llm-dual`。長い問いの温まったあと: UD-Q3_K_XL は 1 枚 入力 約 440 / 生成 約 25.6 tok/s、束ね 約 519 / 約 29.0 tok/s。Uncensored 版は 1 枚 約 477 / 約 29.4、束ね 554.5〜560.7 / 約 33.9（2 回）。細かい値は [ai-server-placement.md の「実測（2026-11-13）」](ai-server-placement.md#実測2026-11-13-qwen38-flash-next) | 2026-11-13 |

---

## dekahamuntu の状態（2026-11-12）

実機を読むだけで洗い出した（値・鍵の中身は書かない。あるかと場所だけ）。「再現」は、入れ直したときに同じ状態を作るもの。ComfyUI・Qwen・MiniMax H3 Image の行は 2026-11-14 の作業のあとに直した（[2-9](#2-9-comfyui-の更新v0452と-minimax-h3-image)）。

### スクリプト・Nix で再現するもの

| 項目 | 実機の状態 | 再現するもの |
|---|---|---|
| OS・ユーザー | Ubuntu 24.04.5、ホスト名 `dekahamuntu`、ユーザー `chibiham`（`sudo`・`power` グループ） | インストーラ（第1段の 1.）。`hosts/ubuntu/dekahamuntu.env` の `UBUNTU_USER`、`power` は RAPL のスクリプト |
| apt の基礎 | `ca-certificates`・`curl`・`git`・`openssh-server`・`sqlite3`・`xz-utils` | `bootstrap-ubuntu.sh` |
| sshd | `ssh` が有効。設定はインストーラの `sshd_config.d/50-cloud-init.conf` のまま | インストーラと `bootstrap-ubuntu.sh` |
| Nix・Home Manager | `chibiham@dekahamuntu`（`~/.ssh/config`、`~/.secrets/env.tpl`、`ai-mode`、nix-gc.timer など） | `bootstrap-ubuntu.sh`（`home-manager switch`）。実機の世代は 2026-11-11 のもの（この枝の後の commit はまだ switch していない。`ai-mode image-dual` も入っていない） |
| mise | Node.js 24、Python 3.12 | `bootstrap-ubuntu.sh` |
| シークレット | `~/.secrets/.env`（Service Account のトークン）、`~/.secrets/.env.secrets`（`update-secrets` の出力） | `bootstrap-ubuntu.sh`（トークンは本人が貼る） |
| Tailscale | `tailscale`（apt）、名前 `dekahamuntu`、operator は未設定 | `install-tailscale-ubuntu.sh`（いまの版は `--operator=$USER` も設定する） |
| Tailscale Serve | `https://dekahamuntu.<tailnet>.ts.net` → 8188、`:4520` → 4520。`:8443` → 8080（Qwen）は本人が sudo で流した（2026-11-14。tailnet から答えが返るのを確かめた）。3 つとも tailnet only | `configure-tailscale-serve-ubuntu.sh`（`TAILSCALE_SERVE=443=8188 4520=4520 8443=8080`）。443・4520 はまねのコマンドで流し、いまの `tailscale serve status` と同じになることを確かめた（8443 を足す前） |
| HWE カーネル | `linux-generic-hwe-24.04`、7.0.0-43 | インストーラで HWE を選ぶ。`install-hwe-kernel-ubuntu.sh` でも入る |
| NVIDIA ドライバ | `nvidia-driver-595-open`、`linux-modules-nvidia-595-open-generic-hwe-24.04`、595.99.02 | `install-nvidia-driver-ubuntu.sh`（`ubuntu-drivers install`）。`pciutils`・`ubuntu-drivers-common` もここ |
| RAPL | `power` グループ、`/etc/udev/rules.d/99-rapl-power.rules` | `install-rapl-power-access-ubuntu.sh`（`configure-ubuntu-hardware.sh` から） |
| ComfyUI の apt | `build-essential`・`python3.12-dev`・`ffmpeg`・`git-lfs` | `install-comfyui-ubuntu.sh` |
| linger | `Linger=yes` | `install-comfyui-ubuntu.sh`（`loginctl enable-linger`） |
| comfyui.service | GPU 0,1（`CUDA_DEVICE_ORDER=PCI_BUS_ID`・`CUDA_VISIBLE_DEVICES=0,1`。2026-11-14 に `0` から変えた）、`CC=/usr/bin/cc`、`--fast` なし。enabled | `install-comfyui-ubuntu.sh`（`COMFY_CUDA_DEVICES=0,1`、`COMFY_EXTRA_ARGS` は空）。導入済みなら `--unit-only`。`0` のときの unit は、まねのコマンドで流し、実機の unit と同じになることを確かめた（2026-11-12）。`0,1` との差は `CUDA_VISIBLE_DEVICES` の 1 行 |
| art-studio.service | unit 本体（PORT=4520、`ART_STUDIO_INBOX`、mise の node 24）。enabled | `~/ai/scripts/install-art-studio`。まねのコマンドで流し、実機の unit と同じになることを確かめた |
| art-studio の drop-in | `art-studio.service.d/dekahamuntu.conf`（`COMFYUI_URL=http://127.0.0.1:8188`、GPU 0） | `configure-art-studio-ubuntu.sh`（`ART_STUDIO_COMFYUI_URL`・`ART_STUDIO_CUDA_DEVICES`）。実機と同じ中身になることを確かめた |
| Qwen の unit（2026-11-13 に入れ、2026-11-14 に流し直した） | `qwen38.service`（GPU 1、Router、ポート 8080。enabled、`WantedBy=default.target`）、`qwen38-dual.service`（GPU 0,1、`--split-mode layer --tensor-split 39,10`、`Conflicts=qwen38.service comfyui.service`。enable しない）。どちらも `--sleep-idle-seconds 600`（2026-11-14 に足した） | `install-qwen38-ubuntu.sh`（`LLM_CUDA_DEVICES`・`LLM_DUAL_*`・`QWEN_WANTED_BY`・`QWEN_SLEEP_IDLE_SECONDS`） |
| MiniMax H3 Image の重み（2026-11-14 に置いた） | `~/ComfyUI/models/` の `vae/` に 1 つ、`diffusion_models/` に 4 つ（公式 int8・w4a8、GGUF Q5_K_M・Q4_K_M。GGUF の 2 つは使わず、消してよい候補）。テキストエンコーダー（NVFP4）とプロンプト拡張は前からあった。ComfyUI-GGUF は入れていない | `install-minimax-h3-image-ubuntu.sh`（`H3_IMAGE_MODELS=int8 w4a8`。revision・sha256 を固定。GGUF は置かない）。台帳への記入は chibiham-ai#74 |
| Qwen のプリセット（2026-11-13 に入れた） | `~/.config/llama.cpp/qwen38-models.ini`（n-cpu-moe 45 / 42）、`qwen38-dual-models.ini`（33 / 31）、`qwen38-flash-chat-template.jinja` | `install-qwen38-ubuntu.sh`（`QWEN_*_N_CPU_MOE`） |
| Qwen のモデル（2026-11-13 に取った） | `~/models/qwen3.8-flash-next`（UD-Q3_K_XL・Uncensored 版 i1-IQ3_M と各 mmproj）。27B はない | `install-qwen38-ubuntu.sh`（`QWEN_INSTALL_27B=0`） |
| ケースファン（2026-11-13 に入れた） | fan2go 0.15.0（`fan2go.service`、active (running)）、`/etc/fan2go/fan2go.yaml`・`case-fan-restore.conf`、`/etc/modules-load.d/case-fan-control.conf`（`nct6775`）。チャネル 1・3・4・6 | `install-case-fan-control-ubuntu.sh`（`CASE_FAN_*`） |

### `~/ai`（chibiham-ai）の手順で再現するもの

| 項目 | 実機の状態 | 再現するもの |
|---|---|---|
| `~/ai` | `gh repo clone` の https の clone（develop）。`lora/` の `lora.json`・`art-studio.json` は chibihamuntu から写した（学習のデータ本体は無い） | `gh repo clone chibiham/chibiham-ai ~/ai -- -b develop`。LoRA の配布の仕組みは chibiham-ai の issue の候補 |
| ComfyUI の本体とカスタムノード | 本体は v0.45.2（2026-11-14 に `e3bee7ff` から上げた。[2-9](#2-9-comfyui-の更新v0452と-minimax-h3-image)）。カスタムノードは chibihamuntu から写したもの、`chibiham-*` は `~/ai/comfyui/custom_nodes` への symlink | 本体の版は `COMFY_REF` と `update-comfyui-ubuntu.sh`（このリポジトリ）。カスタムノードは `~/ai` の README（`custom-nodes.snapshot.json` と `cm-cli restore-snapshot`、symlink） |
| ComfyUI の venv | mise の Python 3.12.16、torch 2.13.0+cu130。パッケージは chibihamuntu の freeze と同じ版から、v0.45.2 への更新で 8 つ変わった（2-9） | `install-comfyui-ubuntu.sh` は最新の torch を入れる（版は揃わない）。揃えるなら chibihamuntu の `uv pip freeze` を使う。更新の前の freeze は `update-comfyui-ubuntu.sh` の控え（`~/.local/state/comfyui-update/20261114T222702Z-e3bee7ffc/freeze.txt`）に残る |
| art-studio のビルドとモザイクの `.venv` | `node_modules`・`dist`（npm ci・build）、`.venv`（torch 2.14.1+cu130、ultralytics） | `install-art-studio`（npm は safe-chain のシム経由にする変更の案がある）と、art-studio の README の `.venv` の手順 |
| モデル | `~/ComfyUI/models`（約 427GB） | `~/ai/scripts/models restore`（R2・Civitai・HF。`update-secrets` の鍵を使う）と `models check --hash` |

### 再現できず、本人が手で行うもの

| 項目 | 実機の状態 | やること |
|---|---|---|
| インストーラでの HWE の選択・ディスクの LVM | HWE 7.0、`/` を 1.9TB に広げた | 第1段の 1.、[ディスク](#ディスク) |
| ssh の鍵 | `~/.ssh/authorized_keys` に 1 本（Mac・chibihamuntu と同じ本人の鍵）。dekahamuntu には GitHub 用の秘密鍵（`~/.ssh/id_ed25519`）は無い（`~/.ssh/config` は参照している） | インストーラの「Import SSH key」。GitHub の鍵を作るかは本人が決める |
| 1Password | Vault `dekahamuntu`、Service Account | 第1段の 0.、4. |
| GitHub | `gh auth login` 済み（`~/.config/gh/hosts.yml`、https） | 第1段の 6. |
| Claude Code・Codex のログイン | — | 第1段の 6. |
| sudo の操作 | ドライバ、apt、linger、Tailscale の認証と serve、lvextend | エージェントがコマンドを出し、本人が流す |
| Tailscale Serve の 8443（Qwen） | 本人が流した（2026-11-14。tailnet から答えが返るのを確かめた）。2026-11-13 に `install-qwen38-ubuntu.sh` の最後の段が operator なしで断られたため、手で流した | 入れ直すときも、本人が `sudo tailscale serve --bg --https=8443 http://127.0.0.1:8080` を流す（`configure-tailscale-serve-ubuntu.sh` でもよい） |
| sudoers | 追加なし（`/etc/sudoers.d` は既定のまま） | なし |
| netplan | インストーラ（cloud-init）の `/etc/netplan/50-cloud-init.yaml` のまま | なし（雛形は使っていない） |

### データ（設定ではない。写したもの）

- `~/ComfyUI/models`（chibihamuntu から rsync、sha256 で確かめた）
- `~/.local/share/art-studio`（作品の `library/`・`thumbs/` と `studio.db`。2026-11-12 に chibihamuntu から切り替えた）
- issue 5 の作業の残り（消してよいかは本人が決める）: `~/issue5-stage/`（ComfyUI の写し、約 7GB）、`/tmp/issue5/`、GGUF の 2 ファイル（約 25.7GB）。控え `~/.local/state/comfyui-update/20261114T222702Z-e3bee7ffc` は戻すのに要るので残す（[2-9](#2-9-comfyui-の更新v0452と-minimax-h3-image) の「残っているもの」）
- 作業の残り（消してよい）: `~/.local/share/art-studio/studio.db.test-20261112`、`~/.local/share/art-studio-test-20261112/`、`~/ai.rsync-20261112/`、`~/ComfyUI/output/dekahamuntu-test/`、`~/.triton/cache.nixgcc-*`、空の `~/.config/systemd/user/comfyui.service.d/`、`~/.cache/dk-*`
