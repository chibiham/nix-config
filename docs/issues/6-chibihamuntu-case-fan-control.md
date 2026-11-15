---
status: doing
created: 2026-11-15
updated: 2026-11-15
goal:
  - text: hosts/ubuntu/chibihamuntu.env に CASE_FAN_CONTROL=1 と、実機で確かめた CASE_FAN_HWMON・CASE_FAN_CHANNELS(ケースファンのヘッダーだけ。CPU_FAN・CPU_OPT・AIO_PUMP は入れない)、CPU の温度の指定(coretemp の Package)が書いてある
    done: false
  - text: chibihamuntu で install-case-fan-control-ubuntu.sh --print-config が通り、出てくる設定が操るのはケースファンのチャネルだけで、GPU の温度が読めないときは全開側に倒れる形になっている
    done: false
  - text: 試験(tests/test_case_fan_control.py)が Linux で通り、dekahamuntu の設定から出る fan2go の設定が変わっていない
    done: false
  - text: docs に、chibihamuntu のファンのつなぎ方(どのヘッダーに何がつながっているか)・入れ方・外し方が書いてある
    done: false
  - text: 本人が実機に入れたあと、fan2go.service が active で、GPU に負荷をかけるとケースファンの pwm と回転数が上がり、負荷を止めると下がるのを実機で確かめてある
    done: false
assignee: agent
---
# chibihamuntu のケースファンを GPU の温度に合わせて回す

## 内容

本人(2026-11-15):

> dekahamuntuと同様、ケースファンはgpu温度におうじて動くように設定しよう。この際。cpuは簡易水冷だし

(きっかけ: 同じ日の 10:30 JST に chibihamuntu の RTX 3090 がバスから落ちて学習が止まった。Xid 79 → Xid 154。原因は未確認で、熱かどうかも分かっていない。同じ Xid 79 は 11-01 にも出ている)

### 執事の読み(本人の言葉ではない)

- dekahamuntu で入れたケースファンの制御(fan2go。`scripts/install-case-fan-control-ubuntu.sh`、`hosts/ubuntu/<ホスト名>.env` の `CASE_FAN_*`)を、chibihamuntu にも入れる。スクリプトはホストに依らない作りなので、主な作業は chibihamuntu の値を決めて `hosts/ubuntu/chibihamuntu.env` に書くことと、文書。スクリプトに直しが要ると分かったら、dekahamuntu の挙動を変えない形で直す。
- ケースファン = max(GPU の温度, CPU の温度) の形は dekahamuntu と同じでよい。CPU は簡易水冷(Cooler Master MasterLiquid 360L Core。ラジエーターのファン 120mm ×3、ポンプは 3pin)なので、**CPU_FAN・CPU_OPT・AIO_PUMP のヘッダーは操らない**(BIOS の制御のまま)。操るのはケースファンのヘッダー(CHA_FAN1〜3)だけ。
- CPU の温度は Intel なので `CASE_FAN_CPU_HWMON=coretemp`、`CASE_FAN_CPU_TEMP_CHANNEL=1`(Package id 0)。

### 執事が実機で読んだこと(2026-11-15 16:20 JST ごろ。`--probe`、sudo なし)

- ボード: ASUSTeK TUF GAMING B760M-PLUS D4、BIOS 1220、カーネル 7.0.0-43-generic。ファンのヘッダー(4pin)は CPU ×1・CPU OPT ×1・AIO ポンプ ×1・ケース ×3(docs/machines.md)。
- nct6775 の ASUS WMI のボード一覧に、このボードが**ある**(`acpi_enforce_resources=lax` なしで読める見込み)。
- いまは nct6775 が読み込まれておらず、pwm のある hwmon は 0(acpitz・r8169・nvme・asus(eeepc-wmi)・coretemp だけ)。Super I/O のチップ名・pwm のチャネル・どのチャネルがどのヘッダーかは**未確認**。
- 実機の `~/.config/nix-config` は develop で origin と一致(ファンのスクリプトは入っている)。fan2go は未導入。
- ケース(CPS C3 T500)の付属ファンは 120mm ×6(背面 1・側面 2・底面 3、ARGB)。どのヘッダーに何がつながっているか、3pin か 4pin かは未確認。

### まだ分かっていない値(本人の手が要る)

sudo が要るので、本人が実機で流す。執事が結果を読んでこの issue に書き足す。

1. `scripts/install-case-fan-control-ubuntu.sh --probe --load-module`(ドライバを一時的に読み込んで、hwmon の name・pwm・fan・mode を出す)
2. `scripts/install-case-fan-control-ubuntu.sh --identify <チャネル>`(10 秒だけ全開にして、どのファンが回るかを本人が見る)を、pwm のチャネルごとに

## 進め方

- 値(`CASE_FAN_HWMON`・`CASE_FAN_CHANNELS`・3pin なら `CASE_FAN_MIN_DUTY`)がこの issue に書き足されてから始める。書かれていなければ、推測で進めずに止まって聞く。
- 曲線は、まず dekahamuntu と同じ値(GPU `45:30 60:45 70:65 78:85 83:100`、CPU `60:30 75:45 85:65 95:100`)から。3090 は 5060 Ti より熱いので、変えたほうがよい根拠が実機の値から出たら、案として報告に書く(勝手に変えない)。
- 実機に入れる(`install-case-fan-control-ubuntu.sh`、sudo)のは本人。エージェントは `--print-config` で書く予定の設定を確かめるところまで。sudo が要る操作、home-manager switch、push はやらずに止まって聞く。
- 試験(`tests/test_case_fan_control.py`)は Linux で流す(macOS の bash 3.2 では mapfile がなく落ちる。前からの挙動)。
- dekahamuntu の設定と挙動を変えない。
- 文書: docs/machines.md(ファンのつなぎ方)、ホストの手順の文書(chibihamuntu の節)、hosts/ubuntu/README.md(要れば)に、構成・入れ方・外し方を書く。

## 作業ログ

- 2026-11-15 18:11 [me] 完了条件の案を有効にした(ゴールのタスクにした)
- 2026-11-15 18:13 [agent] 着手。chibihamuntu を sudo なしで読んだ(ssh、--probe と sysfs): hwmon nct6798、pwm 1・2・4・5・6・7(どれも mode=1)。BIOS の自動の曲線は pwm1 と pwm4 が同じ(20:153 45:178 60:216 70:255)、pwm2 と pwm5 が同じ(20:51 45:102 65:178 70:255)、pwm6 は常に 255。fan1・fan4・fan7 は 0 RPM。CASE_FAN_CHANNELS は --identify 待ち(推測で決めない)。試験は変更前の agent/6 を /tmp に写して chibihamuntu(bash 5.2)で 27 件 OK。
- 2026-11-15 18:17 [agent] agent/6 に commit: (1) --identify を CASE_FAN_HWMON が空でも使えるように(pwm のある Super I/O が 1 つのときそれを使う。--probe に「--identify が使う hwmon」の行)。(2) chibihamuntu.env に確かめた値(nct6798、coretemp の temp1、曲線は dekahamuntu と同じ)。CASE_FAN_CHANNELS は空、CASE_FAN_CONTROL は 0 のまま。(3) docs/machines.md・docs/ubuntu-server.md に読めた値と入れ方・外し方の下書き(つなぎ方は未確認)。確かめ: 作業ツリーを chibihamuntu の /tmp に写して試験 31 件 OK。dekahamuntu の設定(にせの hwmon の木)から出る fan2go.yaml は、変更前(実機の develop 46daa25)と変更後で sha256 が同じ。
