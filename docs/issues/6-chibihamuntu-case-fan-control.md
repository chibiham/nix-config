---
status: doing
created: 2026-11-15
updated: 2026-11-15
assignee: agent
goal:
  - text: hosts/ubuntu/chibihamuntu.env に CASE_FAN_CONTROL=1 と、実機で確かめた CASE_FAN_HWMON・CASE_FAN_CHANNELS(ケースファンのヘッダーだけ。CPU_FAN・CPU_OPT・AIO_PUMP は入れない)、CPU の温度の指定(coretemp の Package)が書いてある
    done: true
  - text: chibihamuntu で install-case-fan-control-ubuntu.sh --print-config が通り、出てくる設定が操るのはケースファンのチャネルだけで、GPU の温度が読めないときは全開側に倒れる形になっている
    done: true
  - text: 試験(tests/test_case_fan_control.py)が Linux で通り、dekahamuntu の設定から出る fan2go の設定が変わっていない
    done: true
  - text: docs に、chibihamuntu のファンのつなぎ方(どのヘッダーに何がつながっているか)・入れ方・外し方が書いてある
    done: true
  - text: 本人が実機に入れたあと、fan2go.service が active で、GPU に負荷をかけるとケースファンの pwm と回転数が上がり、負荷を止めると下がるのを実機で確かめてある
    done: false
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
- 2026-11-15 18:18 [agent] 調べ(fan2go 0.15.0 のソース。実機では動かしていない): fanN_input がいつも 0 のチャネルは、今の設定では操れない。minPwm・startPwm・maxPwm を書いても初回の解析は飛ばされず、「unable to detect start boundary, no spinning PWM found」で失敗して、そのファンだけ BIOS の制御へ戻る。fan2go の process は落ちないので unit は active のまま(気づきにくい)。RPM の検査を切る設定の項目はない。chibihamuntu の fan1・fan4・fan7 は 0 RPM なので、ケースファンがここにつながっていたら別の手当てが要る。--identify の結果待ちで止まる。
- 2026-11-15 18:18 [agent] 返事待ち: chibihamuntu で `--identify` を pwm 1・2・4・5・6・7 のそれぞれに流した結果(どのファンが変わったか、`fanN=` の行)を送ってください。ケースファンのチャネルが決まるまで、`CASE_FAN_CHANNELS` と `CASE_FAN_CONTROL=1` は書きません。
- 2026-11-15 18:29 [agent] 本人の返事(18:25 JST、執事経由): pwm2 はラジエーター(天面)のファン。--identify 5 で fan5 は 685 → 約 1,070 RPM に上がったが、どの位置かは音で分からず。pwm1・4・6・7 は未確認。頼み: 全開では見分けにくいので、10 秒だけ止めて見分けるモードを足す(ポンプと見られるチャネルは明示の指定がないと断る)。直した版の写しを実機のホームの下に置き、本人が流すコマンドを報告に書く。着手。
- 2026-11-15 18:41 [agent] agent/6 に commit(da44c29): --identify <N> --stop(10 秒だけ pwm=0 にして元へ戻す)。BIOS の曲線が全点 255・曲線が読めない・BIOS が全開(enable=0)のチャネルは --allow-pump がないと断る。戻す守りに INT・TERM・HUP の trap を足した。確かめ: chibihamuntu の /tmp の写しで試験 51 件 OK(途中の SIGINT・SIGTERM・SIGHUP で戻る試験を含む)。dekahamuntu の設定から出る fan2go.yaml の sha256 は変更前と同じ。直した版(scripts と hosts)を実機の ~/nix-config-issue6/ に置いた(実機のチェックアウトは触っていない)。読むだけの --probe で「--stop が断るチャネル: pwm6(曲線が全点 255) pwm7(enable=0)」と出るのを確かめた。sudo・--identify は流していない。本人の --identify --stop(pwm 1・4・5、要れば 7・6)の結果待ち。
- 2026-11-15 18:41 [agent] 返事待ち: chibihamuntu で上の `--identify <N> --stop`(pwm 1・4・5。要れば 7、6)を流した結果(どの位置のファンが止まったか、`fanN=` の行)を送ってください。ケースファンのチャネルが決まるまで、`CASE_FAN_CHANNELS` と `CASE_FAN_CONTROL=1` は書きません。
- 2026-11-15 18:53 [agent] 本人の結果(19:00 JST、執事経由): --identify 5 --stop で fan5 は 676 → 約 475 RPM(pwm=0 でも止まらない)。全開は約 1,070 RPM。pwm2 はラジエーターのファン(止めたら止まった)。pwm1・pwm4 を止めても、目に見えて止まったファンはなかった。本人の見立て: ケースファン全体が fan5 の 1 チャネル(6 つ全部が 5 かは目では確かめきれていない)。CASE_FAN_CHANNELS=5、CASE_FAN_CONTROL=1 で進める。完了条件の「CPU_OPT は入れない」は「CPU のクーラーのチャネル(pwm2 のラジエーター、pwm6 のポンプ)は入れない」と読み替える(執事の指示)。
- 2026-11-15 19:00 [agent] 完了条件 0 を済みにした: hosts/ubuntu/chibihamuntu.env(commit 551a83a)に CASE_FAN_CONTROL=1、CASE_FAN_HWMON=nct6798(実機の --probe で確かめた name)、CASE_FAN_CHANNELS=5(本人が --identify 5 と --identify 5 --stop で確かめた。fan5 が 475〜1,070 RPM で動く)、CASE_FAN_CPU_HWMON=coretemp・CASE_FAN_CPU_TEMP_CHANNEL=1(実機で temp1 = Package id 0)。pwm2(ラジエーターのファン)と pwm6(ポンプと見られる)は入れていない。条件の「CPU_OPT は入れない」は、執事の指示で「CPU のクーラーのチャネル(pwm2・pwm6)は入れない」と読み替えた(pwm5 はボードの上では CPU_OPT のヘッダーかもしれないが、つながっているのはケースファン。どのヘッダーかは未確認)。
- 2026-11-15 19:00 [agent] 完了条件 1 を済みにした: chibihamuntu の ~/nix-config-issue6(commit 551a83a と同じ中身。sha256 を Mac の作業ツリーと突き合わせた)で scripts/install-case-fan-control-ubuntu.sh --print-config が exit 0(sudo なし、本物の hwmon)。fans は case_pwm5(platform nct6798、pwmChannel 5、rpmChannel 5)の 1 つだけ(pwmChannel の行は 1 つ)。gpu_max は /usr/local/sbin/case-fan-gpu-temp に ['0','100'] を渡し、gpu_curve の最後は 83: 255、case_fans は maximum(gpu_curve, cpu_curve)。実機で scripts/case-fan-gpu-temp.sh 0 100 は 66000、nvidia-smi を見つけられなくすると「全開側の 100℃ を出します」で 100000 を出した(→ 曲線の最後の 255 = 全開)。
- 2026-11-15 19:00 [agent] 完了条件 2 を済みにした: commit 551a83a を git archive で chibihamuntu(Ubuntu、bash 5.2)の /tmp に写し、python3 -m unittest tests/test_case_fan_control.py → Ran 53 tests、OK(もとの 27 件に、--identify の hwmon の選び方・止めるモード・シグナルで戻ること・設定のコメントの試験を足した)。dekahamuntu の設定: 同じにせの hwmon の木(nct6799・k10temp)で UBUNTU_HOST=dekahamuntu の --print-config の sha256 が、変更前(実機の develop 46daa25)と変更後で同じ 0fd88fd6…ce1cd5。hosts/ubuntu/dekahamuntu.env は変えていない。
- 2026-11-15 19:00 [agent] 完了条件 3 を済みにした: docs/machines.md の chibihamuntu の「ファン（2026-11-15）」に、チャネル 1〜7 ごとの回転数・pwm・BIOS の曲線・つながっているもの(2 = ラジエーターのファン、5 = ケースファン、6 = ポンプと見られる、1・4 = 何もつながっていない見込み、7 = 確かめていない。未確認は未確認と書いた)と --identify の値。docs/ubuntu-server.md の「ケースファン（GPU の温度で回す）」に、構成の表・入れ方(済んだことと、これから流すコマンド)・入れたあとの確かめ方・外し方(stop / disable / --uninstall と env を 0 に戻す)・初回の解析の見込み。差分を読んで確かめた(commit 44be500・da44c29・551a83a)。入れた日時と入れたあとの値は、本人が入れたあとに書き足す。
- 2026-11-15 19:00 [agent] 返事待ち: chibihamuntu で `cd ~/nix-config-issue6 && scripts/install-case-fan-control-ubuntu.sh` を流して入れ、入れ終わったら知らせてください(学習中に入れるか、合間に入れるかは本人の判断で)。入れたあとの確かめはこちらで読むだけでします。
- 2026-11-15 19:14 [agent] 本人が実機に入れた(19:09 JST = 10:09:26 UTC に fan2go.service 起動)。読むだけで確かめた(10:13:54 UTC): active・enabled・再起動 0 回、/etc/fan2go/fan2go.yaml の sha256 は --print-config の出力と同じ、case-fan-restore.conf は「nct6798 5 5」、pwm5 だけ enable=1(ほかは BIOS のまま)。初回の解析は 1 分 43.7 秒で通り、Min 77・Start 77・Max 255(見込みどおり)。学習中 GPU 67℃・Package 75℃ で pwm5=150・fan5=776 RPM、status は「ok 67 gpus=1」。負荷が下がって戻るまで、20 秒ごとの記録を裏で取っている。
- 2026-11-15 19:19 [agent] 完了条件 2 を未済みにした: 印を外す: fan2go を入れたあとの chibihamuntu で試験を流すと 53 件中 16 件が落ちた(IdentifyTests。にせの hwmon の木でも本物の systemctl is-active fan2go を見るので「fan2go が動いています」で止まる)。試験が、流す機械で fan2go が動いているかに依っている。直してから確かめ直す。dekahamuntu の設定の sha256 は変わっていない(0fd88fd6…)。
- 2026-11-15 19:44 [agent] 完了条件 2 を済みにした: 付け直し。commit b15ddf3 を git archive で chibihamuntu(fan2go.service が active のまま)の /tmp に写し、python3 -m unittest tests/test_case_fan_control.py → Ran 91 tests、OK(skipped=1。root でないと流れない本物の fan2go の検査の 1 件)。試験はにせの systemctl・nvidia-smi・journalctl を使い、流す機械の状態に依らなくした(commit 889e2b2)。dekahamuntu の設定: 同じにせの hwmon の木で UBUNTU_HOST=dekahamuntu の --print-config の sha256 が、変更前(実機の develop 46daa25)と変更後(b15ddf3)で同じ 0fd88fd6…ce1cd5。hosts/ubuntu/dekahamuntu.env は変えていない。
- 2026-11-15 19:44 [agent] 完了条件 0 を済みにした: 確かめ直し(commit b15ddf3)。chibihamuntu.env は CASE_FAN_CONTROL=1、CASE_FAN_HWMON=nct6798、CASE_FAN_CHANNELS=5、CASE_FAN_CPU_HWMON=coretemp・TEMP_CHANNEL=1(Package id 0)。本人の決め(2026-11-15 19:25 JST ごろ「やっとこう」)で条件の文の「CPU_FAN・CPU_OPT・AIO_PUMP は入れない」を上書きした: ラジエーターのファン(pwm2)は別の組 CASE_FAN_RAD_CHANNELS=2 で操る。ポンプ(pwm6)は入れていない。GPU の曲線は本人の決めで 45:30 55:50 65:75 72:90 78:100。
