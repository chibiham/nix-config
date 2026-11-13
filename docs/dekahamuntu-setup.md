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

### 2-4. ComfyUI（GPU 0）

> docs/ubuntu-server.md の「ComfyUI」の章に従って `scripts/install-comfyui-ubuntu.sh` を流して（apt と linger に sudo が要るので、その部分は私が流すコマンドを出して）。dekahamuntu.env の `COMFY_CUDA_DEVICES=0` で GPU 0 だけを使う。終わったら `scripts/configure-tailscale-serve-ubuntu.sh` で tailnet に公開して（`TAILSCALE_SERVE`）。モデルは自動で取らない。どのモデルを置くかは docs/ai-server-placement.md の案を私と決めてから。

`~/ai`（private repo）は `gh repo clone chibiham/chibiham-ai ~/ai -- -b develop`（https。`gh auth login` 済みであること）。

2026-11-12 の実績（chibihamuntu からの引っ越し。手順の全体は subako 側の手順書にある）:

1. `install-comfyui-ubuntu.sh` の中身を、chibihamuntu と同じ版に揃えて手で流した: ComfyUI の commit（`e3bee7ff`）を checkout、`uv venv --python 3.12`（mise の 3.12.16 が選ばれた）、chibihamuntu の venv の `uv pip freeze` を cu130 の index で入れた（torch 2.13.0+cu130）。apt（`build-essential`・`python3.12-dev`・`ffmpeg`・`git-lfs`）と linger は本人が sudo で流した
2. カスタムノード: cnr と git のものは chibihamuntu の `~/ComfyUI/custom_nodes` から rsync で写した（`~/ai/comfyui/custom-nodes.snapshot.json` と `cm-cli restore-snapshot` でも作れる）。自作の 5 つ（`chibiham-*`）と `user/default/{workflows,comfy.settings.json}` は `~/ai/comfyui/` への symlink（`~/ai` の README の手順）
3. モデル（`~/ComfyUI/models`、約 427GB）は chibihamuntu から rsync で写し、`~/ai/scripts/models check --hash` で確かめた
4. art-studio: `~/ai/scripts/install-art-studio`（unit 本体）と `scripts/configure-art-studio-ubuntu.sh`（このホストの drop-in。`ART_STUDIO_COMFYUI_URL`・`ART_STUDIO_CUDA_DEVICES`）。モザイクの `.venv` は `~/ai/apps/art-studio` の README の手順。作品と DB は chibihamuntu から写した
5. Tailscale Serve は本人が sudo で `443 → 8188`、`4520 → 4520` を設定した（いまは `configure-tailscale-serve-ubuntu.sh` で同じ形になる）

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

### 2-6. 学習・Applio（必要になったら）

> 学習を dekahamuntu でもするなら、`scripts/install-diffusion-pipe-ubuntu.sh` を流して（GPU 0）。`~/ai/scripts/lora-train` の `Conflicts=` は chibihamuntu の 1 枚を前提に comfyui・qwen38・applio を止めるので、dekahamuntu で使う前に ~/ai 側の変更が要るかを確かめて私に聞いて。

### 2-7. 見張り（subako）

subako の `subako.config.json` の `machines` に dekahamuntu を足すと、GPU の温度（`alerts.gpuTempC`）・CPU 電力が見える。nvidia-smi の行ごとに読むので 2 枚とも見張られる。CPU 電力は `/sys/class/powercap/intel-rapl:0` を読む（AMD でも同じ名前で出る見込み）。subako 側の作業なので、subako のエージェントに頼む。

### 2-8. ケースファンを GPU の温度で回す

本人が順に流す（sudo が要る）。中身と手順は下の「[ケースファン](#ケースファンgpu-の温度で回す)」。

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
| GPU の温度が読めないとき | `nvidia-smi` の失敗・1.2 秒で返らない（TERM を無視しても 0.3 秒後に KILL。fan2go の cmd センサーの時間切れ 2 秒より手前で終える）・枚数が `NVIDIA_EXPECTED_GPUS`（2）でない・数でない値のとき、100℃ を出す。曲線は 83℃ で 100% なので全開になる |
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
#    （env の CASE_FAN_HWMON を使う。既定の nct6799 と --probe の name が違えば、先に env を直す）
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

実機を読むだけで洗い出した（値・鍵の中身は書かない。あるかと場所だけ）。「再現」は、入れ直したときに同じ状態を作るもの。

### スクリプト・Nix で再現するもの

| 項目 | 実機の状態 | 再現するもの |
|---|---|---|
| OS・ユーザー | Ubuntu 24.04.5、ホスト名 `dekahamuntu`、ユーザー `chibiham`（`sudo`・`power` グループ） | インストーラ（第1段の 1.）。`hosts/ubuntu/dekahamuntu.env` の `UBUNTU_USER`、`power` は RAPL のスクリプト |
| apt の基礎 | `ca-certificates`・`curl`・`git`・`openssh-server`・`sqlite3`・`xz-utils` | `bootstrap-ubuntu.sh` |
| sshd | `ssh` が有効。設定はインストーラの `sshd_config.d/50-cloud-init.conf` のまま | インストーラと `bootstrap-ubuntu.sh` |
| Nix・Home Manager | `chibiham@dekahamuntu`（`~/.ssh/config`、`~/.secrets/env.tpl`、`ai-mode`、nix-gc.timer など） | `bootstrap-ubuntu.sh`（`home-manager switch`）。実機の世代は 2026-11-11 のもの（この枝の後の commit はまだ switch していない） |
| mise | Node.js 24、Python 3.12 | `bootstrap-ubuntu.sh` |
| シークレット | `~/.secrets/.env`（Service Account のトークン）、`~/.secrets/.env.secrets`（`update-secrets` の出力） | `bootstrap-ubuntu.sh`（トークンは本人が貼る） |
| Tailscale | `tailscale`（apt）、名前 `dekahamuntu`、operator は未設定 | `install-tailscale-ubuntu.sh`（いまの版は `--operator=$USER` も設定する） |
| Tailscale Serve | `https://dekahamuntu.<tailnet>.ts.net` → 8188、`:4520` → 4520。`:8443` → 8080（Qwen）は本人が sudo で流した（2026-11-14。tailnet から答えが返るのを確かめた）。3 つとも tailnet only | `configure-tailscale-serve-ubuntu.sh`（`TAILSCALE_SERVE=443=8188 4520=4520 8443=8080`）。443・4520 はまねのコマンドで流し、いまの `tailscale serve status` と同じになることを確かめた（8443 を足す前） |
| HWE カーネル | `linux-generic-hwe-24.04`、7.0.0-43 | インストーラで HWE を選ぶ。`install-hwe-kernel-ubuntu.sh` でも入る |
| NVIDIA ドライバ | `nvidia-driver-595-open`、`linux-modules-nvidia-595-open-generic-hwe-24.04`、595.99.02 | `install-nvidia-driver-ubuntu.sh`（`ubuntu-drivers install`）。`pciutils`・`ubuntu-drivers-common` もここ |
| RAPL | `power` グループ、`/etc/udev/rules.d/99-rapl-power.rules` | `install-rapl-power-access-ubuntu.sh`（`configure-ubuntu-hardware.sh` から） |
| ComfyUI の apt | `build-essential`・`python3.12-dev`・`ffmpeg`・`git-lfs` | `install-comfyui-ubuntu.sh` |
| linger | `Linger=yes` | `install-comfyui-ubuntu.sh`（`loginctl enable-linger`） |
| comfyui.service | GPU 0（`CUDA_DEVICE_ORDER=PCI_BUS_ID`・`CUDA_VISIBLE_DEVICES=0`）、`CC=/usr/bin/cc`、`--fast` なし。enabled | `install-comfyui-ubuntu.sh`（`COMFY_CUDA_DEVICES=0`、`COMFY_EXTRA_ARGS` は空）。まねのコマンドで流し、実機の unit と同じになることを確かめた |
| art-studio.service | unit 本体（PORT=4520、`ART_STUDIO_INBOX`、mise の node 24）。enabled | `~/ai/scripts/install-art-studio`。まねのコマンドで流し、実機の unit と同じになることを確かめた |
| art-studio の drop-in | `art-studio.service.d/dekahamuntu.conf`（`COMFYUI_URL=http://127.0.0.1:8188`、GPU 0） | `configure-art-studio-ubuntu.sh`（`ART_STUDIO_COMFYUI_URL`・`ART_STUDIO_CUDA_DEVICES`）。実機と同じ中身になることを確かめた |
| Qwen の unit（2026-11-13 に入れた） | `qwen38.service`（GPU 1、Router、ポート 8080。enabled、`WantedBy=default.target`）、`qwen38-dual.service`（GPU 0,1、`--split-mode layer --tensor-split 39,10`、`Conflicts=qwen38.service comfyui.service`。enable しない） | `install-qwen38-ubuntu.sh`（`LLM_CUDA_DEVICES`・`LLM_DUAL_*`・`QWEN_WANTED_BY`） |
| Qwen のプリセット（2026-11-13 に入れた） | `~/.config/llama.cpp/qwen38-models.ini`（n-cpu-moe 45 / 42）、`qwen38-dual-models.ini`（33 / 31）、`qwen38-flash-chat-template.jinja` | `install-qwen38-ubuntu.sh`（`QWEN_*_N_CPU_MOE`） |
| Qwen のモデル（2026-11-13 に取った） | `~/models/qwen3.8-flash-next`（UD-Q3_K_XL・Uncensored 版 i1-IQ3_M と各 mmproj）。27B はない | `install-qwen38-ubuntu.sh`（`QWEN_INSTALL_27B=0`） |
| ケースファン（2026-11-13 に入れた） | fan2go 0.15.0（`fan2go.service`、active (running)）、`/etc/fan2go/fan2go.yaml`・`case-fan-restore.conf`、`/etc/modules-load.d/case-fan-control.conf`（`nct6775`）。チャネル 1・3・4・6 | `install-case-fan-control-ubuntu.sh`（`CASE_FAN_*`） |

### `~/ai`（chibiham-ai）の手順で再現するもの

| 項目 | 実機の状態 | 再現するもの |
|---|---|---|
| `~/ai` | `gh repo clone` の https の clone（develop）。`lora/` の `lora.json`・`art-studio.json` は chibihamuntu から写した（学習のデータ本体は無い） | `gh repo clone chibiham/chibiham-ai ~/ai -- -b develop`。LoRA の配布の仕組みは chibiham-ai の issue の候補 |
| ComfyUI の本体とカスタムノード | `e3bee7ff`。カスタムノードは chibihamuntu から写したもの、`chibiham-*` は `~/ai/comfyui/custom_nodes` への symlink | `~/ai` の README（`custom-nodes.snapshot.json` と `cm-cli restore-snapshot`、symlink） |
| ComfyUI の venv | mise の Python 3.12.16、torch 2.13.0+cu130。パッケージは chibihamuntu の freeze と同じ版 | `install-comfyui-ubuntu.sh` は最新の torch を入れる（版は揃わない）。揃えるなら chibihamuntu の `uv pip freeze` を使う |
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
- 作業の残り（消してよい）: `~/.local/share/art-studio/studio.db.test-20261112`、`~/.local/share/art-studio-test-20261112/`、`~/ai.rsync-20261112/`、`~/ComfyUI/output/dekahamuntu-test/`、`~/.triton/cache.nixgcc-*`、空の `~/.config/systemd/user/comfyui.service.d/`、`~/.cache/dk-*`
