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

**本人が実機に入れた（2026-11-15 19:09 JST = 10:09 UTC。チャネル 5、GPU の曲線は dekahamuntu と同じ値）。初回の解析は失敗せずに通った（1 分 43.7 秒。下の「初回の解析」）。そのあと本人が GPU の曲線を前へ寄せると決め、env に新しい曲線を書いた。実機への入れ直し（sudo）は本人がこれから（2026-11-15 19:20 JST 時点）。** いま実機で動いているのは最初の曲線。

**同じ日（19:25 JST ごろ）に本人が範囲を広げた: 簡易水冷のラジエーターのファン（pwm2。天面）も fan2go で操り、max(GPU の曲線, CPU の曲線) で回す（下の「ラジエーターのファン（pwm2）も操る」）。env とスクリプトは変えたが、まだ実機には入れていない（2026-11-15 19:30 JST 時点）。** 入れ直しは、GPU の曲線の入れ直しと合わせて 1 回で済む。

ケースファンを GPU の温度に合わせて回す（issue 6）。仕組み（fan2go、ケースファン = max(GPU の曲線, CPU の曲線)、GPU の温度が読めないときは全開側に倒す、止めたとき・落ちたときは BIOS の制御へ戻す、初回の解析）は dekahamuntu と同じスクリプトで、説明は [dekahamuntu-setup.md の「ケースファン（GPU の温度で回す）」](dekahamuntu-setup.md#ケースファンgpu-の温度で回す)。ここには chibihamuntu に固有のことだけを書く。値は `hosts/ubuntu/chibihamuntu.env` の `CASE_FAN_*`（意味は `hosts/ubuntu/README.md`）。

`configure-ubuntu-hardware.sh` は、env が `CASE_FAN_CONTROL=1` のときだけ `install-case-fan-control-ubuntu.sh` を流す。chibihamuntu の env は 1 なので、`configure-ubuntu-hardware.sh` を流すと入れるスクリプトも流れる（入れたあとは、流すたびに fan2go を止めて入れ直す。下の「曲線を変えたあとの入れ直し」）。

| 項目 | chibihamuntu |
|---|---|
| ボード・チップ | ASUS TUF GAMING B760M-PLUS D4（BIOS 1220）、Nuvoton NCT6798D。ドライバは `nct6775`、hwmon の name は `nct6798`（2026-11-15 に実機で確かめた）。ASUS WMI のボード一覧にあり、`acpi_enforce_resources=lax` は要らなかった（`CASE_FAN_ACPI_LAX=0`） |
| 操るチャネル | 5 と 2。<br>5 = ケースファンの組（`CASE_FAN_CHANNELS=5`。回転数も fan5）。ケースの付属ファン 120mm ×6 が付属のハブ 1 つで 5 にまとまっている、という見立て（本人・執事）。6 つ全部が 5 につながっているかは未確認。操れる幅は約 475〜1,070 RPM（pwm=0 で約 475、全開で最大 1,071。2026-11-15 の `--identify`）。<br>2 = ラジエーターの組（`CASE_FAN_RAD_CHANNELS=2`。回転数も fan2）。簡易水冷（Cooler Master MasterLiquid 360L Core）のラジエーター（天面）のファン 120mm ×3（本人が確かめた）。仕様は 650〜1,750 RPM。pwm=0 で止まる（本人が `--identify 2 --stop` で見た）。まだ実機には入れていない |
| 操らないチャネル | pwm6（ポンプと見られる。BIOS の曲線が全点 255、約 2,600 RPM。未確認）は操らない（BIOS の制御のまま全開）。pwm1・pwm4（何もつながっていない見込み）、pwm7（確かめていない）も入れない。<br>はじめは CPU のクーラーのチャネル（pwm2・pwm6）を両方とも入れないことにしていた（issue 6 の「CPU_OPT は入れない」を執事が「CPU のクーラーを操らない」と読み替えた。本人・執事）。issue の本文の「CPU のクーラーは操らない」「操るのはケースファンのチャネルだけ」は、本人の決め（2026-11-15 19:25 JST ごろ）で上書きした: ラジエーターのファン（pwm2）は操る。ポンプ（pwm6）は操らない。<br>pwm5 は BIOS の曲線が pwm2 と同じなので、ボードの上では CPU_OPT のヘッダーかもしれない（pwm5 がボードのどのヘッダーかは未確認）が、つながっているのはケースファンなので操る |
| 最低のデューティ | 30%（`CASE_FAN_MIN_DUTY`）。どの pwm も mode=1（PWM、4pin の制御）。fan5 は pwm=0 でも約 475 RPM で回り続けるので、30% は「止めない」ための下限というより曲線の下の値。30% のときの回転数は未確認 |
| GPU の温度 | RTX 3090 1 枚。`NVIDIA_EXPECTED_GPUS=0` なので枚数は確かめない |
| CPU の温度 | coretemp の temp1（Package id 0）。`CASE_FAN_CPU_HWMON=coretemp`、`CASE_FAN_CPU_TEMP_CHANNEL=1` |
| 曲線 | GPU `45:30 55:50 65:75 72:90 78:100`、CPU `60:30 75:45 85:65 95:100`（℃:デューティ%）。dekahamuntu と違うのは GPU の曲線だけ（CPU の曲線は同じ値）。GPU の曲線は、最初は dekahamuntu と同じ `45:30 60:45 70:65 78:85 83:100` で入れ（2026-11-15 19:09 JST）、同じ日の 19:20 JST ごろに本人が前へ寄せると決めた。本人の言葉は「もう少し曲線を前にしよう。GPUは冷やしたいし、上部はCPUのラジエーターのファンにしているから排気が弱いとおもうんだよね」。新しい曲線の PWM は 45℃ 77・55℃ 128・65℃ 191・72℃ 230・78℃ 255。学習中の 66〜67℃ なら約 77〜79%（PWM 197〜202）の計算（前の曲線では約 59%・150）。fan5 は全開で約 1,070 RPM。新しい曲線は実機にまだ入れていない |
| 前の曲線のとき（実機） | 学習中（GPU 100%・約 335〜340W。2026-11-15 19:13〜19:15 JST、20 秒ごと 6 回）に GPU 66〜67℃、CPU Package 70〜76℃、pwm5 149〜150（enable=1）、fan5 767〜776 RPM。曲線の計算（67℃ → 約 59% = 150）と合う。BIOS のままのほかのチャネルは pwm2 151〜158・fan2 1,248〜1,291 RPM、fan6 約 2,570 RPM。`case-fan-gpu-temp.status` は「<時刻> ok 67 gpus=1」 |
| BIOS の制御のとき | 学習中（GPU 100%・約 340W、GPU 65〜66℃）に pwm5 が 124〜143、fan5 が 650〜750 RPM（本人、2026-11-15） |
| ラジエーターの組の曲線 | GPU `45:30 55:50 65:75 72:90 78:100`（ケースファンの新しい曲線と同じ）、CPU（主）`17:20 42:40 62:70 67:100`（nct6798 の temp9）、CPU（保険）`40:35 60:50 75:65 85:85 92:100`（coretemp の temp1 = Package）。ファン = max(この 3 本)。最低は 20%（`CASE_FAN_RAD_MIN_DUTY=20`。BIOS の最低 51 と同じ）。理由は下の「ラジエーターのファン（pwm2）も操る」。まだ実機には入れていない |
| ラジエーターのファンの BIOS の制御（実機） | 学習中（Package 70〜76℃）は pwm2 151〜158（fan2 1,246〜1,291 RPM）。合間（Package 39〜58℃。1 秒単位で上下する）は temp9 38〜45℃、pwm2 87〜109、fan2 927〜1,032 RPM（2026-11-15、読むだけ） |

チャネルごとの回転数・pwm・BIOS の曲線と、どれが何かの見立て（未確認）は [machines.md の「ファン（2026-11-15）」](machines.md#ファン2026-11-15)。

#### ラジエーターのファン（pwm2）も操る

経緯（2026-11-15 19:25 JST ごろ）: 本人の言葉は「GPUは冷やしたいし、上部はCPUのラジエーターのファンにしているから排気が弱いとおもうんだよね」。執事が「天面のラジエーターのファン（pwm2）は CPU の温度だけで回っていて、学習中は GPU が熱くても天面の排気が上がらない。ここも GPU と CPU の高いほうで回すようにすれば排気が増える。高いほうに合わせる形なら CPU の冷却は弱くならない。やる?」と聞き、本人が「やっとこう」と答えた。ポンプ（pwm6）は操らない。

仕組み: ケースファンの組とは別の「ラジエーターの組」（`CASE_FAN_RAD_*`。意味は `hosts/ubuntu/README.md`）。fan2go の設定には、ファン `rad_pwm2`（曲線 `rad_fans` = maximum(`rad_gpu_curve`, `rad_cpu_curve`, `rad_cpu_backup_curve`)）と、センサー `rad_cpu`（nct6798 の temp9）・`rad_cpu_backup`（coretemp の temp1）が足される。ケースファンの `case_pwm5`・`gpu_max`・`cpu`・`gpu_curve`・`cpu_curve`・`case_fans` は、id も中身も変えない。組がないホスト（dekahamuntu）では、出力は 1 バイトも変わらない。

決まり: **CPU の冷却を BIOS より弱くしない。** 守り方:

- **同じ温度の源**: BIOS の pwm2 の入力は nct6798 の **temp9（ラベル「PECI Agent 0 Calibration」）**。`pwm2_temp_sel=9` で、nct6775 のドライバとドキュメントでは temp_sel の値は sysfs の tempN の N（「Value is temperature sensor index. For example, select '1' for temp1_input」）。実測でも合う（読むだけ。2026-11-15）: temp9 40.5℃ → BIOS の曲線の計算 92.8・実測 pwm2 93、38.0℃ → 87.7・87、36.0℃ → 83.6・83、50.5℃ → 122.9・120。coretemp の Package（= nct6798 の temp8「PECI Agent 0」）そのものではない。主の CPU の曲線は temp9 で引く
- **BIOS の曲線を 3℃ 前へ寄せた**: BIOS の曲線は 20℃:51、45℃:102、65℃:178、70℃:255（5 点目 125℃:255）。点の間は直線で、`pwm2_step_up_time=0`・`pwm2_step_down_time=0`・`pwm2_temp_tolerance=0`。主の CPU の曲線 `17:20 42:40 62:70 67:100` は、PWM で 17℃ 51、42℃ 102、62℃ 179、67℃ 255
- **機械の確かめ**: 入れるスクリプト（と `--print-config`）は、温度の源が BIOS と同じ（`CASE_FAN_RAD_CPU_HWMON` が `CASE_FAN_HWMON` と同じで、`pwm2_temp_sel` が `CASE_FAN_RAD_CPU_TEMP_CHANNEL` と同じ）なら、sysfs の BIOS の曲線（`pwm2_auto_point*`。fan2go が動いていても読める。今の enable には依らない）と主の CPU の曲線を、両方の点の温度の全部で比べる（2 本の折れ線の差は、どちらかの点の温度で最小になる）。1 か所でも BIOS より小さければ、どの温度で BIOS がいくつ・こちらがいくつかを出して止まる。源が違う・BIOS の曲線のファイルがないときは、比べられないと注意を出して進める（標準エラー）。`--probe` の見立てにも比べの結果が出る
- **Package に BIOS の数字をそのまま当てない理由**: Package は temp9 より高く出る（Package 40℃ のとき temp9 36.0、64℃ のとき 50.5）。学習中は Package 70〜76℃ なので、BIOS の数字を当てると、ラジエーターのファンが学習中ずっと全開になる
- **平均の遅れの判断**: fan2go は温度を約 10 秒の指数移動平均でならす（下の「fan2go の動き」）。窓はセンサーごとには変えられず、全体の窓を短くすると dekahamuntu の設定も変わるので変えない。BIOS は遅れなし。3℃ の寄せは、毎秒 0.3℃ までの上がり方なら、ならした温度の遅れ（速さ × 約 10 秒）を埋める。それより速い上がり（CPU の負荷の急な立ち上がり）では、全開に届くのが BIOS より約 10 秒遅れうる。簡易水冷は冷却水とラジエーターの熱容量があり、ファンの 10 秒ほどの遅れで冷却水の温度はほとんど変わらない（250W で 10 秒 = 2.5kJ。冷却水とラジエーターの熱容量を約 1〜1.5kJ/K と見て、放熱がまったくなくても 2℃ ほど。見積もり）。ポンプは BIOS のまま全開
- **保険の曲線（Package）**: 主の源（temp9。ラベルに undocumented とある源）が固まる・0 を返すようになっても、Package の温度でファンが上がる。値 `40:35 60:50 75:65 85:85 92:100` は、観測した BIOS の動き（Package 40℃ → pwm2 83、64℃ → 120、70〜76℃ → 151〜158）以上になるようにした: PWM は 40℃ 89、60℃ 128、75℃ 166、85℃ 217、92℃ 255（64℃ → 138、70℃ → 153、76℃ → 171）。ふだんは保険の曲線のほうが主の曲線より少し高い値を出すので、合間のファンは BIOS より少し（PWM で 10〜20）高く回る見込み
- GPU の曲線は、まずケースファンと同じ（本人・執事）。学習中（GPU 66〜67℃）は PWM 197〜202 の計算（BIOS のときは 151〜158・fan2 約 1,250〜1,290 RPM）。ラジエーターのファンはケースファンよりうるさくなりうるので、入れたあとの音と温度を見て本人が決める

fan2go の動き（fan2go 0.15.0 のソースを別の作業者が読んだもの。実機では未確認の所は見込み）:

- `function: maximum` に 3 本以上の曲線を渡せる。同じセンサー（`gpu_max`）を複数の曲線が使ってよい。同じ platform（nct6798）をファンとセンサーの両方に使ってよい。hwmon のセンサーの `channel: 9` は `temp9_input`
- 温度の平均は指数移動平均（1 秒ごとに `avg ← avg + (x − avg)/10`。時定数 約 9.5 秒）。50→80℃ のステップで平均が 70℃ に届くのは約 10.4 秒。PWM は 200ms に 3（毎秒 15）まで動く
- センサーが読めないとき（見込み）: 動いている間の読みの失敗は、前の平均を保ったまま固まる（毎秒の警告だけ。制御は続く）。0 や負の値はそのまま平均に入り、その曲線は最初の点の値まで下がる（そのときは保険の曲線と GPU の曲線が支える）。起動時にセンサーが見つからないと、それを使う曲線の評価がエラーになり、そのファンの controller が止まって BIOS へ戻る（ほかのファンは動き続ける）
- 止まる・落ちるとき: ファンごとに `onExit: restore` が元の mode（BIOS なら enable=5）を書き戻す。強制終了のときは、unit の `ExecStopPost`（`case-fan-restore-bios`）が `/etc/fan2go/case-fan-restore.conf` の行ごとに戻す。入れるスクリプトは pwm2 の行もそこに書く

#### 入れ方（本人が実機で流す。sudo が要る）

済んだこと（2026-11-15 JST、本人）:

1. `scripts/install-case-fan-control-ubuntu.sh --probe --load-module`（17:00 JST ごろ。nct6775 を一時的に読み込んで調べた。再起動で消える）
2. `--identify 5`（18:25 ごろ。10 秒だけ全開）: fan5 だけが 685 → 最大 1,071 RPM に上がった。`--identify 5 --stop`（19:00 ごろ。10 秒だけ pwm=0）: fan5 が 676 → 475 RPM に下がったが止まらなかった。どちらも終わると元（enable=5 pwm=124）へ戻った。pwm2 はラジエーターのファン（音で確かめ、止めたら止まった）。pwm1・pwm4 は止めても目に見えて止まったファンはなかった。値は [machines.md の「ファン（2026-11-15）」](machines.md#ファン2026-11-15)
3. `hosts/ubuntu/chibihamuntu.env` を `CASE_FAN_CHANNELS=5`・`CASE_FAN_CONTROL=1` にした
4. 入れた（19:09 JST = 10:09 UTC。実機の写し `~/nix-config-issue6`、commit 551a83a と同じ中身で `scripts/install-case-fan-control-ubuntu.sh`）。GPU の曲線は dekahamuntu と同じ `45:30 60:45 70:65 78:85 83:100`。読むだけで確かめたこと:
   - `fan2go.service` は 19:09:26 JST に起動。active・enabled、再起動 0 回、メモリ約 13MB（19:13:54 JST）
   - `/etc/fan2go/fan2go.yaml` の sha256 は `--print-config` の出力と同じ。`/etc/modules-load.d/case-fan-control.conf` に nct6775。`/etc/fan2go/case-fan-restore.conf` は「nct6798 5 5」（入れる前の BIOS の pwm5_enable は 5）
   - 操っているのは pwm5 だけ（enable=1）。pwm1・2・4・6 は enable=5（BIOS の自動）、pwm7 は enable=0 のまま
   - カーネルのログに NVIDIA の Xid はない（起動 16:37 JST から 19:13 JST まで）
   - 入れたあとの値は上の表の「前の曲線のとき（実機）」
5. GPU の曲線を `45:30 55:50 65:75 72:90 78:100` にした（env だけ。19:20 JST ごろ、本人が決めた。上の表の「曲線」）
6. ラジエーターのファン（pwm2）も操ることにした（env とスクリプト。19:25 JST ごろ、本人が決めた。上の「ラジエーターのファン（pwm2）も操る」）

これから流すもの（GPU の曲線とラジエーターの組を合わせた入れ直し。1 回で済む。本人が流す。sudo）:

```bash
cd ~/.config/nix-config

# 1. 書く予定の fan2go.yaml を見る（sudo 不要。ファンは変えない）。fans が case_pwm5 と rad_pwm2 の 2 つで、GPU の曲線が新しい値か、
#    標準エラーに「ラジエーターの pwm2: CASE_FAN_RAD_CPU_CURVE は、BIOS の曲線（temp9。5 点）より弱い所がない」が出るかを見る
scripts/install-case-fan-control-ubuntu.sh --print-config

# 2. 入れ直す（sudo）。コマンドは初めに入れたときと同じ
#    （configure-ubuntu-hardware.sh を流しても、env が 1 なのでこれが流れる）
scripts/install-case-fan-control-ubuntu.sh
```

入れ直しでスクリプトがすること（`do_install` を読んだ）: 設定を確かめる（BIOS の曲線との比べを含む。弱ければ何も変えずに止まる）→ ラジエーターの組があれば、初回の解析でファンが止まる時間がある旨の注意を出す（止めはしない）→ fan2go が動いていれば止める（unit の `ExecStopPost` が BIOS の制御へ戻す）→ fan2go の実行ファイル（SHA256 が合えばそのまま）・センサーと戻しのスクリプトを置き直す → BIOS の `pwm5_enable`・`pwm2_enable` を `case-fan-restore.conf` に書き直す（止めたあとも enable=1 のままなら前の記録を使う。pwm2 は前の記録がないので、enable=1 のまま残っていれば止まる。ふつうは BIOS の 5 が読める）→ 設定を `fan2go config validate` で確かめてから置き換える → unit を置き直して起動し直す（`systemctl restart`）。止めてから起動するまでの短いあいだは BIOS の制御。

解析の結果は `/var/lib/fan2go/fan2go.db` に残る（入れ直しでは消さない）ので、入れ直しでは case_pwm5 の初回の解析は走らない見込み（fan2go 0.15.0 のソースの読み: 保存した結果があれば解析を飛ばす。DB の鍵はファンの `id` だけで、`case_pwm5` の id は変えていないので、ファンを足して入れ直しても解析し直さない。dekahamuntu-setup.md にも「2 回目からは測らない」とある。chibihamuntu では入れ直しのときに `journalctl -u fan2go` で確かめる）。`--uninstall` は `/var/lib/fan2go` を消すので、外してから入れると解析はやり直しになる。

ラジエーターのファン（`rad_pwm2`）は新しいファンなので、入れ直しのときに初回の解析が走る（見込み）。fan2 は pwm=0 で止まるので、止まる所の探索（127 → 63 → 31 → … の二分探索、1 点あたり約 5〜30 秒）のあいだ、ラジエーターのファンが止まる時間が、合わせておそらく 30 秒〜1 分、最悪 3 分前後ある（推測）。そのあとの最大の探索は 255 から。ポンプ（pwm6）は BIOS の制御のまま回り続ける。なので、**学習の合間（CPU と GPU の負荷が低いとき）に流すのがよい**。入れるスクリプトも、入れる前にそう注意を出す（止めはしない）。解析の結果より、設定の `minPwm: 51`・`startPwm: 51`・`maxPwm: 255` が勝つ。

初回の解析（見込みは別の作業者が fan2go 0.15.0 のソースを読んだもの。実機で確かめたのは 2026-11-15 19:09 JST に入れたとき。ログは `journalctl -u fan2go`、時刻は JST）:

- 見込み: 失敗せずに通る。fan5 は止まる点がないので start の境界は PWM 0 になるが、使われるのは設定の `minPwm: 77`・`startPwm: 77`・`maxPwm: 255`（設定に書いた値は解析の結果で上書きされない。`internal/fans/hwmon.go` の `SetStartPwm` など）。ログには「Analysis boundaries detected (before config overrides)」と出る
  - 実機で確かめた: 見込みどおり。19:09:29「Fan 'case_pwm5' has not yet been analyzed, starting initialization sequence...」→ 19:10:06「start/min boundary detected at PWM 0」→ 19:10:39「max boundary confirmed at PWM 255 (threshold 1022.2 RPM)」→ 19:11:12「RPM curve analysis finished in 1m43.695s」「Analysis boundaries detected (before config overrides): Start 1, Max 255」「PWM settings of fan 'case_pwm5': Min 77, Start 77, Max 255」「Starting controller loop」
- 見込み: 解析のあいだ、pwm は曲線と関係なく動く: 127 → 63 → 31 → 15 → 7 → 3 → 1 → 0（止まる所の探索）、255〜191（最大の探索と確認）、32〜224（間の点）。1 点あたり約 5〜30 秒（`analysis.settleTimeout` の既定 30 秒）。合計はおそらく 1.5〜3 分、上限は約 11 分。GPU 自身のファンは別に動く
  - 実機で確かめた: 合計 1 分 43.7 秒（見込みの幅の中）。止まる所の探索は 37.582 秒、最大の探索は 33.046 秒（ログの値）。pwm が一点ずつどう動いたか、fan5 が最低付近にあった時間は記録していない
- 見込み（実機では確かめていない）: 解析の途中で fan2go を止めると、解析が終わるまで終わらず（systemd の既定の 90 秒で SIGKILL）、そのときは unit の `ExecStopPost`（case-fan-restore-bios）が BIOS の制御へ戻す。測った結果は最後にまとめて保存するので、途中で止めると次の起動で解析は最初からやり直し
- 見込み: 動いている間の RPM の検査（平均が 0 なら minPwm を上げる・全開でも 0 なら止まる）には、fan5 はいつも約 475 RPM 以上なので当たらない。入れたあと（19:13〜19:15 JST）は fan5 767〜776 RPM で、fan2go の再起動は 0 回

入れたあとの確かめ方:

```bash
systemctl status fan2go                           # active (running)
cat /run/fan2go/case-fan-gpu-temp.status          # 「<時刻> ok <GPU の℃> gpus=1」
scripts/install-case-fan-control-ubuntu.sh --probe   # pwm5 と pwm2 の enable=1（fan2go が操っている）、pwm6 などは BIOS のまま。RPM。見立てに BIOS の曲線との比べ
cat /etc/fan2go/case-fan-restore.conf             # 「nct6798 5 5」と「nct6798 2 5」の 2 行
journalctl -u fan2go -b --no-pager | grep -E "analyzed|boundar|PWM settings"   # rad_pwm2 の初回の解析。case_pwm5 は解析し直していないこと
```

`case-fan-gpu-temp.status` の行は、chibihamuntu では `NVIDIA_EXPECTED_GPUS=0` なので枚数で failsafe にはならず、見えた枚数がそのまま `gpus=1` と出る（dekahamuntu は 2 枚を期待して `gpus=2`）。`nvidia-smi` が失敗する・1.2 秒で返らない・GPU が 1 枚も見えない・数でない値のときは「failsafe 100 <理由>」で、ケースファンは全開になる。

GPU に負荷をかけて pwm と回転数が上がり、負荷を止めると下がるのを見る（issue 6 の完了条件。前の曲線で学習中の値は読んだが、負荷を止めたとき・戻ったときはまだ確かめていない）。

#### 外し方（ラジエーターの組があっても同じ。止めると pwm2 も BIOS の制御へ戻る）

```bash
sudo systemctl stop fan2go            # 一時的に BIOS の制御へ（起動すればまた操る）
sudo systemctl disable --now fan2go   # 次の起動からも操らない
scripts/install-case-fan-control-ubuntu.sh --uninstall   # 全部外す（unit・設定・fan2go・modules-load）
```

`--uninstall` のあとは env の `CASE_FAN_CONTROL` を 0 に戻す（1 のままだと、次に `configure-ubuntu-hardware.sh` を流したときに入れ直される）。

#### 入れたあとに埋めるところ

- 新しい GPU の曲線とラジエーターの組で入れ直した日時（この節の冒頭と、表の「操るチャネル」「曲線」「ラジエーターの組の曲線」の「まだ入れていない」を直す）
- case_pwm5 の初回の解析が走らなかったか（`journalctl -u fan2go` に case_pwm5 の「has not yet been analyzed」が出ないか）
- rad_pwm2 の初回の解析の結果（かかった時間、start/min・max の境界、「PWM settings of fan 'rad_pwm2'」。fan2 が止まっていた時間が分かれば）
- 学習中と合間の pwm5・fan5・pwm2・fan2 と、GPU の温度・CPU の温度（Package と temp9）。計算では学習中（GPU 66〜67℃）に pwm5・pwm2 とも PWM 197〜202
- CPU に負荷がかかったとき（GPU が冷えているとき）に、pwm2 が BIOS の曲線の値（temp9 で 20:51 45:102 65:178 70:255）を下回らないこと
- ラジエーターのファンの音（GPU の曲線を変えるかは本人が決める）
- 負荷を止めたとき・戻ったときの pwm5・fan5・pwm2・fan2（issue 6 の完了条件）

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
