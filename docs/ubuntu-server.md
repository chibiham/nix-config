# Ubuntu Serverセットアップ

ComfyUI専用機では、CLI環境をNix/Home Manager、OSサービスをapt/systemdで管理する。
NVIDIAドライバ、CUDA、ComfyUIはGPU装着後に追加する。

## ホスト

| ホスト | 構成 | Home Manager | スクリプトの設定 |
|---|---|---|---|
| chibihamuntu | Intel Core i7-13700KF / RTX 3090 24GB ×1 / DDR4 64GB | `$USER@ubuntu-server` | `hosts/ubuntu/chibihamuntu.env` |
| dekahamuntu | AMD Ryzen 7 9700X / RTX 5060 Ti 16GB ×2 / DDR5 64GB | `$USER@dekahamuntu` | `hosts/ubuntu/dekahamuntu.env` |

部品・仕様の正は [machines.md](machines.md)。この表は要約。

`scripts/*-ubuntu.sh` はホスト名（`hostname -s`）から `hosts/ubuntu/<ホスト名>.env` を読み、GPUの割り当て・ドライバの条件・LEDの対象などを決める（変数は `hosts/ubuntu/README.md`、決定は [ADR 0002](adr/0002-ubuntu機ごとの設定.md)）。
ファイルのないホストでは chibihamuntu と同じ既定で動く。ただし `bootstrap-ubuntu.sh` はファイルがないと止まる。
以下の手順は chibihamuntu を例に書いている。dekahamuntu は最初から [dekahamuntu-setup.md](dekahamuntu-setup.md) に従う（第1段・第2段の順と、Blackwell・AMD・2枚のGPUの違い）。

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

その後、Ubuntu用bootstrapを実行する。Home Managerの対象（`$USER@ubuntu-server` など）とVaultはホストの設定から決まる。

```bash
~/.config/nix-config/scripts/bootstrap-ubuntu.sh
~/.config/nix-config/scripts/install-tailscale-ubuntu.sh
```

## シークレット（1Password）

Mac用の`MyMachine` Vaultは使わず、このマシン専用の`chibihamuntu` Vaultを参照する。
1Passwordで`chibihamuntu` Vaultだけを読めるService Accountを作り、そのトークンを
`bootstrap-ubuntu.sh`の入力に渡す（`~/.secrets/.env`に保存され、`update-secrets`まで実行される）。

参照するアイテムは`home/linux.nix`の`env.tpl`で管理する。追加する手順は次のとおり:

1. `chibihamuntu` Vaultにアイテムを作る（例: `CIVITAI_TOKEN`、credentialフィールド）
2. `home/linux.nix`の`env.tpl`に`op://chibihamuntu/<アイテム>/credential`を追記してswitchする
3. `update-secrets`を実行する（`op inject`は参照先が1つでも欠けると全体が失敗するため、先にアイテムを作っておく）

既存環境でトークンだけ設定する場合:

```bash
echo 'export OP_SERVICE_ACCOUNT_TOKEN="ops_..."' >> ~/.secrets/.env && chmod 600 ~/.secrets/.env
update-secrets
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

## HWEカーネル・GPU LED・RAPL

HWEカーネルの追加、GPU LEDの起動時消灯、RAPL（CPU消費電力）の読み取り権限（ホストの設定が `CASE_FAN_CONTROL=1` ならケースファンの制御も）をまとめて反映する:

```bash
~/.config/nix-config/scripts/configure-ubuntu-hardware.sh
```

sudo認証が必要。スクリプトは再実行可能で、OSの再起動やNVIDIAドライバの再ロードは行わない。
LEDはその場で消灯し、カーネルの切り替えは次回の手動再起動時になる。
カーネル・OSサービスはこのリポジトリのスクリプトからapt/systemdで管理し、
`home-manager switch`のactivationには含めない。

### カーネル更新の前に

カーネルが上がっても、同じ版の `linux-modules-nvidia-<世代>-open` が入らないと、再起動後にGPUが見えなくなる
（2026-10-23のchibihamuntu。メタパッケージ `linux-modules-nvidia-595-open-generic-hwe-24.04` が古い版のまま止まっていた）。
`apt full-upgrade` の前と、再起動の前に確かめる。読むだけで、何も変えない:

```bash
sudo apt-get update
~/.config/nix-config/scripts/check-nvidia-kernel-modules-ubuntu.sh
```

導入済みの各カーネル、メタパッケージ（`linux-image-generic-hwe-24.04` と `linux-modules-nvidia-<世代>-generic-hwe-24.04` の版）、
`full-upgrade` で入る予定のカーネルについて、同じ版のNVIDIAモジュールがあるかを出す。✗ があれば非0で終わる。
そのときは、モジュールが届くまで更新・再起動を待つか、足りないモジュールを入れる
（`sudo apt-get install linux-modules-nvidia-<世代>-<カーネル>`）。稼働中より古いカーネルに欠けているものは ⚠ で知らせるだけ（GRUBで選ばない限り起動しない）。
unattended-upgradesがカーネルを入れることもあるので、再起動の前には毎回流す。

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

対象はホストの設定の `GPU_LED_MATCH`（OpenRGBの一覧の行に当てる正規表現）と `GPU_LED_COUNT`（台数）で、
インストーラが `/etc/default/gpu-led-off` に書く（ないときはGigabyte RTX 3090 1台）。
同じ名前のカードが複数あるときは、一覧の番号で全部を一度に消す。`GPU_LED_OFF=0` のホストでは
`configure-ubuntu-hardware.sh` が消灯を入れない（dekahamuntuはカードがPalitと分かった（2026-11-13）。OpenRGBで消せるかを確かめるまで0）。

root所有のsystem serviceとして動くため、SSHログインやユーザー領域の実行ファイルに依存しない。
I2Cデバイスを全ユーザーへ開放する設定も不要。OpenRGBの設定は`/var/lib/gpu-led-off`に分離する。
電源投入直後からサービス実行までの間は、GPU本体の既定の点灯状態になる場合がある。

### RAPL（CPU消費電力）の読み取り

```bash
~/.config/nix-config/scripts/install-rapl-power-access-ubuntu.sh
# 確認（新しいSSHログインで）
ls -l /sys/class/powercap/intel-rapl:0/energy_uj   # -r--r----- root power
cat /sys/class/powercap/intel-rapl:0/energy_uj
```

`energy_uj`（積算エネルギー、µJ）はカーネル既定でroot専用
（CVE-2020-8694の電力サイドチャネル対策）。全ユーザーには開放せず、
systemグループ`power`を作って実行ユーザー（sudo元、または引数のユーザー）だけを加える。

`udev/99-rapl-power.rules`を`/etc/udev/rules.d/`へ置き、powercapデバイスの追加時に
`energy_uj`を`root:power 0440`にする。sysfsの権限は起動ごとに戻るのでudevで毎回設定し、
インストール時は`udevadm trigger --action=add`で既存デバイスにも即座に反映する。
グループ所属は新しいログインから有効（SSHは毎回新しいログインなのでMacからはすぐ読める）。

AMD（Zen）でも `intel_rapl_msr` が同じ `intel-rapl:0` に積算エネルギーを出す（Zen 5はカーネル6.12以降。HWEなら入っている）。
ゾーンが1つもないCPU・カーネルでは、スクリプトは何も変えずに警告だけ出して終わる。読めないホストはホストの設定で `CPU_POWER_READ=0` にする。

### ケースファン（GPU の温度で回す）

**本人が実機に入れた（2026-11-15 19:09 JST = 10:09 UTC。チャネル 5、GPU の曲線は dekahamuntu と同じ値）。そのあと本人が GPU の曲線を前へ寄せ、ラジエーターのファン（pwm2）も操ると決め、22:59 JST（13:59 UTC）に入れ直した（写し `~/nix-config-issue6`、commit b15ddf3 と同じ中身から）。2026-11-16 に本人の決めで 19:09 JST の形に戻した（env。下の「戻した（2026-11-16）」）。** env の上では、fan2go が操るのは pwm5（ケースファン）だけで、GPU の曲線は dekahamuntu と同じ値、pwm2（ラジエーターのファン）は BIOS の制御。実機に入れ直すのは本人（入れ直すまでは、実機は前へ寄せた曲線とラジエーターの組のまま）。前へ寄せた曲線とラジエーターの組の値と結果は、試した記録として下の表・「ラジエーターのファン（pwm2）も操る」・「入れ直しの結果」に残す。

ケースファンを GPU の温度に合わせて回す（issue 6）。仕組み（fan2go、ケースファン = max(GPU の曲線, CPU の曲線)、GPU の温度が読めないときは全開側に倒す、止めたとき・落ちたときは BIOS の制御へ戻す、初回の解析）は dekahamuntu と同じスクリプトで、説明は [dekahamuntu-setup.md の「ケースファン（GPU の温度で回す）」](dekahamuntu-setup.md#ケースファンgpu-の温度で回す)。ここには chibihamuntu に固有のことだけを書く。値は `hosts/ubuntu/chibihamuntu.env` の `CASE_FAN_*`（意味は `hosts/ubuntu/README.md`）。

`configure-ubuntu-hardware.sh` は、env が `CASE_FAN_CONTROL=1` のときだけ `install-case-fan-control-ubuntu.sh` を流す。chibihamuntu の env は 1 なので、`configure-ubuntu-hardware.sh` を流すと入れるスクリプトも流れる（入れたあとは、流すたびに fan2go を止めて入れ直す。下の「入れ直しでスクリプトがすること」）。

| 項目 | chibihamuntu |
|---|---|
| ボード・チップ | ASUS TUF GAMING B760M-PLUS D4（BIOS 1220）、Nuvoton NCT6798D。ドライバは `nct6775`、hwmon の name は `nct6798`（2026-11-15 に実機で確かめた）。ASUS WMI のボード一覧にあり、`acpi_enforce_resources=lax` は要らなかった（`CASE_FAN_ACPI_LAX=0`） |
| 操るチャネル | 5（env。2026-11-16 に戻した形）。2026-11-15 22:59 JST から一晩は 5 と 2（どちらも enable=1）。<br>5 = ケースファンの組（`CASE_FAN_CHANNELS=5`。回転数も fan5）。ケースの付属ファン 120mm ×6 が付属のハブ 1 つで 5 にまとまっている、という見立て（本人・執事）。6 つ全部が 5 につながっているかは未確認。操れる幅は約 475〜1,070 RPM（pwm=0 で約 475、全開で最大 1,071。2026-11-15 の `--identify`）。<br>2 = ラジエーターの組（試したが戻した。2026-11-15 22:59 JST 〜 2026-11-16。そのときは `CASE_FAN_RAD_CHANNELS=2`。いまの env は空。回転数も fan2）。簡易水冷（Cooler Master MasterLiquid 360L Core）のラジエーター（天面）のファン 120mm ×3（本人が確かめた）。仕様は 650〜1,750 RPM。pwm=0 でも約 680 RPM で回り続ける（初回の解析で、pwm 0〜64 のあいだ 681〜773 RPM。全開で 1,541〜1,711 RPM）。前に書いた「pwm=0 で止まる」（本人が `--identify 2 --stop` で「止まってるみたい」と見た）は、回転数の上では当たらなかった |
| 操らないチャネル | pwm2（ラジエーターのファン）は、2026-11-16 から操らない（BIOS の制御。SmartFan IV、`pwm2_enable=5`。下の「戻した（2026-11-16）」）。<br>pwm6（ポンプと見られる。BIOS の曲線が全点 255、約 2,600 RPM。未確認）は操らない（BIOS の制御のまま全開。入れ直しのあとも 255・約 2,580〜2,610 RPM で変わらず）。pwm1・pwm4（何もつながっていない見込み。enable=5）、pwm7（確かめていない。enable=0）も入れない。<br>はじめは CPU のクーラーのチャネル（pwm2・pwm6）を両方とも入れないことにしていた（issue 6 の「CPU_OPT は入れない」を執事が「CPU のクーラーを操らない」と読み替えた。本人・執事）。issue の本文の「CPU のクーラーは操らない」「操るのはケースファンのチャネルだけ」は、本人の決め（2026-11-15 19:25 JST ごろ）で上書きした: ラジエーターのファン（pwm2）は操る。ポンプ（pwm6）は操らない。2026-11-16 に、本人の決めで pwm2 も操らない形へ戻した。<br>pwm5 は BIOS の曲線が pwm2 と同じなので、ボードの上では CPU_OPT のヘッダーかもしれない（pwm5 がボードのどのヘッダーかは未確認）が、つながっているのはケースファンなので操る |
| 最低のデューティ | ケースファン 30%（`CASE_FAN_MIN_DUTY`）、ラジエーターのファン 20%（`CASE_FAN_RAD_MIN_DUTY`。BIOS の最低 51 と同じ。組を使っていたときの値。env に残してある）。どの pwm も mode=1（PWM、4pin の制御）。fan5 は pwm=0 でも約 475 RPM で回り続けるので、30% は「止めない」ための下限というより曲線の下の値。30%（pwm5 77）のときは fan5 約 520〜531 RPM（学習の合間、2026-11-15 23:20 JST ごろ） |
| GPU の温度 | RTX 3090 1 枚。`NVIDIA_EXPECTED_GPUS=0` なので枚数は確かめない |
| CPU の温度 | ケースファン: coretemp の temp1（Package id 0。`CASE_FAN_CPU_HWMON=coretemp`、`CASE_FAN_CPU_TEMP_CHANNEL=1`）。ラジエーターのファン（組を使っていたとき）: 主は nct6798 の temp9（BIOS と同じ源）、保険は coretemp の temp1 |
| ケースファンの曲線 | GPU `45:30 60:45 70:65 78:85 83:100`、CPU `60:30 75:45 85:65 95:100`（℃:デューティ%）。どちらも dekahamuntu と同じ値（2026-11-16 に戻した）。<br>試したが戻した: 最初にこの値で入れ（2026-11-15 19:09 JST）、同じ日の 19:20 JST ごろに本人が GPU の曲線を前へ寄せると決め、`45:30 55:50 65:75 72:90 78:100`（PWM は 45℃ 77・55℃ 128・65℃ 191・72℃ 230・78℃ 255）で 22:59 JST に入れ直した。本人の言葉は「もう少し曲線を前にしよう。GPUは冷やしたいし、上部はCPUのラジエーターのファンにしているから排気が弱いとおもうんだよね」。ファンは上がったが学習中の GPU の温度はほとんど変わらず（下の「入れ直しの結果」）、2026-11-16 に戻した。fan5 は全開で約 1,070 RPM |
| ラジエーターの組の曲線（試したが戻した。値は env に残してある） | GPU `45:30 55:50 65:75 72:90 78:100`（ケースファンの前へ寄せた曲線と同じ）、CPU（主）`17:20 42:40 62:70 67:100`（nct6798 の temp9）、CPU（保険）`40:35 60:50 75:65 85:85 92:100`（coretemp の temp1 = Package）。ファン = max(この 3 本)。理由は下の「ラジエーターのファン（pwm2）も操る」 |
| 最初の曲線のとき（実機） | 学習中（GPU 100%・約 335〜340W。2026-11-15 19:13〜19:15 JST、20 秒ごと 6 回）に GPU 66〜67℃、CPU Package 70〜76℃、pwm5 149〜150（enable=1）、fan5 767〜776 RPM。曲線の計算（67℃ → 約 59% = 150）と合う。BIOS のままのほかのチャネルは pwm2 151〜158・fan2 1,248〜1,291 RPM、fan6 約 2,570 RPM。`case-fan-gpu-temp.status` は「<時刻> ok 67 gpus=1」 |
| BIOS の制御のとき | 学習中（GPU 100%・約 340W、GPU 65〜66℃）に pwm5 が 124〜143、fan5 が 650〜750 RPM（本人、2026-11-15）。ラジエーターのファンは、学習中（Package 70〜76℃）に pwm2 151〜158（fan2 1,246〜1,291 RPM）、合間（Package 39〜58℃。1 秒単位で上下する）に temp9 38〜45℃、pwm2 87〜109、fan2 927〜1,032 RPM（2026-11-15、読むだけ） |

チャネルごとの回転数・pwm・BIOS の曲線と、どれが何かの見立て（未確認）は [machines.md の「ファン（2026-11-15）」](machines.md#ファン2026-11-15)。

#### ラジエーターのファン（pwm2）も操る

**2026-11-16 に戻した（下の「戻した（2026-11-16）」）。この節は、試したときの決め・仕組み・守り方の記録。** スクリプトの組の機能（`CASE_FAN_RAD_*`）と、その守り・試験は残してある。

経緯（2026-11-15 19:25 JST ごろ）: 本人の言葉は「GPUは冷やしたいし、上部はCPUのラジエーターのファンにしているから排気が弱いとおもうんだよね」。執事が「天面のラジエーターのファン（pwm2）は CPU の温度だけで回っていて、学習中は GPU が熱くても天面の排気が上がらない。ここも GPU と CPU の高いほうで回すようにすれば排気が増える。高いほうに合わせる形なら CPU の冷却は弱くならない。やる?」と聞き、本人が「やっとこう」と答えた。ポンプ（pwm6）は操らない。22:59 JST に入れた。

仕組み: ケースファンの組とは別の「ラジエーターの組」（`CASE_FAN_RAD_*`。意味は `hosts/ubuntu/README.md`）。fan2go の設定には、ファン `rad_pwm2`（曲線 `rad_fans` = maximum(`rad_gpu_curve`, `rad_cpu_curve`, `rad_cpu_backup_curve`)）と、センサー `rad_cpu`（nct6798 の temp9）・`rad_cpu_backup`（coretemp の temp1）が足される。ケースファンの `case_pwm5`・`gpu_max`・`cpu`・`gpu_curve`・`cpu_curve`・`case_fans` は、id も中身も変えない。組がないホスト（dekahamuntu）では、出力は 1 バイトも変わらない。

決まり: **CPU の冷却を BIOS より弱くしない。** 守り方:

- **同じ温度の源**: BIOS の pwm2 の入力は nct6798 の **temp9（ラベル「PECI Agent 0 Calibration」）**。`pwm2_temp_sel=9` で、nct6775 のドライバとドキュメントでは temp_sel の値は sysfs の tempN の N（「Value is temperature sensor index. For example, select '1' for temp1_input」）。実測でも合う（読むだけ。2026-11-15）: temp9 40.5℃ → BIOS の曲線の計算 92.8・実測 pwm2 93、38.0℃ → 87.7・87、36.0℃ → 83.6・83、50.5℃ → 122.9・120。coretemp の Package（= nct6798 の temp8「PECI Agent 0」）そのものではない。主の CPU の曲線は temp9 で引く
- **BIOS の曲線を 3℃ 前へ寄せた**: BIOS の曲線は 20℃:51、45℃:102、65℃:178、70℃:255（5 点目 125℃:255）。点の間は直線で、`pwm2_step_up_time=0`・`pwm2_step_down_time=0`・`pwm2_temp_tolerance=0`。主の CPU の曲線 `17:20 42:40 62:70 67:100` は、PWM で 17℃ 51、42℃ 102、62℃ 179、67℃ 255
- **機械の確かめ**: 入れるスクリプト（と `--print-config`）は、温度の源が BIOS と同じ（`CASE_FAN_RAD_CPU_HWMON` が `CASE_FAN_HWMON` と同じで、`pwm2_temp_sel` が `CASE_FAN_RAD_CPU_TEMP_CHANNEL` と同じ）なら、sysfs の BIOS の曲線（`pwm2_auto_point*`。fan2go が動いていても読める。今の enable には依らない）と主の CPU の曲線を、両方の点の温度の全部で比べる（2 本の折れ線の差は、どちらかの点の温度で最小になる）。1 か所でも BIOS より小さければ、どの温度で BIOS がいくつ・こちらがいくつかを出して止まる。源が違う・BIOS の曲線のファイルがないときは、比べられないと注意を出して進める（標準エラー）。`--probe` の見立てにも比べの結果が出る
- **BIOS のモード**: 曲線を比べる前に、fan2go が止まったときに戻る `pwm2_enable`（BIOS のモード）を見る。いまの値が 1 以外ならその値、1（fan2go が操っている）なら `/etc/fan2go/case-fan-restore.conf` の記録の値。5（SmartFan IV）のときだけ曲線を比べる。0（全開）は、どの温度でも 255 なので fan2go で操れば必ず弱くなる。温度の源が違っても止まる。2〜4（Thermal Cruise・Fan Speed Cruise・SmartFan III）やほかの値は `auto_point` の曲線を使わず、比べるものがないので止まる。いま 1 で記録がない（分からない）ときも止まる。通ったときの文に、モードとその出所（いまの値か、記録か）が出る（例「BIOS のモード: SmartFan IV（pwm2_enable=5。いまは pwm2_enable=1 なので、/etc/fan2go/case-fan-restore.conf の記録）」）
- **BIOS の曲線の段差**: BIOS の曲線は、同じ温度に点が 2 つ以上あってよい（段差。例 `62:178 62:255`）。その温度ちょうどでは、その温度の点の PWM の最大と比べる（最初の点より下・最後の点より上も、端の温度の最大）。点の間は、すぐ左の点（同じ温度が複数あれば最後）とすぐ右の点（同じ温度が複数あれば最初）を結ぶ直線。こちらの曲線は連続なので、段差の温度で高いほうと比べれば、段差のすぐ右も覆える
- **既知の限界**: 戻し先の記録は、入れたときの BIOS のモード。fan2go が動いたまま BIOS の設定を変えた（たとえば全開にした）場合は気づけない。fan2go が止まるたびに unit の `ExecStopPost` が記録の値を書き戻すので、入れ直しでも記録は前のまま。`--uninstall` も記録の値へ戻してから記録を消すので、そのあとすぐ入れ直しても前のモードを読む。BIOS の設定を変えるときは、先に `--uninstall` し、BIOS の設定を変えて起動し直して（BIOS が起動のときに自分のモードを入れる見込み）から入れ直す
- **Package に BIOS の数字をそのまま当てない理由**: Package は temp9 より高く出る（Package 40℃ のとき temp9 36.0、64℃ のとき 50.5）。学習中は Package 70〜76℃ なので、BIOS の数字を当てると、ラジエーターのファンが学習中ずっと全開になる
- **平均の遅れの判断**: fan2go は温度を約 10 秒の指数移動平均でならす（下の「fan2go の動き」）。窓はセンサーごとには変えられず、全体の窓を短くすると dekahamuntu の設定も変わるので変えない。BIOS は遅れなし。3℃ の寄せは、毎秒 0.3℃ までの上がり方なら、ならした温度の遅れ（速さ × 約 10 秒）を埋める。それより速い上がり（CPU の負荷の急な立ち上がり）では、全開に届くのが BIOS より約 10 秒遅れうる。簡易水冷は冷却水とラジエーターの熱容量があり、ファンの 10 秒ほどの遅れで冷却水の温度はほとんど変わらない（250W で 10 秒 = 2.5kJ。冷却水とラジエーターの熱容量を約 1〜1.5kJ/K と見て、放熱がまったくなくても 2℃ ほど。見積もり）。ポンプは BIOS のまま全開。入れたあとの記録で、この遅れのぶん BIOS をわずかに下回った所が 3 回あった（下の「入れ直しの結果」）
- **保険の曲線（Package）**: 主の源（temp9。ラベルに undocumented とある源）が固まる・0 を返すようになっても、Package の温度でファンが上がる。値 `40:35 60:50 75:65 85:85 92:100` は、観測した BIOS の動き（Package 40℃ → pwm2 83、64℃ → 120、70〜76℃ → 151〜158）以上になるようにした: PWM は 40℃ 89、60℃ 128、75℃ 166、85℃ 217、92℃ 255（64℃ → 138、70℃ → 153、76℃ → 171）。入れる前は「合間のファンは BIOS より少し（PWM で 10〜20）高く回る」と見込んでいたが、入れたあとの合間の pwm2 は平均 98 で、BIOS のときの合間（平均 94）とほぼ同じだった
- GPU の曲線は、まずケースファンと同じ（本人・執事）。ラジエーターのファンはケースファンよりうるさくなりうるので、音と効き目を見て、曲線を戻す・変えるのは本人が決める

fan2go の動き（fan2go 0.15.0 のソースを別の作業者が読んだもの。実機で確かめた所はそう書く。ほかは見込み）:

- `function: maximum` に 3 本以上の曲線を渡せる。同じセンサー（`gpu_max`）を複数の曲線が使ってよい。同じ platform（nct6798）をファンとセンサーの両方に使ってよい。hwmon のセンサーの `channel: 9` は `temp9_input`。実機で確かめた: この形の設定（3 本の maximum、nct6798 の channel 9 のセンサー）が、入れるスクリプトの中の root での `fan2go config validate`（本物の 0.15.0）を通り、そのまま動いている
- 温度の平均は指数移動平均（1 秒ごとに `avg ← avg + (x − avg)/10`。時定数 約 9.5 秒）。50→80℃ のステップで平均が 70℃ に届くのは約 10.4 秒。PWM は 200ms に 3（毎秒 15）まで動く
- センサーが読めないとき（見込み。実機では確かめていない）: 動いている間の読みの失敗は、前の平均を保ったまま固まる（毎秒の警告だけ。制御は続く）。0 や負の値はそのまま平均に入り、その曲線は最初の点の値まで下がる（そのときは保険の曲線と GPU の曲線が支える）。起動時にセンサーが見つからないと、それを使う曲線の評価がエラーになり、そのファンの controller が止まって BIOS へ戻る（ほかのファンは動き続ける）
- 止まる・落ちるとき: ファンごとに `onExit: restore` が元の mode（BIOS なら enable=5）を書き戻す。強制終了のときは、unit の `ExecStopPost`（`case-fan-restore-bios`）が `/etc/fan2go/case-fan-restore.conf` の行ごとに戻す。入れるスクリプトは pwm2 の行もそこに書く（実機の記録は 2 行。下の「入れ直しの結果」）

#### 入れ方（本人が実機で流した。sudo が要る）

済んだこと（2026-11-15 JST、本人）:

1. `scripts/install-case-fan-control-ubuntu.sh --probe --load-module`（17:00 JST ごろ。nct6775 を一時的に読み込んで調べた。再起動で消える）
2. `--identify 5`（18:25 ごろ。10 秒だけ全開）: fan5 だけが 685 → 最大 1,071 RPM に上がった。`--identify 5 --stop`（19:00 ごろ。10 秒だけ pwm=0）: fan5 が 676 → 475 RPM に下がったが止まらなかった。どちらも終わると元（enable=5 pwm=124）へ戻った。pwm2 はラジエーターのファン（音で確かめた。止めたら止まって見えたが、回転数の上では pwm=0 でも約 680 RPM で回る。上の表）。pwm1・pwm4 は止めても目に見えて止まったファンはなかった。値は [machines.md の「ファン（2026-11-15）」](machines.md#ファン2026-11-15)
3. `hosts/ubuntu/chibihamuntu.env` を `CASE_FAN_CHANNELS=5`・`CASE_FAN_CONTROL=1` にした
4. 入れた（19:09 JST = 10:09 UTC。実機の写し `~/nix-config-issue6`、commit 551a83a と同じ中身で `scripts/install-case-fan-control-ubuntu.sh`）。GPU の曲線は dekahamuntu と同じ `45:30 60:45 70:65 78:85 83:100`。読むだけで確かめたこと:
   - `fan2go.service` は 19:09:26 JST に起動。active・enabled、再起動 0 回、メモリ約 13MB（19:13:54 JST）
   - `/etc/fan2go/fan2go.yaml` の sha256 は `--print-config` の出力と同じ。`/etc/modules-load.d/case-fan-control.conf` に nct6775。`/etc/fan2go/case-fan-restore.conf` は「nct6798 5 5」（入れる前の BIOS の pwm5_enable は 5）
   - 操っているのは pwm5 だけ（enable=1）。pwm1・2・4・6 は enable=5（BIOS の自動）、pwm7 は enable=0 のまま
   - カーネルのログに NVIDIA の Xid はない（起動 16:37 JST から 19:13 JST まで）
   - 入れたあとの値は上の表の「最初の曲線のとき（実機）」
5. GPU の曲線を `45:30 55:50 65:75 72:90 78:100` にした（env。19:20 JST ごろ、本人が決めた）
6. ラジエーターのファン（pwm2）も操ることにした（env とスクリプト。19:25 JST ごろ、本人が決めた。上の「ラジエーターのファン（pwm2）も操る」）
7. 入れ直した（22:59 JST = 13:59 UTC。学習中。GPU 100%・約 338W・65℃。写し `~/nix-config-issue6`、commit b15ddf3 と同じ中身で `scripts/install-case-fan-control-ubuntu.sh`）。結果は下の「入れ直しの結果」
8. 19:09 JST の形に戻した（env。2026-11-16。下の「戻した（2026-11-16）」）。実機への入れ直しは本人

入れ方の手順（次に入れ直すとき。本人が流す。sudo）:

```bash
cd ~/.config/nix-config

# 1. 書く予定の fan2go.yaml を見る（sudo 不要。ファンは変えない）。いまの env では fans は case_pwm5 の 1 つ。
#    （ラジエーターの組を使う env なら、fans が case_pwm5 と rad_pwm2 の 2 つか、標準エラーに
#    「ラジエーターの pwm2: CASE_FAN_RAD_CPU_CURVE は、BIOS の曲線（temp9。5 点）より弱い所がない」が出るかを見る）
scripts/install-case-fan-control-ubuntu.sh --print-config

# 2. 入れ直す（sudo）
#    （configure-ubuntu-hardware.sh を流しても、env が 1 なのでこれが流れる）
scripts/install-case-fan-control-ubuntu.sh
```

入れ直しでスクリプトがすること（`do_install` を読んだ）: 設定を確かめる（BIOS の曲線との比べを含む。弱ければ何も変えずに止まる）→ ラジエーターの組があれば、初回の解析でファンが止まる時間がある旨の注意を出す（止めはしない）→ fan2go が動いていれば止める（落ちて起動し直しを待っている `activating` も止める。fan2go 自身の `onExit: restore` と unit の `ExecStopPost` が、**前の** `case-fan-restore.conf` の行ごとに BIOS の制御へ戻す）→ fan2go の実行ファイル（SHA256 が合えばそのまま）・センサーと戻しのスクリプトを置き直す → 前の記録にあって新しい設定にないチャネル（組から外したチャネル。2026-11-16 の戻しでは pwm2）がまだ手動（enable=1）なら、前の記録の値へ戻して読み戻す（戻せなければ記録を書き直さずに止まる）→ 新しい設定のチャネルの BIOS の `pwmN_enable` を `case-fan-restore.conf` に書き直す（止めたあとも enable=1 のままなら前の記録を使う）→ 設定を `fan2go config validate` で確かめてから置き換える → unit を置き直して起動し直す（`systemctl restart`）。止めてから起動するまでの短いあいだは BIOS の制御。

スクリプトが出す「初回の解析でラジエーターのファンが止まる時間がある」の注意は、pwm=0 で止まるファンのためのもの。chibihamuntu の fan2 は pwm=0 でも止まらなかった（下）。

解析の結果は `/var/lib/fan2go/fan2go.db` に残る（入れ直しでは消さない）。DB の鍵はファンの `id` だけなので、id を変えなければ入れ直しでは解析し直さない（22:59 の入れ直しで case_pwm5 について確かめた）。`--uninstall` は `/var/lib/fan2go` を消すので、外してから入れると解析はやり直しになる。

#### 初回の解析

見込みは別の作業者が fan2go 0.15.0 のソースを読んだもの。ログは `journalctl -u fan2go`、時刻は JST。

- 見込み: 失敗せずに通る。止まる点がなければ start の境界は PWM 0 になるが、使われるのは設定の `minPwm`・`startPwm`・`maxPwm`（設定に書いた値は解析の結果で上書きされない。`internal/fans/hwmon.go` の `SetStartPwm` など）。ログには「Analysis boundaries detected (before config overrides)」と出る
  - 実機で確かめた（case_pwm5、19:09 に入れたとき）: 見込みどおり。19:09:29「Fan 'case_pwm5' has not yet been analyzed, starting initialization sequence...」→ 19:10:06「start/min boundary detected at PWM 0」→ 19:10:39「max boundary confirmed at PWM 255 (threshold 1022.2 RPM)」→ 19:11:12「RPM curve analysis finished in 1m43.695s」「Analysis boundaries detected (before config overrides): Start 1, Max 255」「PWM settings of fan 'case_pwm5': Min 77, Start 77, Max 255」「Starting controller loop」
  - 実機で確かめた（rad_pwm2、22:59 に入れ直したとき）: 見込みどおり。22:59:55「Fan 'rad_pwm2' has not yet been analyzed, starting initialization sequence...」→ 23:00:32「start/min boundary detected at PWM 0」（36.835 秒）→ 23:01:05「max boundary confirmed at PWM 255 (threshold 1627.3 RPM)」（32.408 秒）→ 23:01:38「Interior coarse sampling captured 7 points」（33.643 秒）「RPM curve analysis finished in 1m42.887s」「Analysis boundaries detected (before config overrides): Start 1, Max 255」「PWM settings of fan 'rad_pwm2': Min 51, Start 51, Max 255」「Starting controller loop」
- 見込み: 入れ直しでは、id の変わらない case_pwm5 は解析し直さない
  - 実機で確かめた: 見込みどおり。22:59:55 に解析なしで「PWM settings of fan 'case_pwm5': Min 77, Start 77, Max 255」「Starting controller loop」
- 見込み: 解析のあいだ、pwm は曲線と関係なく動く: 127 → 63 → 31 → 15 → 7 → 3 → 1 → 0（止まる所の探索）、255〜191（最大の探索と確認）、32〜224（間の点）。1 点あたり約 5〜30 秒（`analysis.settleTimeout` の既定 30 秒）。合計はおそらく 1.5〜3 分、上限は約 11 分。GPU 自身のファンは別に動く
  - 実機で確かめた（case_pwm5）: 合計 1 分 43.7 秒（見込みの幅の中）。止まる所の探索は 37.582 秒、最大の探索は 33.046 秒（ログの値）
  - 実機で確かめた（rad_pwm2。5 秒ごとの記録）: 合計 1 分 42.9 秒。pwm2 は 63 → 15 → 7 → 3 → 1 → 0 と置かれ（約 25 秒、23:00:05〜23:00:32）、そのあと 223〜255、間の点 32・64・96・160・192・224
- 見込み（外れた）: fan2 は pwm=0 で止まるので、止まる所の探索のあいだ、ラジエーターのファンが止まる時間が合わせて 30 秒〜1 分、最悪 3 分前後ある
  - 実機で確かめた: **ラジエーターのファンは止まらなかった。** pwm2 が 63 → 0 と置かれた約 25 秒のあいだ、fan2 は 767 → 681〜684 RPM で回り続けた。最大の探索の 223〜255 では 1,541〜1,711 RPM、間の点は 32 で 767 RPM、64 で 773、96 で 978、160 で 1,146、192 で 1,424、224 で 1,577。fan2 は pwm=0 でも約 680 RPM（仕様の最低 650 RPM 付近）で回り続けるファンで、pwm 0〜64 では回転数がほぼ変わらない（681〜773 RPM）。解析のあいだの CPU Package は 65〜72℃、temp9 は 55〜57℃ で、直前（67〜70℃・55〜56℃）と変わらなかった
- 見込み（実機では確かめていない）: 解析の途中で fan2go を止めると、解析が終わるまで終わらず（systemd の既定の 90 秒で SIGKILL）、そのときは unit の `ExecStopPost`（case-fan-restore-bios）が BIOS の制御へ戻す。測った結果は最後にまとめて保存するので、途中で止めると次の起動で解析は最初からやり直し
- 見込み: 動いている間の RPM の検査（平均が 0 なら minPwm を上げる・全開でも 0 なら止まる）には、fan5（いつも約 475 RPM 以上）も fan2（いつも約 680 RPM 以上）も当たらない。入れ直しのあと 23:33 JST まで fan2go の再起動は 0 回

#### 入れ直しの結果（2026-11-15 22:59 JST。読むだけで確かめた）

- `fan2go.service` は 22:59:52 JST に起動し直した。active・enabled、再起動 0 回、メモリ約 14MB（23:33 JST）。入れ直しのとき、前の fan2go は SIGTERM で止まり、「case-fan-restore-bios: nct6798 pwm5 を pwm5_enable=5（BIOS の制御）へ戻しました」が出てから新しい設定で起動した
- `/etc/fan2go/fan2go.yaml` の sha256 は `--print-config`（b15ddf3）の出力と同じ。入れるスクリプトの中の root での `fan2go config validate` を通った
- `/etc/fan2go/case-fan-restore.conf` は「nct6798 5 5」「nct6798 2 5」の 2 行
- 操っているのは pwm5 と pwm2（enable=1）。pwm1・pwm4・pwm6 は enable=5（BIOS）、pwm7 は enable=0 のまま。pwm6（ポンプと見られる）は 255・約 2,580〜2,610 RPM で変わらず
- 入れ直しから 23:33 JST まで、fan2go のログに警告・エラーは 0 行。`case-fan-gpu-temp.status` は「ok 65 gpus=1」。カーネルのログに NVIDIA の Xid は 0 行（起動 16:37 JST から）

学習中（GPU 100%・約 339W）の前後:

| | 回数 | GPU | CPU Package | temp9 | pwm5 | fan5 | pwm2 | fan2 |
|---|---|---|---|---|---|---|---|---|
| 最初の曲線・前半（19:44〜21:39 JST、10 秒ごと） | 555 | 平均 66.3℃（最大 68） | 平均 71.1℃（最大 79） | 平均 58.9℃ | 平均 147 | 平均 763 RPM | 平均 153（BIOS） | 平均 1,271 RPM |
| 最初の曲線・入れ直しの直前（21:40〜22:59 JST、20 秒ごと） | 196 | 平均 64.4℃ | 平均 67.8℃ | 平均 55.5℃ | 平均 137 | 平均 726 RPM | 平均 140（BIOS） | 平均 1,209 RPM |
| 新しい設定（23:01〜23:32 JST、5〜8 秒ごと） | 235 | 平均 64.2℃（最大 65） | 平均 65.1℃（最大 71） | 平均 52.8℃ | 平均 185 | 平均 863 RPM | 平均 185 | 平均 1,423 RPM |

読み方:

- ファンは計算どおり上がった（65℃ で PWM 191。直前と比べて fan5 は約 +140 RPM、fan2 は約 +210 RPM）
- **GPU の温度は、直前と比べてほとんど変わっていない**（64.4℃ → 64.2℃。nvidia-smi の 1℃ 刻みの中）。夜になって、最初の曲線のままでも 66.3 → 64.4℃ に下がっていた（部屋の温度の変化と見られる。未確認）ので、前半の 66.3℃ と比べて「2℃ 下がった」とは言えない
- CPU は下がった（Package 67.8 → 65.1℃、temp9 55.5 → 52.8℃）
- GPU 自身のファンは、最初の曲線のとき（19:13 JST、GPU 67℃）77%、新しい設定（23:33 JST、GPU 65℃）73%（どちらも 1 回の読み）。GPU のファンが自分で温度を保つので、ケースの風が増えたぶんは GPU の温度でなく GPU のファンの回転に出る見込み（確かめるには GPU のファンの回転も記録する必要がある。していない）
- 音と効き目を見て、曲線を戻す・変えるのは本人が決める

学習の合間（新しい設定。23:19:54〜23:28 JST、GPU 0%）:

- GPU 53 → 39〜42℃。pwm5 163 → 77（約 50 秒で）・fan5 833 → 520〜531 RPM、pwm2 163 → 89〜103・fan2 1,366 → 904〜1,017 RPM。合間の平均は GPU 41.6℃、Package 40.4℃、temp9 38.0℃、pwm5 82、fan5 543 RPM、pwm2 98、fan2 973 RPM
- 学習に戻ると（23:28:14 JST〜）、pwm5・pwm2 は 91・108 → 122 → 約 4 分後に 191 へ上がり、fan5 878 RPM・fan2 1,459 RPM（23:32:34 JST）
- 最初の曲線での合間（20:43〜20:55 JST）は pwm5 平均 79・fan5 548 RPM、pwm2（BIOS）平均 94・fan2 967 RPM。新しい設定の合間の pwm2（平均 98）は、BIOS のとき（平均 94）とほぼ同じ
- 「GPU に負荷がかかるとケースファン（とラジエーターのファン）の pwm と回転数が上がり、負荷を止めると下がる」（issue 6 の完了条件）を、最初の曲線（19:19〜19:29 JST の合間）と新しい設定（23:19〜23:28 JST の合間）の両方で確かめた

pwm2 と BIOS の曲線（記録から）:

- 入れ直しのあとの 344 回の記録（23:01:45〜23:32 JST）で、temp9 の値を BIOS の曲線（20:51 45:102 65:178 70:255）に入れた値と pwm2 を比べた。**341 回は BIOS の値以上。3 回だけ下回った**: 23:27:51（temp9 39.5℃、BIOS 90.8、pwm2 89）、23:27:56（43.0℃、97.9、96）、23:28:02（44.5℃、101.0、100）。差は最大 1.9（PWM 0..255。約 0.7%）
- 3 回とも、学習が合間から戻って temp9 が 10 秒ほどで 35 → 44.5℃ に上がったとき。fan2go の温度の平均（約 10 秒）の遅れによる。入れる前に見込んでいた遅れで、3℃ の寄せではこれより急な上がりは埋まらない
- 学習中は GPU の曲線が決めるので、pwm2 は BIOS の値（temp9 52.8℃ で約 132）より大きく上（平均 185）
- 直す案（していない。本人が決める）: 主の CPU の曲線の寄せを 3℃ から 5〜6℃ に広げると、この大きさの上がりは埋まる（合間の pwm2 が 10 前後上がる。入れ直しが要る）。それでも、もっと急な上がりでは 10 秒ほどの遅れは残る（窓はセンサーごとに変えられない）

入れたあとの確かめ方:

```bash
systemctl status fan2go                           # active (running)
cat /run/fan2go/case-fan-gpu-temp.status          # 「<時刻> ok <GPU の℃> gpus=1」
scripts/install-case-fan-control-ubuntu.sh --probe   # pwm5 の enable=1（fan2go が操っている）、pwm2・pwm6 などは BIOS のまま。RPM。（組を使う env なら pwm2 も 1 で、見立てに BIOS の曲線との比べ）
cat /etc/fan2go/case-fan-restore.conf             # 「nct6798 5 5」の 1 行（組を使っていたときは「nct6798 2 5」との 2 行）
journalctl -u fan2go -b --no-pager | grep -E "analyzed|boundar|PWM settings"   # 解析の有無と PWM settings
```

`case-fan-gpu-temp.status` の行は、chibihamuntu では `NVIDIA_EXPECTED_GPUS=0` なので枚数で failsafe にはならず、見えた枚数がそのまま `gpus=1` と出る（dekahamuntu は 2 枚を期待して `gpus=2`）。`nvidia-smi` が失敗する・1.2 秒で返らない・GPU が 1 枚も見えない・数でない値のときは「failsafe 100 <理由>」で、ケースファンとラジエーターのファンは全開になる。

#### 戻した（2026-11-16）

本人の決めで、19:09 JST に入れた最初の形に戻した: ケースファン（pwm5）だけを fan2go で `max(GPU の曲線, CPU の曲線)` で回し、GPU の曲線は dekahamuntu と同じ `45:30 60:45 70:65 78:85 83:100`。ラジエーターのファン（pwm2）は fan2go で操らず、BIOS の制御（SmartFan IV、`pwm2_enable=5`）に戻す。CPU の曲線・最低のデューティ・チャネルは変えない。

- 理由: 執事が「ファンは上がった（ケースファン 726 → 863 RPM、ラジエーター 1,209 → 1,423 RPM）が、学習中の GPU の温度は平均 64.4℃ → 64.2℃ でほとんど変わらなかった。曲線をこのままにするか戻すか」と聞き、本人が「fan, そうなんだ。じゃあ戻そうかな。わりと音が変わったし。」と答えた（上の「入れ直しの結果」）
- env: `CASE_FAN_GPU_CURVE` を最初の値へ、`CASE_FAN_RAD_CHANNELS` を空に。ほかの `CASE_FAN_RAD_*` は試した値のまま残す（`CASE_FAN_RAD_CHANNELS` が空なら読まれない）。もう一度試すなら `CASE_FAN_RAD_CHANNELS` を 2 にして入れ直す
- 書き出す fan2go の設定は、19:09 JST に入れたとき（commit 551a83a・9845cca の env とスクリプト）の `--print-config` とバイト単位で同じ（sha256 `9bb0261a8f62e38318050765904d918c9ed40808c3b14c743726c2cf7e75b21f`。2026-11-16 に実機で sudo なしで比べた）。fans は `case_pwm5` の 1 つ
- スクリプトのラジエーターの組の機能・`--identify --stop`・試験は残す

入れ直しのときの pwm2 の戻り方（スクリプトとソースを読んだ。実機ではまだ）:

1. 入れるスクリプトが fan2go を止める。このとき fan2go 自身（`rad_pwm2` の `onExit: restore`）と unit の `ExecStopPost`（`case-fan-restore-bios`）が、前の記録（`nct6798 5 5`・`nct6798 2 5`）で pwm5・pwm2 を `enable=5` へ戻す。記録を書き直すのはこのあと
2. 記録を書き直す前に、前の記録にあって新しい設定にないチャネル（pwm2）を読む。enable が 5 ならそのまま記録から外す。1（手動）のまま残っていれば、前の記録の 5 へ戻して読み戻す。戻せなければ記録を書き直さずに止まる（前の記録が残るので、次に fan2go が止まるときにも ExecStopPost が pwm2 を戻しに行く）。この確かめは 2026-11-16 に足した。前は、戻しが効かなかったときに pwm2 が手動のまま（固定の値で）取り残されても気づけなかった
3. 新しい記録は `nct6798 5 5` の 1 行。新しい fan2go は pwm2 に触らない

見込み:

- 初回の解析は走らない（`case_pwm5` の id は変わらず、解析の結果は `/var/lib/fan2go/fan2go.db` に残っている）。ラジエーターの組がないので、解析の注意も出ない
- 入れ直しのあいだ、ラジエーターのファンは fan2go が止まった時点で BIOS の曲線（temp9 で引く）へ戻り、そのあとずっと BIOS のまま。学習中なら pwm2 は約 190 から BIOS の値（temp9 55℃ ごろで約 140）へ、fan2 は約 1,420 → 約 1,210 RPM へ下がる見込み（BIOS は遅れなしで値を置く）。ケースファンは止めてから起動するまでの数秒だけ BIOS の制御で、そのあと最初の曲線へ毎秒 15 ずつ寄る（学習中 GPU 64〜66℃ なら pwm5 約 135〜150）
- 2026-11-16 02:51 JST の再起動のあと、fan2go は GPU の温度を読めずに全開になっている（下の「残っていること」）。そのまま入れ直すと、止めた時点で pwm2・pwm5 は全開（255）から BIOS の値へ下がり、起動し直した fan2go は GPU の温度を読める見込み（`/dev/nvidia*` はもうある）。入れたあと `case-fan-gpu-temp.status` が「ok」になっているかも見る

入れたあとに読むだけで確かめること:

```bash
systemctl is-active fan2go; systemctl show fan2go -p NRestarts     # active、0
cat /run/fan2go/case-fan-gpu-temp.status                            # 「<時刻> ok <GPU の℃> gpus=1」（failsafe でない）
cat /etc/fan2go/case-fan-restore.conf                               # 「nct6798 5 5」の 1 行
d=$(grep -l '^nct6798$' /sys/class/hwmon/hwmon*/name | xargs dirname)
for c in 2 5 6; do echo "pwm$c enable=$(cat $d/pwm${c}_enable) pwm=$(cat $d/pwm$c) fan=$(cat $d/fan${c}_input)"; done
#   pwm2 enable=5（BIOS）、pwm5 enable=1（fan2go）、pwm6 enable=5 pwm=255
sha256sum /etc/fan2go/fan2go.yaml                                   # 9bb0261a…b21f（上の値）
journalctl -u fan2go -b --no-pager | grep -E "restore-bios|analyzed|PWM settings" | tail   # pwm2・pwm5 を戻した行、解析なし、case_pwm5 だけ
```

#### 外し方（止めると BIOS の制御へ戻る）

```bash
sudo systemctl stop fan2go            # 一時的に BIOS の制御へ（起動すればまた操る）
sudo systemctl disable --now fan2go   # 次の起動からも操らない
scripts/install-case-fan-control-ubuntu.sh --uninstall   # 全部外す（unit・設定・fan2go・modules-load）
```

`--uninstall` のあとは env の `CASE_FAN_CONTROL` を 0 に戻す（1 のままだと、次に `configure-ubuntu-hardware.sh` を流したときに入れ直される）。

#### 残っていること

- 実機のチェックアウト（`~/.config/nix-config`）は origin/develop のまま（env は `CASE_FAN_CONTROL=0` の古い版）。この変更が develop に入ったら、実機で `git pull` する。それまで実機のチェックアウトで入れるスクリプトを流すと「切ってあります。何も変えていません」で終わる（外しはしない）。pull のあと、写し `~/nix-config-issue6` は消してよい
- **再起動のあと、fan2go が GPU の温度を読めず全開になる（2026-11-16 02:51 JST の起動で見た。読むだけで確かめた。直していない）。** nct6775 は自動で読み込まれ（`/etc/modules-load.d/case-fan-control.conf`）、fan2go も自分で立ち上がった（active・enabled、再起動 0 回）。ただし `case-fan-gpu-temp.status` が「failsafe 100 nvidia-smi が失敗した: Failed to initialize NVML: Unknown Error」のままで、ケースファンとラジエーターのファンが全開（pwm5・pwm2 とも 255。fan5 約 1,025 RPM、fan2 約 1,690 RPM）。同じとき、ログインした端末からの `nvidia-smi` は読めた（43℃）。原因の見立て: systemd が fan2go を起動した時刻（02:51:34.842）には `/dev/nvidia*` がまだなく（「Couldn't stat device /dev/nvidia0: No such file or directory」ほか、`/dev/nvidiactl`・`/dev/nvidia-uvm` も）、unit の `DeviceAllow=/dev/nvidia0` などが許す一覧に入らなかった。ノードができたのは 0.03 秒あと（02:51:34.870）。入れ直し（`systemctl restart`）や `sudo systemctl restart fan2go` で、その起動のあいだは直る見込み。直すなら、unit の NVIDIA の `DeviceAllow` をパスでなくデバイスの種類（`char-nvidia`・`char-nvidia-uvm`・`char-nvidia-caps`。`/proc/devices` の名前で、起動の時点でドライバが読み込まれていれば効く）で書く案がある（dekahamuntu と同じ unit なので、両方で確かめる）。このとき pwm5・pwm2 の `enable` は 0（全開）と読めた（fan2go が操っているときの 1 ではなかった。理由は確かめていない）
- `systemctl stop fan2go` で pwm2・pwm5 が BIOS の制御（enable=5）へ戻ること。入れ直しのときに pwm5 が戻ったのはログで見た。pwm2 は、2026-11-16 の戻しの入れ直しで確かめる（上の「戻した（2026-11-16）」）
- （ラジエーターの組をやめたので、いまは要らない。もう一度試すときに）CPU だけに強い負荷がかかったとき（GPU が冷えているとき）の pwm2。記録は学習と合間だけ。BIOS の曲線をわずかに下回った 3 回（上の「pwm2 と BIOS の曲線」）を受けて、主の CPU の曲線の寄せを広げるかは本人が決める
- ケースの付属ファン 6 つが全部 pwm5 につながっているか
- GPU のファンの回転の前後の比べ（ケースの風が増えたぶんが GPU のファンの回転に出ているか）
- ラジエーターのファンとケースファンの音: 前へ寄せた曲線とラジエーターの組で「わりと音が変わった」（本人）ので、2026-11-16 に戻した

## ComfyUI

NVIDIAドライバの再起動後、専用uv環境へComfyUIを導入する。

```bash
~/.config/nix-config/scripts/install-comfyui-ubuntu.sh
```

インストーラは次を行う。

- `~/ComfyUI`へ公式リポジトリをclone（ホストの設定の `COMFY_REF` が空でなければ、cloneしたあとその版を `checkout --detach` する。取得済みなら触らない）
- Python 3.12の`.venv`を作成
- NVIDIA向けPyTorchとComfyUI依存を導入
- PyTorchからGPUの名前・世代（sm_86 / sm_120）とVRAM、既定のデバイス（`cuda:0`）を確認
- ホストの設定に `COMFY_CUDA_DEVICES` があれば、unitに `CUDA_VISIBLE_DEVICES` を書いてそのGPUだけを使う（chibihamuntuでは書かない）。複数を書くと最初のGPUが既定のデバイスになり、ほかのGPUはノード（`Select CLIP Device` など）で指定したときだけ使われる（dekahamuntuは `0,1`。[dekahamuntu-setup.md の 2-9](dekahamuntu-setup.md#2-9-comfyui-の更新v0452と-minimax-h3-image)）
- `comfyui.service`をsystemd user serviceとして登録・起動
- lingerを有効にし、ログイン前から自動起動

ComfyUIは`127.0.0.1:8188`だけで待ち受ける。インストール後、Tailscale Serveを設定する。

```bash
~/.config/nix-config/scripts/configure-comfyui-tailscale-serve.sh
```

ホストで公開するものが決まっていれば、`hosts/ubuntu/<ホスト名>.env` の `TAILSCALE_SERVE`（「HTTPSのポート=127.0.0.1のポート」の一覧）にまとめて書き、こちらで揃えてもよい（何度流してもよい。一覧にないServeは `--prune` のときだけ外す。`--dry-run` で変えるコマンドだけ表示）:

```bash
~/.config/nix-config/scripts/configure-tailscale-serve-ubuntu.sh --dry-run
~/.config/nix-config/scripts/configure-tailscale-serve-ubuntu.sh
```

`install-tailscale-ubuntu.sh` が `tailscale set --operator=$USER` を設定するので、serve の変更に sudo は要らない（operator が無い機械では sudo に落ちる）。

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

モデルはインストール時には自動取得しない。チェックポイントは`~/ComfyUI/models/checkpoints/`へ配置する。
Civitaiのモデルは`civitai-download <URL>`（Claude Codeからは`civitai-download` skill）で、
種別に応じた`~/ComfyUI/models/`以下へ取得できる。`CIVITAI_TOKEN`は上記のchibihamuntu Vaultから展開する。モデルごとにVAE、text encoder、diffusion modelなどの配置先が異なる場合は、そのモデルの公式手順に従う。
MiniMax H3 Image（画像）の重みは `scripts/install-minimax-h3-image-ubuntu.sh` が revision と sha256 を固定して置く（版はホストの設定の `H3_IMAGE_MODELS` か引数。[dekahamuntu-setup.md の 2-9](dekahamuntu-setup.md#2-9-comfyui-の更新v0452と-minimax-h3-image)）。

unitだけを書き直す場合（`COMFY_CUDA_DEVICES`・`COMFY_EXTRA_ARGS` を変えたとき。sudoなし）:

```bash
~/.config/nix-config/scripts/install-comfyui-ubuntu.sh --unit-only
```

- CUDAの動作確認とunitの書き出しだけをする（apt・clone・venv・PyTorch・依存・lingerは飛ばす）。導入済みの `~/ComfyUI/.venv` がなければ止まる
- 何もしないのは、今のunitと同じで、前回の適用の途中の印がなく、`comfyui.service` が動いているときだけ。どれかが欠ければ（unitが違えば差（`diff -u`）を表示し）、ComfyUIのキューが空なのを確かめてから、印を置き、（違えば）書き、`daemon-reload` と `restart` をして、起動を待ち、印を消す（下の「更新」と同じ確かめ。`--force` でキューを確かめない）
- 途中（書き出し・`daemon-reload`・`restart`・起動の待ち）で失敗したら、失敗した段を表示して終了コード 1 で止まり、印 `~/.local/state/comfyui-update/unit-apply-pending`（`XDG_STATE_HOME` があればその下）が残る。原因を直して同じコマンドを流し直せば、ファイルが同じでも続きから適用する

### ComfyUIの更新と戻し

ComfyUIは自動では更新しない。上げるときは明示的に流す。

```bash
~/.config/nix-config/scripts/update-comfyui-ubuntu.sh                 # COMFY_REF の版（空なら master を pull）
~/.config/nix-config/scripts/update-comfyui-ubuntu.sh --ref <タグ|commit>  # 版を指定（COMFY_REF より優先）
```

- **版**: ホストの設定の `COMFY_REF`（タグかcommit）。空なら今までどおり `git pull --ff-only`（masterに追従）。値があれば `git fetch --tags origin` のあと、そのcommitを `git checkout --detach` する。chibihamuntuは空（master）、dekahamuntuは `v0.45.2`（[dekahamuntu-setup.md の 2-9](dekahamuntu-setup.md#2-9-comfyui-の更新v0452と-minimax-h3-image)）。dekahamuntuは2026-11-14にv0.45.2へ上げたので、2台の版は分かれている
- HEADがブランチから外れている（`COMFY_REF`・`--ref`・`--restore` で固定した）ときに `COMFY_REF` を空にして流すと、pullせずに止まる。masterに追従し直すなら `git -C ~/ComfyUI checkout master`
- **控え**: 変える前に、いまの状態を `~/.local/state/comfyui-update/<UTC時刻>-<短いcommit>/` に控える（`commit`・`describe`（`git describe --tags --always`）・`freeze.txt`（`uv pip freeze`）・`comfy_dir`（対象のComfyUIの絶対パス））。置き場所は `COMFY_SNAPSHOT_DIR` で変えられる。終わりに（起動の待ちで失敗したときも）戻すコマンドを表示する
- 戻すコマンドは今回の対象と方針を引き継ぐ: `COMFY_DIR`・`COMFY_PORT` が既定（`~/ComfyUI`・8188）でなければ `COMFY_DIR=…` などを頭に付け、`--no-restart` で流したなら `--no-restart` を付ける（写しで流したときに表示されたコマンドをそのまま貼っても、本番を変えない）
- 追跡しているファイルに未コミットの変更があれば、何もせずに止まる。未追跡のファイル（例: dekahamuntuの `~/ComfyUI/.chibihamuntu-freeze.txt`）では止まらない（前の版は止まっていた）
- 依存は `requirements.txt`（あれば `manager_requirements.txt` も）を `uv pip install` する
- **キューの確かめ**: 起動し直す前に、ComfyUIのキュー（`/queue`）に実行中・待ちがないことを確かめ、あれば何も変えずに止まる（`--force` で確かめない）。進むのは、ComfyUIにつながらない（止まっている。curl の終了コード 7）ときだけ。タイムアウト（生成中で応答が遅い）やHTTPの誤り、読めない応答では、何も変えずに止まる
- スクリプトが見るのはキューだけ。art-studioのループは項目の合間にキューが空になるので、流す前に、art-studioに実行待ち・実行中のループがないことを自分で確かめる（art-studioの画面のループの一覧か、`~/.local/share/art-studio/studio.db` の `loops` に `state` が `running`・`stopping` のものがないこと）
- **起動の待ち**: 起動し直したあと、`/system_stats` が返るまで待ち（既定180秒、`COMFY_READY_TIMEOUT`）、`comfyui_version` を表示する。返らなければ戻すコマンドを表示して失敗する
- `--no-restart`: gitとvenvだけを変え、systemctlを呼ばない（キューも確かめない）。サービスでない写し（`COMFY_DIR` で別の場所を指す）で試す用

```bash
# キューと art-studio のループを先に見る（どちらも 0 であること）
curl -fsS http://127.0.0.1:8188/queue | jq '[.queue_running, .queue_pending] | map(length)'
sqlite3 ~/.local/share/art-studio/studio.db "select count(*) from loops where state in ('running','stopping');"
```

戻す（控えのパスは更新の最後に表示される）:

```bash
~/.config/nix-config/scripts/update-comfyui-ubuntu.sh --restore ~/.local/state/comfyui-update/<控え>
```

- 控えのcommitに `checkout --detach` し、`freeze.txt` で依存を入れ直す。freezeにはPyTorchのindexにしかない `torch==…+cu130` とPyPIにしかない版が混ざるので、`--extra-index-url https://download.pytorch.org/whl/cu130 --index-strategy unsafe-best-match` を付けている（付けないと「certifi was found on …/whl/cu130, but not at the requested version」で失敗する。dekahamuntuで見た）
- 戻す前にも控えを取るので、戻しを戻せる。`--force`・`--no-restart` は更新と同じ
- 控えの `comfy_dir` がいまの `COMFY_DIR` と違えば、git・キュー・新しい控えより前に、何も変えずに止まる（「この控えは <dir> のもの」と表示する。その場所を戻すなら `COMFY_DIR=<dir>` を付けて流す）。`comfy_dir` のない控え（この確かめを足す前のもの。dekahamuntu の `20261114T222702Z-e3bee7ffc`）は、警告を出していまの `COMFY_DIR` のものとして戻す
- 戻らないもの: `freeze.txt` にない（新しい版で足された）パッケージは消さない。ComfyUIの `user/`（設定・ワークフロー）は触らない（拡張の `custom_nodes/` とモデルもスクリプトは触らない）
- 戻したままにするなら、ホストの設定の `COMFY_REF` も戻した版に直す（直さないと、次の `update-comfyui-ubuntu.sh` でまた `COMFY_REF` の版に上がる）

chibihamuntu（`COMFY_REF` が空）では、`git pull --ff-only` → 依存 → restart の流れは前と同じ。足されたのは、控えを取る・キューを確かめる・起動を待つ・未追跡のファイルで止まらない、の4つ。

## Qwen3.8（27B / Flash-Next）

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
`~/models/qwen3.8-27b/`へaria2で並列・再開可能な形で取得する。
あわせてQwen3.8-Flash-Next（125B-A6B MoE、llama.cpp v0.5.0以降）のUD-Q3_K_XLを
`~/models/qwen3.8-flash-next/`へ取得する。VRAMに収まらないエキスパートは`n-cpu-moe`で
RAMへ置き（48層中38層）、n-gram埋め込み（約29GB）はmmapのまま使う。ubatchを2048にして
prompt処理を速くしている（実測: prompt約480 tok/s、生成約21 tok/s。ロード直後はページキャッシュが
温まるまで遅い）。`codex -p qwen-local-flash`で選べる。無検閲版として
Qwen3.8-Flash-Next-Uncensoredのmradermacher i1-IQ3_M（`n-cpu-moe`は35）も取得し、
`codex -p qwen-local-flash-uncensored`で選べる。各モデルのVision Projectorも
取得してRouter presetで関連付け、画像入力を有効にする。
128K context、Q8 KV cache、単一モデルだけをVRAMへロードするRouterモードの
`qwen38.service`を作成する。`--agent`でWeb UIの組み込みツール（シェル実行・ファイル編集を含む）とMCPプロキシを有効にしている（tailnet内のみ公開）。内蔵Web UIでモデルを切り替えられ、再実行しても取得済みファイルは再取得しない。

GPUが1枚のchibihamuntuでは、RTX 3090を共有するため、`applio.service`はComfyUI・Qwenとunitの`Conflicts=`で排他的に起動する
（GPUが2枚のdekahamuntuの割り当てと `ai-mode` は [dekahamuntu-setup.md](dekahamuntu-setup.md) の「GPU」の節）。
LoRA学習も private repo（`~/ai`）の`lora-train`が同じ`Conflicts=`を持つ一時unitとして起動し、
学習中は`ai-mode`での切替を拒否する。

Qwen Router（`qwen38.service`）の親プロセスはモデル未ロードならVRAMを使わないため、
`WantedBy=comfyui.service`でComfyUIと同時に動かす。ComfyUIのノードからLLMを使うときは、
ノードがComfyUI側のモデルを退避 → `/models/load` → 生成 → `/models/unload` の順に
VRAMを受け渡す（ノード自体は private repo 側）。チャット等でQwenを専有するときは`ai-mode qwen`。

Routerは、一度読み込んだモデルを自分では降ろさない。ホストの設定の `QWEN_SLEEP_IDLE_SECONDS` に秒数を書くと、`qwen38.service`・`qwen38-dual.service` の llama-server に `--sleep-idle-seconds <秒>` を付け、その秒数だけ問いのなかったモデルを降ろす（Routerの `/models` の status が `sleeping` になり、次の問いで読み込み直す）。chibihamuntuは空（付けない。unitは前と同じ）、dekahamuntuは `600`（Qwenのモデルが GPU 1 に載ったままだと、MiniMax H3 Image のテキストエンコーダーの計算（GPU 1）がOutOfMemoryErrorになるため。[dekahamuntu-setup.md の 2-9](dekahamuntu-setup.md#2-9-comfyui-の更新v0452と-minimax-h3-image)）。

```bash
ai-mode qwen    # ComfyUIを止めてQwenを専有
ai-mode comfy   # Qwenのロード済みモデルを下ろし、ComfyUIとQwen Router（モデル未ロード）を起動
ai-mode applio  # 他を止めてApplioを起動
ai-mode stop    # すべて停止（LoRA学習は止めない）
ai-mode status  # 各サービスと学習の状態
```

再起動後はComfyUIとQwen Router（モデル未ロード）が起動する。APIは
`http://127.0.0.1:8080/v1`で待ち受ける。Tailscale接続済みの場合、内蔵Web UIは
HTTPS 8443番でもtailnet内限定で公開する。公開ポートは
`QWEN_TAILSCALE_HTTPS_PORT`で変更できる。

Home Managerだけを再適用する場合:

```bash
nix run ~/.config/nix-config#home-manager -- switch --flake ~/.config/nix-config#$USER@ubuntu-server
```

bashの設定（[ADR 0003](adr/0003-ubuntuのbashにもpathを通す.md)）を含む世代へ初めて上げるときは、Ubuntu標準の`~/.bashrc`・`~/.profile`とぶつかるので`-b backup`を付ける（元のファイルは`~/.bashrc.backup`・`~/.profile.backup`に残る）。上げたらログインし直し、`which pnpm node`と`ssh <ホスト> 'command -v pnpm node'`で両方が出ることを確かめる。

`bootstrap-ubuntu.sh`はsshdを有効化するが、UFWは自動で有効化しない。先にLANまたはTailscale経由のSSH接続を別端末から確認する。ファイアウォールを使う場合は、現在の接続経路を許可してから有効化する。

## 管理境界

| 対象 | 管理方法 |
|---|---|
| CLI、Zsh・Bashの設定、Neovim、mise、llama.cpp | Nix / Home Manager |
| Codex CLI、Claude Code | Ubuntu用bootstrap / 公式インストーラ |
| Python、Node.js | mise |
| sshd、Tailscale daemon | apt / systemd |
| NVIDIAドライバ | Ubuntuの推奨ドライバ |
| HWEカーネル・対応NVIDIAモジュール | `scripts/install-hwe-kernel-ubuntu.sh` / apt。更新前の確認は `scripts/check-nvidia-kernel-modules-ubuntu.sh` |
| ホストごとの差（GPUの割り当て・ドライバの条件・LED・電力） | `hosts/ubuntu/<ホスト名>.env`（スクリプト）、`home/hosts/<ホスト名>.nix`（Home Manager） |
| GPU LED消灯 | 固定版OpenRGB / systemd system service |
| RAPL読み取り権限 | `power`グループ / udevルール（`scripts/install-rapl-power-access-ubuntu.sh`） |
| ComfyUIとPython依存 | ComfyUI専用venvまたはuv環境 |
| Qwenモデル、Qwen user service | 専用の冪等インストールスクリプト |
| ComfyUIのモデル台帳・ワークフロー・custom_nodes、LoRAプロジェクト、AGENTS.md | private repo（`~/ai`）。自作モデルの実体はCloudflare R2 |

## private repo（~/ai）とR2

モデル名やワークフロー、データセットなど個人的な資産はこのpublic repoに入れず、
private repoを`~/ai`へcloneして管理する。`~/.claude/CLAUDE.md`と`~/.codex/AGENTS.md`は
`~/ai/AGENTS.md`へのリンクとしてHome Managerが配置する（clone前はリンク切れになるだけ）。

自作モデルのバックアップ先はCloudflare R2（rclone、S3互換）。認証情報は`chibihamuntu` Vaultの
`R2_CHIBIHAM_AI`アイテム（`access_key_id`・`secret_access_key`・`endpoint`フィールド）から
`RCLONE_CONFIG_R2_*`として展開する。rcloneの設定ファイルは使わない。

GUIなしでもTailscaleは使える。`sudo tailscale up`が表示するURLをMacのブラウザで開いて認証する。CodexやClaude Codeも同様に、SSHセッションへ表示されたURLをMac側で開く方式を使える。
