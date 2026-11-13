# 機械の仕様（4 台）

このリポジトリで管理する 4 台の機械の部品と仕様。仕様の正はこの文書とする。ほかの文書の表（[ubuntu-server.md](ubuntu-server.md)・[dekahamuntu-setup.md](dekahamuntu-setup.md)・[ai-server-placement.md](ai-server-placement.md)）は短い要約で、食い違えばこちらを正とする。

値の出どころ:

- **本人**: 本人の一覧（通販の商品名。末尾の「[出どころ](#出どころ)」に原文がある）
- **実機**: 2026-11-13 に読むだけで読んだ値（sudo なし）。MacBook Air は実機から読めていない
- **仕様**: メーカーの製品ページ・仕様のページ（URL は末尾の「出どころ」）

分からないものは「未確認」と書く。シリアル番号・MAC アドレス・IP アドレス・tailnet のドメインは書かない。

## 一覧

| 機械 | 役割 | flake の構成名 | CPU | メモリ | GPU | ストレージ | OS |
|---|---|---|---|---|---|---|---|
| chibihamuntu | AI サーバー（ComfyUI、Qwen Router、LoRA 学習、Applio） | `chibiham@ubuntu-server` | Intel Core i7-13700KF（16 コア 24 スレッド） | DDR4 64GB（Acclamator OUNCE 32GB ×2。2,666 MT/s で動いている） | RTX 3090 24GB ×1（Gigabyte GeForce RTX 3090 GAMING の系統。OC の有無は未確認） | SATA SSD 2TB（Ubuntu）、NVMe 2TB（Ubuntu からは使っていない） | Ubuntu 24.04.5 LTS |
| dekahamuntu | AI サーバー（2 台目。ComfyUI、Qwen Router） | `chibiham@dekahamuntu` | AMD Ryzen 7 9700X（8 コア 16 スレッド） | DDR5 64GB（32GB ×2、5,600 MT/s） | RTX 5060 Ti 16GB ×2（Palit Infinity 3） | NVMe 2TB | Ubuntu 24.04.5 LTS |
| Mac mini | flake.lock の更新とコミットをする Mac。MacBook から画面共有で操作する。ローカルの Qwen3.8（`qwen38`） | `chibiham@mac-mini` | Apple M4（10 コア） | 32GB | M4 内蔵（10 コア） | 1TB（内蔵） | macOS 27.0.1 |
| MacBook Air | Mac mini を画面共有で操作する Mac。flake.lock は mac-mini で更新したものを pull して反映する | `chibiham@macbook` | Apple M2（8 コア） | 24GB | M2 内蔵（8 コアか 10 コアかは未確認） | 未確認 | 未確認 |

役割は [CLAUDE.md](../CLAUDE.md)・[maintenance.md](maintenance.md)・[ai-server-placement.md](ai-server-placement.md) から分かる範囲で書いた。

---

## chibihamuntu

### 部品

| 部品 | メーカー・製品名 | 型番 | 主要な仕様 | 出どころ |
|---|---|---|---|---|
| CPU | Intel Core i7-13700KF | BX8071513700KF（BOX） | 16 コア（P 8 + E 8）24 スレッド、最大 5.40GHz、キャッシュ 30MB、Processor Base Power 125W・Maximum Turbo Power 253W、FCLGA1700、DDR5 5600 / DDR4 3200 MT/s まで、最大 192GB、PCIe 5.0・4.0（20 レーン）。仕様のページに内蔵 GPU の項目はない | 本人（型番）、仕様（Intel） |
| マザーボード | ASUS TUF GAMING B760M-PLUS D4 | — | Micro ATX（24.4 × 24.4cm）、Intel B760、LGA1700、DDR4 DIMM ×4（最大 128GB、2133〜5333 MT/s。3333 以上は OC）、PCIe 5.0 x16 ×1（CPU）、PCIe 4.0 x16 形状 ×1（x4 動作、チップセット）、PCIe 4.0 x1 ×1、M.2 ×2（どちらも PCIe 4.0 x4。M.2_1 は CPU、M.2_2 はチップセット）、SATA ×4、有線 Realtek 2.5GbE、ファンのヘッダー（4pin）は CPU ×1・CPU OPT ×1・AIO ポンプ ×1・ケース ×3。Wi-Fi の規格は仕様のページで確かめられなかった | 本人、仕様（ASUS） |
| メモリ | Acclamator OUNCE（DDR4-3200 32GB ×2、白ヒートシンク） | 未確認（商品名に出ていない） | 本人: DDR4 PC4-25600（3200MHz）、32GB ×2、CL22（最初の一覧）、電圧は最初の一覧が 1.2V・2 回目が 1.35V。実機: 2,666 MT/s で動いている（下の「食い違い」） | 本人（2 回）、実機 |
| GPU | Gigabyte GeForce RTX 3090 GAMING（OC の有無は未確認） | 本人: GV-N3090GAMING（後ろは未確認）。実機: PCI のサブシステム 1458:4043（どの製品かは照らせなかった） | Gigabyte の GAMING OC 24G（GV-N3090GAMING OC-24GD）の仕様（検索の抜粋）: 24GB GDDR6X、384bit、コアクロック 1,755MHz（同じページの基準のカードは 1,695MHz）、補助電源 8pin ×2、推奨の電源 750W、320 × 129 × 55mm（ギリシャのページの抜粋だけ）、出力 DisplayPort 1.4a ×3・HDMI 2.1 ×2（オランダのページの抜粋）。スロット数は未確認。手元が OC 版でなければ、クロックは違うかもしれない。NVIDIA の RTX 3090 の基準の仕様: 10,496 CUDA コア、グラフィックスカードの電力 350W、NVLink あり | 本人、実機、仕様（Gigabyte の GAMING OC 24G。検索の抜粋）、仕様（NVIDIA の基準） |
| SSD（SATA） | Fanxiang S101 2TB | 未確認 | 本人: 2.5 インチ 7mm、SATA 6Gb/s、3D NAND TLC。仕様: SATA III 6Gb/s、最大 読み 520MB/s・書き 480MB/s（S101 の 1TB の製品ページの値。2TB の値と TBW は未確認） | 本人、仕様（Fanxiang） |
| SSD（NVMe） | Lexar NM790 2TB（本人の一覧にない） | 未確認 | M.2 2280、PCIe Gen4 x4、2TB は 最大 読み 7,400MB/s・書き 6,500MB/s、1,500TBW、保証 5 年 | 実機、仕様（Lexar） |
| 電源 | CORSAIR HX1200 | 未確認（HX1200 の版は未確認） | 本人: 1200W、80 PLUS Platinum。参考に CP-9020140 の HX1200 のページ: 1200W、80 PLUS Platinum、フルモジュラー、ATX12V v2.4、135mm ファン、保証 10 年（12V-2x6 の記載なし）。手元のものがこの版かは未確認 | 本人、仕様（Corsair。版は未確認） |
| CPU クーラー | Cooler Master MasterLiquid 360L Core ARGB White（簡易水冷） | MLW-D36M-A18PZ-RW | ラジエーター 360mm（394 × 119.6 × 27.2mm、アルミ）、ファン 120mm ×3（650〜1,750 RPM、4pin PWM）、ポンプは 3pin、対応ソケット Intel LGA1851/1700/1200/115x、AMD AM5/AM4 ほか | 本人、仕様（Cooler Master） |
| ケース | CPS（PCCOOLER）C3 T500 ARGB WH（ピラーレス） | C3T500-ARGB-WH | ATX ケース、415 × 295 × 368mm、ATX / M-ATX / ITX、付属ファン 120mm ×6（背面 1・側面 2・底面 3、ARGB）、ラジエーター 上 240/280/360・背面 120/140・側面 240・底面 240/280/360mm、GPU 400mm まで、CPU クーラー 175mm まで、電源 200mm まで、3.5 インチ ×2・2.5 インチ ×1、拡張スロット 6。メーカーのページは BK（黒）の値で、WH が同じかは未確認 | 本人、仕様（PCCOOLER） |

本人の一覧で CPU クーラーが 2 回出ているのは、同じもの 1 つと読む。

### 実機で読んだ値（2026-11-13）

- ボード: ASUSTeK TUF GAMING B760M-PLUS D4（Rev 1.xx）、BIOS 1220（2023-08-03）
- OS: Ubuntu 24.04.5 LTS、カーネル 7.0.0-42-generic
- CPU: 13th Gen Intel Core i7-13700KF。24 スレッド（lscpu は 16 コア・1 ソケット）、最大 5,400MHz、L3 30MiB
- メモリ: MemTotal 65,645,188 kB（約 62.6GiB）。4 スロットのうち 2 枚（ロケータ Controller0-ChannelA-DIMM1・Controller1-ChannelA-DIMM1）、各 32GiB、DDR4。SMBIOS のメーカー欄は「Shenzhen Zhongshi Technology Co Ltd」、型番欄は空。速度の欄 2,666 MT/s、動いている速度も 2,666 MT/s。ボードの最大は 128GiB
- GPU: NVIDIA GeForce RTX 3090、24,576MiB、PCI 01:00.0、デバイス 10de:2204（GA102）、サブシステム 1458:4043（1458 = Gigabyte）、VBIOS 94.02.42.40.B7、ドライバ 595.99.02。PCIe 4.0 x16 でつながっている。電力の上限 370W（設定できる最大 390W）
- ディスク:
  - sda = Fanxiang S101 2T（SATA、1.9T）。Ubuntu はこれに入っている。sda1 `/boot/efi` 1G、sda2 `/boot` 2G、sda3 LVM → `/` 1.9T（使用 894G・空き 886G）
  - nvme0n1 = Lexar SSD NM790 2TB（NVMe、PCIe 4.0 x4、ファームウェア 11296）。中は EFI 100M・16M・NTFS 1.9T・NTFS 889M。Ubuntu からはマウントしていない（Windows の並びに見える）
- ネットワーク: 有線 eno1 = Realtek RTL8125（2.5GbE）、1,000Mb/s でつながっている。Wi-Fi wlp6s0 = Realtek RTL8852BE（802.11ax）、up。Bluetooth あり
- ファン: Super I/O のドライバ（nct6775 など）は読み込んでいない（hwmon に pwm・fan がない）。BIOS まかせ
- そのほか: USB に ASUS AURA LED Controller

### 本人の一覧・仕様と実機の食い違い

- メモリの速度: 商品名は 3200MHz（PC4-25600）、実機は 2,666 MT/s で動いている（SMBIOS の速度の欄も 2,666）。BIOS で XMP を使っていないのか、モジュールの SPD が 2,666 なのかは未確認。見立て: DDR4-3200 で 1.35V は XMP のプロファイルによくある組み合わせなので、BIOS で XMP を入れていないため 2,666 MT/s で動いている、という見立てと合う（確かめていない）
- メモリのメーカー: ブランドは Acclamator（本人）、SMBIOS のメーカー欄は「Shenzhen Zhongshi Technology Co Ltd」、型番欄は空。ブランドと製造元の関係は未確認
- メモリの電圧: 最初の一覧の商品名は 1.2V、2 回目の商品名は 1.35V。どちらが正しいかは未確認
- NVMe（Lexar NM790 2TB）が本人の一覧にない
- Wi-Fi: 実機に RTL8852BE（802.11ax）があるが、ASUS の仕様のページで Wi-Fi の規格を確かめられなかった（ボードの名前に WIFI が付かない）。カードがどこに付いているかは未確認
- GPU の電力の上限: 実機は 370W（最大 390W）、NVIDIA の RTX 3090 の仕様は 350W。Gigabyte の製品の値は未確認（GAMING OC 24G の仕様のページの抜粋に電力の項は出てこなかった）

### 未確認

- GPU の正式な型番（OC の付く GV-N3090GAMING OC-24GD か）。検索で見つかった GAMING の RTX 3090 は GV-N3090GAMING OC-24GD だけで、OC の付かない型番は見つからなかったが、Gigabyte の製品の一覧（ページは 403 で取れず）で確かめていないので決めない。カードのスロット数
- PCI のサブシステム 1458:4043 がどの製品か。pci-ids の RTX 3090（10de:2204）の項に Gigabyte（1458）のサブシステムは載っていない。TechPowerUp の VBIOS のデータベースも検索で 1458:4043 の版は見つけられなかった（一覧のページは 403 で取れず）。実機の PCI のデバイス ID は 10de:2204
- メモリの型番、電圧（1.2V か 1.35V か）、2,666 MT/s で動いている理由（XMP を入れていないためか）。XMP を入れるかは本人が BIOS で決める
- 電源 HX1200 の版（型番）。12V-2x6 があるか
- Lexar NM790 がどの M.2 スロット（CPU 側の M.2_1 かチップセット側の M.2_2）に挿さっているか、Windows の用途
- Wi-Fi のカードの出どころ（ボード付属か後付けか）
- ケースファンの数・型番と、どのヘッダーにつながっているか。簡易水冷のファン・ポンプのつなぎ先
- ラジエーターの取り付け位置

---

## dekahamuntu

### 部品

| 部品 | メーカー・製品名 | 型番 | 主要な仕様 | 出どころ |
|---|---|---|---|---|
| CPU | AMD Ryzen 7 9700X | 100-100001404WOF | Zen 5、8 コア 16 スレッド、ベース 3.8GHz・ブースト最大 5.5GHz、L2 8MB・L3 32MB、既定の TDP 65W、AM5、内蔵 GPU は AMD Radeon Graphics（2 コア）、DDR5、PCIe 5.0。CPU クーラーなし | 本人（型番・65W・クーラーなし）、仕様（AMD） |
| マザーボード | ASUS ProArt B850-CREATOR WIFI NEO | — | ATX（30.5 × 24.4cm）、AMD B850、AM5、DDR5 DIMM ×4（最大 256GB）、PCIe 5.0 x16 ×2（CPU。2 本とも使うと x8/x8）、PCIe 4.0 x16 形状 ×1（x4 動作、チップセット。M.2_3 を使うと無効）、PCIe 4.0 x1 ×1、M.2 ×3（M.2_1・M.2_2 は PCIe 5.0 x4（Ryzen 9000）、M.2_3 は PCIe 4.0 x4（チップセット、2280 のみ））、SATA ×4、有線 Realtek 5GbE ×2、Wi-Fi 7（Realtek RTL8922AE、802.11be 2x2）、Bluetooth、ファンのヘッダー（4pin）は CPU ×1・CPU OPT ×1・AIO ポンプ ×1・ケース ×4 | 本人、仕様（ASUS） |
| メモリ | ADATA DDR5-5600 U-DIMM 32GB ×2 | 本人: AD5U560032G-DT-I。SMBIOS: AD5U560032G-B | 本人: DDR5 5600MHz、U-DIMM、32GB ×2。ADATA の DDR5 5600 U-DIMM のページ: CL46、1.1V、PMIC と On-Die ECC を載せる（この型番のページかは未確認） | 本人、実機、仕様（ADATA。型番の一致は未確認） |
| GPU ×2 | Palit GeForce RTX 5060 Ti Infinity 3 16GB | NE7506T019T1-GB2061S | 16GB GDDR7、128bit、448GB/s、4,608 CUDA コア、ブースト 2,572MHz、PCIe 5.0（レーン数はページになし。実機は x8）、グラフィックスカードの電力 180W、推奨のシステム電源 600W、補助電源 8pin ×1、291.9 × 116.6 × 41.3mm、2 スロット | 本人、仕様（Palit、NVIDIA） |
| SSD | KingSpec XG7000 2TB | 未確認（実機のモデル名は XG7000-2TB 2280） | M.2 2280、PCIe Gen4 x4、NVMe 1.4、3D NAND、最大 読み 7,200〜7,400MB/s・書き 4,400〜6,600MB/s（容量ごとの値は未確認）、保証 3 年。TBW はページに 300/600/1200/2400/4000TB と並ぶが容量との対応の記載がない | 本人（7400MB/s）、仕様（KingSpec） |
| 電源 | CORSAIR RM850e | CP-9020296-JP | 850W、フルモジュラー、ATX 3.1（Intel ATX 3.1 認証）、PCIe 5.1、12V-2x6（12+4）×1 と 12V-2x6 → 8pin ×2 のケーブル、120mm ファン、Cybenetics Gold（80 PLUS の記載はページになし）、保証 7 年 | 本人、仕様（Corsair。CP-9020296-NA のページ） |
| CPU クーラー | ID-COOLING FROZN A620 PRO SE（空冷、デュアルタワー、ブラック） | FROZN A620 PRO SE | 120 × 142 × 157mm、ヒートパイプ 6mm ×6、ファン 120 × 120 × 25mm ×2（AS-120-K、300〜2,000 RPM、4pin PWM）、TDP 260W、対応ソケット Intel LGA1851/1700/1200/115x、AMD AM5/AM4 | 本人、仕様（ID-COOLING） |
| ケース | Antec C8 Curve Wood | — | フルタワー、464 × 303 × 476mm（奥行き × 幅 × 高さ）、E-ATX（280mm まで）/ ATX / Micro-ATX / Mini-ITX、ファンは最大 10、ラジエーター 上・側面・底面に 120〜360mm、GPU 440mm まで、CPU クーラー 175mm まで、電源 210mm まで。付属ファンの有無・数は未確認 | 本人、仕様（Antec） |
| ケースファン | Thermalright TL-C12C（光らない版。ARGB の TL-C12C-S は別の型番） | TL-C12C | 実機で 4 チャネル（fan1・3・4・6）。個数は未確認。仕様: 120 × 120 × 25mm、120g、4pin PWM、最大 1,550 RPM ±10%、風量 66.17 CFM、静圧 1.53mmH2O、騒音 25.6 dBA（どれも最大）、S-FDB 軸受、0.20A。電圧・最低の回転数はページになし。ページの分類は「Non-LED 120mm」。何個入りかはページになし（TL-C12C X3 の別のページがあり、仕様は同じ。入り数の記載なし） | 本人（どの機械かは明示していない。執事の読み）、実機、仕様（Thermalright） |

### 実機で読んだ値（2026-11-13）

- ボード: ASUSTeK ProArt B850-CREATOR WIFI NEO（Rev 1.xx）、BIOS 1002（2026-07-13）
- OS: Ubuntu 24.04.5 LTS、カーネル 7.0.0-43-generic
- CPU: AMD Ryzen 7 9700X 8-Core。8 コア 16 スレッド、最大 約 5,582MHz、L3 32MiB
- メモリ: MemTotal 62,879,492 kB（約 60.0GiB。内蔵 GPU の分が引かれている見込み）。4 スロットのうち 2 枚（DIMM 1 ×2）、各 32GiB、DDR5、A-DATA、型番欄は AD5U560032G-B、5,600 MT/s で動いている。ボードの最大は 256GiB
- GPU: NVIDIA GeForce RTX 5060 Ti ×2、各 16,311MiB、PCI 01:00.0 と 03:00.0、サブシステム 1569:f328（1569 = Palit）、VBIOS 98.06.4E.00.1B、ドライバ 595.99.02。どちらも PCIe の幅は x8（カードの最大は PCIe 5.0 x8。アイドルのときは 2.5GT/s に落ちている）。電力の上限 180W。内蔵 GPU（AMD、PCI 0d:00.0、1002:13c0）もある
- ディスク: nvme0n1 = XG7000-2TB 2280（NVMe、PCIe 4.0 x4 でつながっている、ファームウェア 1.W.O.BA、1.9T）。p1 `/boot/efi` 1G、p2 `/boot` 2G、p3 LVM → `/` 1.9T（使用 579G・空き 1.2T）
- ネットワーク: 有線 2 つ（Realtek 10ec:8126 = 5GbE ×2）。eno2 が 5,000Mb/s でつながっている、eno1 は未接続。Wi-Fi wlp10s0 = Realtek 10ec:8922（`rtw89_8922ae`）は未接続。Bluetooth あり
- ファン: Super I/O は nct6799（ドライバ `nct6775`）

  | チャネル | 実機で読んだこと |
  |---|---|
  | fan1・3・4・6 | ケースファン 4 つ。fan2go が GPU の温度で回す（[dekahamuntu-setup.md の「ケースファン」](dekahamuntu-setup.md#ケースファンgpu-の温度で回す)）。本人の答えでは Thermalright TL-C12C。4 チャネルとも mode=1（PWM）。PWM 77（30%）で約 520〜660 RPM、PWM 0 でも止まらない。全開の境の閾値（fan2go の threshold。最大の回転数そのものではない）は pwm1 1,356.6・pwm3 1,318.6・pwm4 1,475.3・pwm6 1,369.9 RPM |
  | fan2・5 | 約 810〜820 RPM でほぼ同じ回転数。CPU クーラーのファン 2 つの見込み（本人は 2 を「たぶん CPU のクーラー」と言っている） |
  | fan7 | 0 RPM |

  ASUS の仕様のファンのヘッダーは 7 つ（CPU・CPU OPT・AIO ポンプ・ケース ×4）。チャネルの番号とヘッダーの対応は未確認
- そのほか: USB にキーボードとマウス、ASUS AURA LED Controller

### 本人の一覧・仕様と実機の食い違い

- メモリの型番: 商品名は AD5U560032G-DT-I、SMBIOS の型番欄は AD5U560032G-B
- メモリの量: 64GB 挿していて、MemTotal は約 60.0GiB（内蔵 GPU の分が引かれている見込み。確かめていない）
- SSD の速度: 本人の一覧は「最大読込 7400MB/s」、KingSpec のページは 7,200〜7,400MB/s（容量ごとの値はない）。M.2_1・M.2_2 は PCIe 5.0 x4 だが、SSD が PCIe 4.0 なので 4.0 x4 でつながっている
- ケースファンの回転数: Thermalright のページの最大は 1,550 RPM ±10%（1,395〜1,705 RPM）。実機の全開の境の閾値は約 1,320〜1,480 RPM で、pwm4 だけがこの幅に入り、ほかの 3 つは幅より少し下。閾値は最大の回転数そのものではないので、食い違いとまでは言えない（全開の回転数は測っていない）

### 未確認

- ケースファンの個数（4 チャネルに何個つないでいるか）と位置（吸気・排気）。ケースの付属ファンの有無
- fan2・fan5 が CPU クーラーのファン 2 つか（本人「たぶん」）。チャネルとヘッダーの対応
- 負荷をかけたときの PCIe の速さ（Gen5 になるか）、P2P の可否
- NVMe がどの M.2 スロットに挿さっているか
- KingSpec XG7000 2TB の TBW と NAND の種類（TLC か QLC か）
- メモリの CL・電圧（ADATA のページの CL46・1.1V がこの型番の値か）

---

## Mac mini

flake の構成名は `chibiham@mac-mini`。

### 仕様

| 項目 | 値 | 出どころ |
|---|---|---|
| 機種 | Mac mini（2024）、機種 ID Mac16,10、型番 Z1JX2J/A | 実機、本人（M4 2024） |
| チップ | Apple M4。CPU 10 コア（高性能 4 + 高効率 6）、GPU 10 コア、Neural Engine 16 コア | 実機（CPU）、仕様（GPU・Neural Engine） |
| メモリ | 32GB（M4 の Mac mini は 16GB が標準、24GB・32GB を選べる） | 本人、実機、仕様 |
| ストレージ | 内蔵 1TB（APPLE SSD AP1024Z、994.66GB）。M4 の Mac mini は 256GB が標準、512GB・1TB・2TB を選べる | 実機、仕様 |
| 端子 | 背面 Thunderbolt 4 ×3、HDMI、ギガビット Ethernet（10Gb Ethernet を選べる）。前面 USB-C（USB 3、10Gb/s）×2、ヘッドホン端子 | 仕様 |
| 画面 | Thunderbolt で 6K ×2 と 5K（または HDMI で 4K）の最大 3 枚 | 仕様 |
| 電源 | 最大の連続消費電力 155W | 仕様 |
| OS | macOS 27.0.1 | 実機 |

### 実機で読んだ値（2026-11-13）

- 有線 LAN（en0）が 1000baseT でつながっている。Wi-Fi も有効
- 外付け: USB の NVMe ケース（RTL9210B-CG）に約 500GB のディスク
- 画面: 1920×1080 が 1 枚

### 未確認

- 有線 LAN が標準のギガビットか 10Gb Ethernet か（いまは 1000baseT でつながっている）
- 外付けの約 500GB のディスクの製品と用途
- 画面の製品

---

## MacBook Air

flake の構成名は `chibiham@macbook`。実機からは読めていない（SSH を受け付けない）。

### 仕様

| 項目 | 値 | 出どころ |
|---|---|---|
| 機種 | MacBook Air（M2, 2022） | 本人（M2、2022） |
| 画面 | 13.6 インチ、2560 × 1664（MacBook Air（M2, 2022）の仕様のページにあるのは 13.6 インチだけ） | 仕様 |
| チップ | Apple M2。CPU 8 コア（高性能 4 + 高効率 4）、GPU 8 コアか 10 コア | 仕様 |
| メモリ | 24GB（8GB が標準、16GB・24GB を選べる） | 本人、仕様 |
| ストレージ | 未確認（256GB が標準、512GB・1TB・2TB を選べる） | 仕様 |
| 端子 | Thunderbolt / USB 4 ×2、MagSafe 3、ヘッドホン端子 | 仕様 |

### 未確認

- GPU のコア数（8 か 10 か）、ストレージの容量
- macOS の版、機種 ID・型番

---

## 出どころ

### 本人の一覧（2026-11-13）

原文のまま。

chibihamuntu:

- Cooler Master MasterLiquid 360L Core ARGB White LGA1700 / AM5対応 360mmラジエーター搭載 簡易水冷 CPUクーラー
- CORSAIR HX1200 1200W PC電源ユニット [80PLUS PLATINUM] RTX4090
- ASUS INTEL 第13.12世代 LGA1700 対応 B760M 搭載 マザ―ボード Micro ATX TUF GAMING B760M-PLUS D4
- 64GB 3200MHz Memory DDR4 / PC4-25600 CL22 1.2V (32GB x 2枚) ヒートシンク付きシリーズ デスクトップPC用
- CPS 高透過率ガラス採用 ピラーレスPCケース C3T500-ARGB-WH
- gigabyte geforce rtx3090
- Cooler Master MasterLiquid 360L Core ARGB White LGA1700 / AM5対応 360mmラジエーター搭載 簡易水冷 CPUクーラー
- intel インテル CPU 第13世代 Core i7-13700KF BOX BX8071513700KF
- Fanxiang S101 SATA SSD 2TB 2.5インチ 7mm 3D NAND TLC採用 6Gb/s高速内蔵ソリッドステートドライブ

dekahamuntu:

- Palit(パリット) GeForce RTX 5060 Ti Infinity 3 16GB / NE7506T019T1-GB2061S x2
- 【エイデータ】 PCメモリ DDR5 64GB (32GB×2) 5600MHz U-DIMM デスクトップ用 AD5U560032G-DT-I
- KingSpec XG7000 2TB SSD M.2 NVMe 2280 PCIe Gen 4.0 最大読込: 7400MB/s SSD内蔵
- ANTEC PCケース C8 Curve Wood
- 【Amazon.co.jp】限定 AMD Ryzen 7 9700X 8コア 16スレッド 100-100001404WOF_4Y | 3.8GHz、65W、CPUクーラーなし
- ASUS ProArt B850-CREATOR WiFi NEO AM5 ATX マザーボード、DDR5
- ID-COOLING FROZN A620 PRO SE - ブラックアウトデュアルタワーエアCPUクーラー
- CORSAIR RM850e PC電源ユニット 850W PCIE 5.1 対応 ATX 3.1 認証済 – CP-9020296-JP

macbook air: M2、2022 24GB

Macmini: M4 2024 32GB

追加（2026-11-13、chibihamuntu のメモリ）:

- 64GB 3200MHz DDR4 PC4-25600 RAM 1.35V (32GB x 2枚) 白ヒートシンク付きシリーズ デスクトップPC用 メモリモジュール Memory Acclamator OUNCE

追加（2026-11-13、chibihamuntu の GPU）:

- 3090はGigabyte GeForce RTX3090 GV-N3090GAMING

追加（2026-11-13、ケースファン。どの機械かは本人が明示していない。dekahamuntu と読んだ）:

- Thermalright TL-C12C CPUファン 120mmケースクーラー、4ピンPWM静音コンピュータファン

### メーカーのページ（2026-11-13 に読んだ）

「検索の抜粋」と書いたものは、ページの本文を取れず、検索で出たそのページの抜粋で値を読んだ。

| 部品 | メーカー・ページの題 | URL |
|---|---|---|
| Core i7-13700KF | Intel「Intel Core i7-13700KF Processor (30M Cache, up to 5.40 GHz) Specifications」 | https://www.intel.com/content/www/us/en/products/sku/230489/intel-core-i713700kf-processor-30m-cache-up-to-5-40-ghz/specifications.html |
| Ryzen 7 9700X | AMD「AMD Ryzen 7 9700X」（検索の抜粋） | https://www.amd.com/en/products/processors/desktops/ryzen/9000-series/amd-ryzen-7-9700x.html |
| TUF GAMING B760M-PLUS D4 | ASUS「TUF GAMING B760M-PLUS D4 - Tech Specs」 | https://www.asus.com/motherboards-components/motherboards/tuf-gaming/tuf-gaming-b760m-plus-d4/techspec/ |
| ProArt B850-CREATOR WIFI NEO | ASUS「ProArt B850-CREATOR WIFI NEO - Tech Specs」 | https://www.asus.com/motherboards-components/motherboards/proart/proart-b850-creator-wifi-neo/techspec/ |
| RTX 3090（基準の仕様） | NVIDIA「GeForce RTX 3090 Family」 | https://www.nvidia.com/en-us/geforce/graphics-cards/30-series/rtx-3090-3090ti/ |
| RTX 3090 GAMING OC 24G | Gigabyte「GeForce RTX 3090 GAMING OC 24G Graphics Card Specifications」（検索の抜粋。ページは 403 で取れず。値はグローバル・スウェーデン・ギリシャ・オランダの各ページの抜粋） | https://www.gigabyte.com/Graphics-Card/GV-N3090GAMING-OC-24GD/sp |
| PCI のサブシステム 1458:4043（照らせなかった） | The PCI ID Repository の 10de:2204 の項（題は記録していない。Gigabyte のサブシステムは載っていない） | https://admin.pci-ids.ucw.cz/read/PC/10de/2204 |
| RTX 5060 Ti（基準の仕様） | NVIDIA「GeForce RTX 5060 Family」 | https://www.nvidia.com/en-us/geforce/graphics-cards/50-series/rtx-5060-family/ |
| RTX 5060 Ti Infinity 3 16GB | Palit「GeForce RTX 5060 Ti Infinity 3 16GB」 | https://www.palit.com/palit/vgapro.php?id=5495&lang=en&pn=NE7506T019T1-GB2061S&tab=sp |
| ADATA DDR5-5600 U-DIMM | ADATA「DDR5 5600 U-DIMM Desktop RAM」（検索の抜粋。ページは 403 で取れず。型番の一致は未確認） | https://www.adata.com/en/consumer/category/computer-memory/dram-module-ddr5-5600-u-dimm/ |
| XG7000 | KingSpec「M.2 NVMe PCIe Gen4 SSD XG7000 2280mm」 | https://www.kingspec.com/product/m2-nvme-pcie-gen4-ssd-xg7000-2280mm.html |
| NM790 | Lexar「Lexar NM790 M.2 2280 PCIe Gen 4x4 NVMe SSD」（検索の抜粋） | https://americas.lexar.com/product/lexar-nm790-m-2-2280-pcie-gen-4x4-nvme-ssd/ |
| S101 | Fanxiang「FanXiang S101 SSD: Reliable SATA III Internal SSD」（1TB のページ、検索の抜粋） | https://ja.fanxiang.com/en/products/internal-solid-state-drive-fanxiang-s101-1tb-ssd |
| RM850e | Corsair「RMe Series RM850e Fully Modular Low-Noise ATX Power Supply」（CP-9020296-NA） | https://www.corsair.com/us/en/p/psu/cp-9020296-na/rme-series-rm850e-fully-modular-low-noise-atx-power-supply-cp-9020296-na |
| HX1200 | Corsair「HX Series HX1200 — 1200 Watt 80 PLUS PLATINUM Certified Fully Modular PSU」（CP-9020140-NA。手元の版かは未確認） | https://www.corsair.com/us/en/p/psu/cp-9020140-na/hx-series-hx1200-1200-watt-80-plus-platinum-certified-fully-modular-psu-cp-9020140-na |
| MasterLiquid 360L Core ARGB White | Cooler Master「MasterLiquid 360L Core ARGB White CPU Liquid Cooler」 | https://www.coolermaster.com/en-us/products/masterliquid-360l-core-argb-white.html |
| FROZN A620 PRO SE | ID-COOLING「FROZN A620 PRO SE」 | https://www.idcooling.com/product/detail?id=496 |
| C8 Curve Wood | Antec「C8 CURVE Wood」（検索の抜粋） | https://www.antec.com/product/case/c8-curve-wood |
| TL-C12C | Thermalright「TL-C12C – Thermalright」 | https://www.thermalright.com/product/tl-c12c/ |
| TL-C12C X3（入り数を見るため） | Thermalright「TL-C12C X3 – Thermalright」（仕様は TL-C12C と同じ。入り数の記載なし） | https://www.thermalright.com/product/tl-c12c-x3/ |
| C3 T500 ARGB | PCCOOLER（CPS）「C3 T500 ARGB」（BK のページ） | http://www.cpspccooler.com/product/c3-t500-argb/ |
| Mac mini（2024） | Apple「Mac mini (2024) - Tech Specs」 | https://support.apple.com/en-us/121555 |
| MacBook Air（M2, 2022） | Apple「MacBook Air (M2, 2022) - Tech Specs」 | https://support.apple.com/en-us/111867 |
