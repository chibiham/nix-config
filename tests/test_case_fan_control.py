"""Hardware-free checks for the case fan control (fan2go) scripts.

Uses a fake hwmon tree and a fake nvidia-smi. Needs bash 4 or later
(on macOS: BASH=$(nix build --print-out-paths nixpkgs#bash)/bin/bash).
"""

import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest


REPO = Path(__file__).resolve().parents[1]
INSTALL = REPO / "scripts/install-case-fan-control-ubuntu.sh"
GPU_TEMP = REPO / "scripts/case-fan-gpu-temp.sh"
RESTORE = REPO / "scripts/case-fan-restore-bios.sh"
BASH = os.environ.get("BASH_FOR_TESTS", "bash")


def make_hwmon(root, index, name, files):
    d = root / f"hwmon{index}"
    d.mkdir(parents=True)
    (d / "name").write_text(name + "\n")
    for key, value in files.items():
        (d / key).write_text(f"{value}\n")
    return d


class Fixture:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.hwmon = self.base / "hwmon"
        self.nct = make_hwmon(self.hwmon, 0, "nct6799", {
            "pwm1": 120, "pwm1_enable": 5, "fan1_input": 1100,
            "pwm2": 90, "pwm2_enable": 5, "fan2_input": 800,
            "pwm3": 90, "pwm3_enable": 5, "fan3_input": 0,
            "fan4_input": 600,
        })
        make_hwmon(self.hwmon, 1, "k10temp", {"temp1_input": 45000, "temp1_label": "Tctl"})

    def close(self):
        self.tmp.cleanup()


# ラジエーターの組の変数を全部空にする（流す人の環境に依らないように。既定の CASE_FAN_RAD_MIN_DUTY は 20 に戻る）
RAD_OFF = {
    "CASE_FAN_RAD_CHANNELS": "",
    "CASE_FAN_RAD_MIN_DUTY": "",
    "CASE_FAN_RAD_GPU_CURVE": "",
    "CASE_FAN_RAD_CPU_CURVE": "",
    "CASE_FAN_RAD_CPU_HWMON": "",
    "CASE_FAN_RAD_CPU_TEMP_CHANNEL": "",
    "CASE_FAN_RAD_CPU_BACKUP_CURVE": "",
    "CASE_FAN_RAD_CPU_BACKUP_HWMON": "",
    "CASE_FAN_RAD_CPU_BACKUP_TEMP_CHANNEL": "",
}

# BIOS の pwm2 の曲線（chibihamuntu と同じ値。温度はミリ度）
BIOS_CURVE = [(20000, 51), (45000, 102), (65000, 178), (70000, 255), (125000, 255)]

# ラジエーターの組を使う値（chibihamuntu の主の CPU の曲線と同じ。ケースファンは pwm3、ラジエーターのファンは pwm2）
RAD_ON = {
    "CASE_FAN_CHANNELS": "3",
    "CASE_FAN_RAD_CHANNELS": "2",
    "CASE_FAN_RAD_GPU_CURVE": "45:30 55:50 65:75 72:90 78:100",
    "CASE_FAN_RAD_CPU_CURVE": "17:20 42:40 62:70 67:100",
    "CASE_FAN_RAD_CPU_HWMON": "nct6799",
    "CASE_FAN_RAD_CPU_TEMP_CHANNEL": "9",
}

RAD_BACKUP = {
    "CASE_FAN_RAD_CPU_BACKUP_CURVE": "40:35 60:50 75:65 85:85 92:100",
    "CASE_FAN_RAD_CPU_BACKUP_HWMON": "coretemp",
    "CASE_FAN_RAD_CPU_BACKUP_TEMP_CHANNEL": "1",
}


def add_radiator(fx):
    """にせの木に、ラジエーターの組の温度の源と BIOS の曲線を足す: nct6799 の temp9・pwm2_temp_sel=9・pwm2 の BIOS の曲線、coretemp の temp1"""
    (fx.nct / "temp9_input").write_text("40500\n")
    (fx.nct / "pwm2_temp_sel").write_text("9\n")
    for m, (t, v) in enumerate(BIOS_CURVE, start=1):
        (fx.nct / f"pwm2_auto_point{m}_temp").write_text(f"{t}\n")
        (fx.nct / f"pwm2_auto_point{m}_pwm").write_text(f"{v}\n")
    make_hwmon(fx.hwmon, 2, "coretemp", {"temp1_input": 45000, "temp1_label": "Package id 0"})


def block(text, start):
    """text の中の、start の行から次の「  - id:」の行か空の行の前までを返す"""
    lines = text.splitlines(keepends=True)
    i = lines.index(start + "\n")
    out = [lines[i]]
    for line in lines[i + 1:]:
        if line.startswith("  - id:") or line == "\n":
            break
        out.append(line)
    return "".join(out)


class PrintConfigTests(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def run_print(self, **env):
        full = {
            **os.environ,
            "UBUNTU_HOST": "no-such-host-for-tests",
            "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
            "CASE_FAN_HWMON": "nct6799",
            "CASE_FAN_CHANNELS": "2 3",
            "NVIDIA_EXPECTED_GPUS": "2",
            **RAD_OFF,
            **env,
        }
        return subprocess.run([BASH, str(INSTALL), "--print-config"], env=full,
                              capture_output=True, text=True)

    def test_gpu_only_config(self):
        r = self.run_print()
        self.assertEqual(r.returncode, 0, r.stderr)
        y = r.stdout
        self.assertIn("platform: nct6799", y)
        self.assertIn("id: case_pwm2", y)
        self.assertIn("id: case_pwm3", y)
        self.assertNotIn("case_pwm1", y)
        # 30% → 77
        self.assertIn("minPwm: 77", y)
        self.assertIn("useUnscaledCurveValues: true", y)
        self.assertIn("onExit: restore", y)
        self.assertIn("args: ['2', '100']", y)
        # 既定の GPU の曲線 45:30 60:45 70:65 78:85 83:100
        for step in ["- 45: 77", "- 60: 115", "- 70: 166", "- 78: 217", "- 83: 255"]:
            self.assertIn(step, y)
        self.assertNotIn("cpu_curve", y)
        # fan2go 0.15.0 は function の曲線に 2 本以上を要る。CPU の曲線がなければ function を出さず、ファンが GPU の曲線を直に指す
        self.assertNotIn("function:", y)
        self.assertNotIn("type: maximum", y)
        self.assertNotIn("case_fans", y)
        self.assertEqual(y.count("    curve: gpu_curve\n"), 2)
        self.assertIn("ケースファン = GPU の曲線（CPU の曲線なし）", y)
        self.assertNotIn("max(GPU の曲線, CPU の曲線)", y)

    def test_gpu_sensor_comment_with_expected_count(self):
        r = self.run_print()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(
            "  # NVIDIA の GPU の温度の最大（ミリ度）。読めないとき・枚数が 2 枚でないときは 100℃ を出す（全開）\n"
            "  - id: gpu_max\n", r.stdout)

    def test_gpu_sensor_comment_when_count_is_not_checked(self):
        r = self.run_print(NVIDIA_EXPECTED_GPUS="0")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(
            "  # NVIDIA の GPU の温度の最大（ミリ度）。読めないときは 100℃ を出す（全開）。枚数は確かめない（NVIDIA_EXPECTED_GPUS=0）\n"
            "  - id: gpu_max\n", r.stdout)
        self.assertNotIn("0 枚でない", r.stdout)
        self.assertIn("args: ['0', '100']", r.stdout)

    def test_cpu_curve_is_combined_with_maximum(self):
        r = self.run_print(CASE_FAN_CPU_CURVE="60:30 95:100")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("platform: k10temp", r.stdout)
        self.assertIn("channel: 1", r.stdout)
        self.assertIn("- gpu_curve\n        - cpu_curve", r.stdout)

    def test_pwm_rpm_pair(self):
        r = self.run_print(CASE_FAN_CHANNELS="2:4")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("rpmChannel: 4\n      pwmChannel: 2", r.stdout)

    def test_missing_channel_is_refused(self):
        r = self.run_print(CASE_FAN_CHANNELS="2 7")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("pwm7", r.stderr)
        self.assertEqual(r.stdout, "")

    def test_missing_rpm_is_refused(self):
        r = self.run_print(CASE_FAN_CHANNELS="2:9")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")

    def test_empty_channels_are_refused(self):
        r = self.run_print(CASE_FAN_CHANNELS="")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")

    def test_duplicate_channel_is_refused(self):
        r = self.run_print(CASE_FAN_CHANNELS="2 2")
        self.assertNotEqual(r.returncode, 0)

    def test_unknown_hwmon_is_refused(self):
        r = self.run_print(CASE_FAN_HWMON="nct6798")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "")

    def test_two_chips_with_same_name_are_refused(self):
        make_hwmon(self.fx.hwmon, 5, "nct6799", {"pwm2": 1, "pwm2_enable": 5, "fan2_input": 1})
        r = self.run_print()
        self.assertNotEqual(r.returncode, 0)

    def test_bad_curve_is_refused(self):
        for curve in ["45:30 40:50", "45:130 60:50", "45-30 60:50", "45:30"]:
            with self.subTest(curve=curve):
                r = self.run_print(CASE_FAN_GPU_CURVE=curve)
                self.assertNotEqual(r.returncode, 0)
                self.assertEqual(r.stdout, "")

    def test_curve_must_reach_full_below_failsafe_temperature(self):
        r = self.run_print(CASE_FAN_GPU_CURVE="45:30 100:100")
        self.assertNotEqual(r.returncode, 0)

    def test_gpu_curve_must_end_at_full_duty(self):
        # fan2go の線形の曲線は最後の点より上で最後の値のまま。100% でなければ、GPU が読めないときに全開にならない
        for curve in ["45:30 83:65", "45:30 83:99"]:
            with self.subTest(curve=curve):
                r = self.run_print(CASE_FAN_GPU_CURVE=curve)
                self.assertNotEqual(r.returncode, 0)
                self.assertEqual(r.stdout, "")
                self.assertIn("最後の点は 100%", r.stderr)

    def test_cpu_curve_need_not_end_at_full_duty(self):
        r = self.run_print(CASE_FAN_CPU_CURVE="60:30 95:65")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("- 95: 166", r.stdout)

    def test_min_duty_bounds(self):
        r = self.run_print(CASE_FAN_MIN_DUTY="5")
        self.assertNotEqual(r.returncode, 0)
        r = self.run_print(CASE_FAN_MIN_DUTY="50")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("minPwm: 128", r.stdout)


class RadiatorPrintConfigTests(unittest.TestCase):
    """ラジエーターの組（CASE_FAN_RAD_*）の設定と守り"""

    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        add_radiator(self.fx)
        # BIOS のモードの記録（case-fan-restore.conf）の置き場。流す機械の /etc/fan2go は読まない
        self.etc = self.fx.base / "etc-fan2go"
        self.etc.mkdir()
        self.record = self.etc / "case-fan-restore.conf"

    def run_print(self, **env):
        full = {
            **os.environ,
            "UBUNTU_HOST": "no-such-host-for-tests",
            "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
            "CASE_FAN_HWMON": "nct6799",
            "CASE_FAN_CPU_CURVE": "60:30 95:100",
            "NVIDIA_EXPECTED_GPUS": "0",
            "CASE_FAN_TEST_CONFIG_DIR": str(self.etc),
            **RAD_OFF,
            **RAD_ON,
            **env,
        }
        return subprocess.run([BASH, str(INSTALL), "--print-config"], env=full,
                              capture_output=True, text=True)

    def assert_refused(self, r, *messages):
        self.assertNotEqual(r.returncode, 0, r.stdout)
        self.assertEqual(r.stdout, "")
        for m in messages:
            self.assertIn(m, r.stderr)

    def test_config_with_backup(self):
        r = self.run_print(**RAD_BACKUP)
        self.assertEqual(r.returncode, 0, r.stderr)
        y = r.stdout
        self.assertIn("# fan2go 0.15.0。ケースファン = max(GPU の曲線, CPU の曲線)、"
                      "ラジエーターのファン = max(GPU の曲線, CPU の曲線, CPU の保険の曲線)。曲線の値は", y)
        rad = block(y, "  - id: rad_pwm2")
        for line in ["      platform: nct6799", "      rpmChannel: 2", "      pwmChannel: 2", "    curve: rad_fans",
                     "    neverStop: true", "    minPwm: 51", "    startPwm: 51", "    maxPwm: 255",
                     "    pwmMap: identity", "    setPwmToGetPwmMap: identity", "    useUnscaledCurveValues: true",
                     "        maxPwmChangePerCycle: 3", "      active: pwm", "      onExit: restore"]:
            self.assertIn(line + "\n", rad)
        # ケースファンは今までどおり
        case = block(y, "  - id: case_pwm3")
        self.assertIn("    curve: case_fans\n", case)
        self.assertIn("    minPwm: 77\n", case)
        self.assertNotIn("case_pwm2", y)
        self.assertIn("  - id: rad_cpu\n    hwmon:\n      platform: nct6799\n      channel: 9\n", y)
        self.assertIn("  - id: rad_cpu_backup\n    hwmon:\n      platform: coretemp\n      channel: 1\n", y)
        self.assertIn("  - id: rad_gpu_curve\n    linear:\n      sensor: gpu_max\n      steps:\n"
                      "        - 45: 77\n        - 55: 128\n        - 65: 191\n        - 72: 230\n        - 78: 255\n", y)
        self.assertIn("  - id: rad_cpu_curve\n    linear:\n      sensor: rad_cpu\n      steps:\n"
                      "        - 17: 51\n        - 42: 102\n        - 62: 179\n        - 67: 255\n", y)
        self.assertIn("  - id: rad_cpu_backup_curve\n    linear:\n      sensor: rad_cpu_backup\n      steps:\n"
                      "        - 40: 89\n        - 60: 128\n        - 75: 166\n        - 85: 217\n        - 92: 255\n", y)
        self.assertIn("  - id: rad_fans\n    function:\n      type: maximum\n      curves:\n"
                      "        - rad_gpu_curve\n        - rad_cpu_curve\n        - rad_cpu_backup_curve\n\n", y)
        # 比べが通ったことは標準エラーへ（設定には混ぜない）
        self.assertIn("ラジエーターの pwm2: CASE_FAN_RAD_CPU_CURVE は、BIOS の曲線（temp9。5 点）より弱い所がない"
                      "（BIOS のモード: SmartFan IV（pwm2_enable=5。いまの値）。両方の点の温度 9 か所で比べた）",
                      r.stderr)
        self.assertNotIn("BIOS の曲線（", y)

    def test_config_without_backup(self):
        r = self.run_print()
        self.assertEqual(r.returncode, 0, r.stderr)
        y = r.stdout
        self.assertIn("ラジエーターのファン = max(GPU の曲線, CPU の曲線)。曲線の値は", y)
        self.assertNotIn("rad_cpu_backup", y)
        self.assertIn("      curves:\n        - rad_gpu_curve\n        - rad_cpu_curve\n\nstatistics:", y)

    def test_case_fan_part_is_unchanged(self):
        # 組なしの出力の行（頭のコメントの 2 行目を除く）は、組ありの出力にそのままの順で全部ある
        off = self.run_print(CASE_FAN_RAD_CHANNELS="")
        on = self.run_print(**RAD_BACKUP)
        self.assertEqual(off.returncode, 0, off.stderr)
        self.assertEqual(on.returncode, 0, on.stderr)
        off_lines = off.stdout.splitlines()
        on_lines = on.stdout.splitlines()
        self.assertNotEqual(off_lines[1], on_lines[1])
        del off_lines[1]
        del on_lines[1]
        rest = iter(on_lines)
        missing = [line for line in off_lines if not any(line == other for other in rest)]
        self.assertEqual(missing, [])

    def test_radiator_settings_are_ignored_without_channels(self):
        plain = self.run_print(**RAD_OFF)
        ignored = self.run_print(CASE_FAN_RAD_CHANNELS="", **RAD_BACKUP)
        self.assertEqual(plain.returncode, 0, plain.stderr)
        self.assertEqual(ignored.stdout, plain.stdout)
        self.assertEqual(ignored.stderr, "")
        self.assertNotIn("rad_", plain.stdout)
        self.assertNotIn("ラジエーター", plain.stdout)

    def test_min_duty(self):
        r = self.run_print(CASE_FAN_RAD_MIN_DUTY="40")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("    minPwm: 102\n    startPwm: 102\n", block(r.stdout, "  - id: rad_pwm2"))
        self.assertIn("    minPwm: 77\n", block(r.stdout, "  - id: case_pwm3"))
        for duty in ["5", "101", "x"]:
            with self.subTest(duty=duty):
                self.assert_refused(self.run_print(CASE_FAN_RAD_MIN_DUTY=duty), "CASE_FAN_RAD_MIN_DUTY は 10..100")

    def test_cpu_curve_is_required(self):
        self.assert_refused(self.run_print(CASE_FAN_RAD_CPU_CURVE=""), "CASE_FAN_RAD_CPU_CURVE が空です")

    def test_gpu_curve_is_required(self):
        self.assert_refused(self.run_print(CASE_FAN_RAD_GPU_CURVE=""), "CASE_FAN_RAD_GPU_CURVE が空です")

    def test_overlap_with_case_fans_is_refused(self):
        self.assert_refused(self.run_print(CASE_FAN_CHANNELS="2 3"), "pwm2 が CASE_FAN_CHANNELS と CASE_FAN_RAD_CHANNELS の両方")

    def test_duplicate_channel_is_refused(self):
        self.assert_refused(self.run_print(CASE_FAN_RAD_CHANNELS="2 2"), "CASE_FAN_RAD_CHANNELS に pwm2 が2回")

    def test_missing_channel_or_rpm_is_refused(self):
        self.assert_refused(self.run_print(CASE_FAN_RAD_CHANNELS="7"), "pwm7")
        self.assert_refused(self.run_print(CASE_FAN_RAD_CHANNELS="2:9"), "fan9_input")
        self.assert_refused(self.run_print(CASE_FAN_RAD_CHANNELS="x"), "CASE_FAN_RAD_CHANNELS の値が読めません")

    def test_last_points_must_be_full(self):
        for key, curve in [("CASE_FAN_RAD_GPU_CURVE", "45:30 78:90"),
                           ("CASE_FAN_RAD_CPU_CURVE", "17:20 42:40 62:70 67:99"),
                           ("CASE_FAN_RAD_CPU_BACKUP_CURVE", "40:35 92:90")]:
            with self.subTest(key=key):
                r = self.run_print(**{**RAD_BACKUP, key: curve})
                self.assert_refused(r, f"{key} の最後の点は 100%")

    def test_gpu_curve_must_end_below_failsafe(self):
        self.assert_refused(self.run_print(CASE_FAN_RAD_GPU_CURVE="45:30 100:100"), "100℃ より低くすること")

    def test_curves_need_two_points(self):
        self.assert_refused(self.run_print(CASE_FAN_RAD_CPU_CURVE="67:100"), "CASE_FAN_RAD_CPU_CURVE は2点以上")

    def test_missing_temperature_source_is_refused(self):
        self.assert_refused(self.run_print(CASE_FAN_RAD_CPU_TEMP_CHANNEL="8"), "nct6799 に temp8_input がありません")
        self.assert_refused(self.run_print(CASE_FAN_RAD_CPU_HWMON=""), "CASE_FAN_RAD_CPU_HWMON が使えません")
        self.assert_refused(self.run_print(CASE_FAN_RAD_CPU_HWMON="nosuch"), "hwmon nosuch が1つに決まりません")
        self.assert_refused(self.run_print(**{**RAD_BACKUP, "CASE_FAN_RAD_CPU_BACKUP_TEMP_CHANNEL": "5"}),
                            "coretemp に temp5_input がありません")
        self.assert_refused(self.run_print(**{**RAD_BACKUP, "CASE_FAN_RAD_CPU_BACKUP_HWMON": "nosuch"}),
                            "CASE_FAN_RAD_CPU_BACKUP_HWMON の hwmon nosuch")

    def test_backup_source_without_curve_is_refused(self):
        r = self.run_print(**{**RAD_BACKUP, "CASE_FAN_RAD_CPU_BACKUP_CURVE": ""})
        self.assert_refused(r, "CASE_FAN_RAD_CPU_BACKUP_CURVE が空です")

    def test_weaker_than_bios_is_refused(self):
        # 65℃: BIOS 178、こちら 60% = 153
        r = self.run_print(CASE_FAN_RAD_CPU_CURVE="20:20 45:40 65:60 70:100")
        self.assert_refused(r, "ラジエーターの pwm2: CASE_FAN_RAD_CPU_CURVE が BIOS の曲線（temp9）より弱い所があります: "
                               "65℃ で BIOS 178、こちら 153（PWM 0..255）", "止めます")

    def test_weaker_between_bios_points_is_refused(self):
        # こちらの点 30℃（51）で、BIOS は 20:51 と 45:102 の間の 71.4。BIOS の点の温度だけでは見つからない弱さ
        r = self.run_print(CASE_FAN_RAD_CPU_CURVE="20:20 30:20 70:100")
        self.assert_refused(r, "30℃ で BIOS 71.4、こちら 51")

    def test_weaker_below_first_point_is_refused(self):
        # こちらの最初の点が BIOS より上の温度で低い値: 20℃ で BIOS 51、こちら（最初の点より下は最初の値）26
        r = self.run_print(CASE_FAN_RAD_CPU_CURVE="25:10 45:40 65:70 70:100")
        self.assert_refused(r, "20℃ で BIOS 51、こちら 26")

    def test_weaker_at_the_top_is_refused(self):
        # 最後の点が 100% でも、全開に届くのが BIOS より遅ければ止まる（70℃: BIOS 255、こちら 72℃ まで上がりきらない）
        r = self.run_print(CASE_FAN_RAD_CPU_CURVE="20:20 45:40 65:70 72:100")
        self.assert_refused(r, "70℃ で BIOS 255、こちら 233.3")

    def test_same_or_stronger_than_bios_passes(self):
        for curve in ["20:20 45:40 65:70 70:100", "17:20 42:40 62:70 67:100", "10:50 60:100"]:
            with self.subTest(curve=curve):
                r = self.run_print(CASE_FAN_RAD_CPU_CURVE=curve)
                self.assertEqual(r.returncode, 0, r.stderr)
                self.assertIn("より弱い所がない", r.stderr)

    def test_compared_even_when_fan2go_is_driving(self):
        # fan2go が操っている（enable=1）ときは、BIOS のモードを記録から取り、BIOS の曲線と比べる
        (self.fx.nct / "pwm2_enable").write_text("1\n")
        self.record.write_text("# 記録\nnct6799 3 5\nnct6799 2 5\n")
        r = self.run_print(CASE_FAN_RAD_CPU_CURVE="20:20 45:40 65:60 70:100")
        self.assert_refused(r, "65℃ で BIOS 178、こちら 153")
        r = self.run_print()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("より弱い所がない（BIOS のモード: SmartFan IV（pwm2_enable=5。いまは pwm2_enable=1 なので、"
                      f"{self.record} の記録）。", r.stderr)

    def test_bios_full_speed_is_refused(self):
        # BIOS が全開（enable=0）なら、どの温度でも 255。使われていない auto_point の曲線と比べて通してはいけない
        (self.fx.nct / "pwm2_enable").write_text("0\n")
        for env in [{}, {"CASE_FAN_RAD_CPU_HWMON": "coretemp", "CASE_FAN_RAD_CPU_TEMP_CHANNEL": "1"}]:
            with self.subTest(env=env):
                r = self.run_print(**env)
                self.assert_refused(r, "ラジエーターの pwm2: BIOS が全開にしている（pwm2_enable=0。いまの値）チャネルは、"
                                       "ラジエーターの組に入れられない", "SmartFan")
                self.assertNotIn("より弱い所がない", r.stderr)
                self.assertNotIn("自分で確かめる", r.stderr)

    def test_bios_full_speed_in_the_record_is_refused(self):
        (self.fx.nct / "pwm2_enable").write_text("1\n")
        self.record.write_text("nct6799 2 0\n")
        r = self.run_print()
        self.assert_refused(r, "BIOS が全開にしている（pwm2_enable=0。いまは pwm2_enable=1 なので、", "の記録）チャネルは")

    def test_bios_mode_other_than_smartfan4_is_refused(self):
        for mode in ["2", "3", "4", "7"]:
            with self.subTest(mode=mode):
                (self.fx.nct / "pwm2_enable").write_text(f"{mode}\n")
                r = self.run_print()
                self.assert_refused(r, f"BIOS の制御が SmartFan IV（5）でない（pwm2_enable={mode}。いまの値）ので、曲線を比べられない",
                                    "弱くならないと確かめられないので止める")

    def test_manual_without_record_is_refused(self):
        # いま 1 で記録がない（記録のファイルがない・その行がない・記録も 1）。--print-config では BIOS のモードが分からない
        (self.fx.nct / "pwm2_enable").write_text("1\n")
        for record in [None, "nct6799 3 5\nnct6798 2 5\n", "nct6799 2 1\n"]:
            with self.subTest(record=record):
                if record is None:
                    self.record.unlink(missing_ok=True)
                else:
                    self.record.write_text(record)
                r = self.run_print()
                self.assert_refused(r, "ラジエーターの pwm2: いまは手動（pwm2_enable=1）で、BIOS のモードの記録がない",
                                    "fan2go を止めて BIOS の制御に戻す（再起動）か、記録を確かめる")

    def test_fake_tree_does_not_read_the_real_record(self):
        # にせの木で CASE_FAN_TEST_CONFIG_DIR がなければ、本物の /etc/fan2go の記録は読まず、記録なしとして扱う
        (self.fx.nct / "pwm2_enable").write_text("1\n")
        for value in ["", None]:
            with self.subTest(value=value):
                env = {k: v for k, v in os.environ.items() if k != "CASE_FAN_TEST_CONFIG_DIR"}
                full = {**env, "UBUNTU_HOST": "no-such-host-for-tests", "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
                        "CASE_FAN_HWMON": "nct6799", "CASE_FAN_CPU_CURVE": "60:30 95:100", **RAD_OFF, **RAD_ON}
                if value is not None:
                    full["CASE_FAN_TEST_CONFIG_DIR"] = value
                r = subprocess.run([BASH, str(INSTALL), "--print-config"], env=full, capture_output=True, text=True)
                self.assert_refused(r, "BIOS のモードの記録がない")

    def test_record_override_is_refused_for_a_real_tree(self):
        # 本物の木（/sys の下・ないパス）では、記録の場所の差し替えを受け付けない
        for root in ["/sys/class/hwmon", str(self.fx.base / "no-such-dir")]:
            with self.subTest(root=root):
                r = self.run_print(CASE_FAN_HWMON_ROOT=root)
                self.assert_refused(r, "CASE_FAN_TEST_CONFIG_DIR は、にせの hwmon の木")

    def write_bios_curve(self, points):
        for f in self.fx.nct.glob("pwm2_auto_point*"):
            f.unlink()
        for m, (t, v) in enumerate(points, start=1):
            (self.fx.nct / f"pwm2_auto_point{m}_temp").write_text(f"{t * 1000}\n")
            (self.fx.nct / f"pwm2_auto_point{m}_pwm").write_text(f"{v}\n")

    def test_bios_step_is_compared_on_the_high_side(self):
        # 62℃ に点が 2 つ（178 → 255 の段差）。63℃ では BIOS 255、こちら 194.2。段差の温度で高いほうと比べて止まる
        self.write_bios_curve([(20, 51), (45, 102), (62, 178), (62, 255), (125, 255)])
        r = self.run_print()
        self.assert_refused(r, "より弱い所があります: 62℃ で BIOS 255、こちら 179（PWM 0..255）")

    def test_bios_step_at_the_first_point_is_compared_on_the_high_side(self):
        # 最初の温度に点が 2 つ: 最初の点より下も、高いほう（102）と比べる
        self.write_bios_curve([(20, 51), (20, 102), (45, 102), (65, 178), (70, 255)])
        r = self.run_print()
        self.assert_refused(r, "17℃ で BIOS 102、こちら 51")

    def test_stronger_than_bios_step_passes(self):
        self.write_bios_curve([(20, 51), (45, 102), (62, 178), (62, 255), (125, 255)])
        r = self.run_print(CASE_FAN_RAD_CPU_CURVE="17:20 42:40 60:100")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("BIOS の曲線（temp9。5 点）より弱い所がない", r.stderr)
        self.assertIn("7 か所で比べた", r.stderr)

    def test_duplicate_bios_point_with_the_same_value_is_harmless(self):
        self.write_bios_curve([(20, 51), (45, 102), (65, 178), (70, 255), (125, 255), (125, 255)])
        r = self.run_print()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("BIOS の曲線（temp9。6 点）より弱い所がない", r.stderr)

    def assert_warned(self, r, message):
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(message, r.stderr)
        self.assertIn("自分で確かめる", r.stderr)
        self.assertTrue(r.stdout.startswith("# install-case-fan-control-ubuntu.sh"), r.stdout[:200])
        self.assertNotIn("比べられません", r.stdout)
        self.assertIn("  - id: rad_pwm2\n", r.stdout)

    def test_different_bios_source_warns_and_proceeds(self):
        (self.fx.nct / "pwm2_temp_sel").write_text("3\n")
        # 源が違うので、BIOS より弱い曲線でも止めない
        r = self.run_print(CASE_FAN_RAD_CPU_CURVE="20:20 45:40 65:60 70:100")
        self.assert_warned(r, "BIOS の温度の源は temp3（pwm2_temp_sel）で、CASE_FAN_RAD_CPU_TEMP_CHANNEL（temp9）と違うので")

    def test_different_hwmon_warns_and_proceeds(self):
        r = self.run_print(CASE_FAN_RAD_CPU_HWMON="coretemp", CASE_FAN_RAD_CPU_TEMP_CHANNEL="1")
        self.assert_warned(r, "CPU の温度の源（coretemp の temp1）が BIOS の側の hwmon（nct6799）と違うので")

    def test_missing_temp_sel_warns_and_proceeds(self):
        (self.fx.nct / "pwm2_temp_sel").unlink()
        self.assert_warned(self.run_print(), "pwm2_temp_sel が読めず")

    def test_missing_bios_curve_warns_and_proceeds(self):
        for f in self.fx.nct.glob("pwm2_auto_point*"):
            f.unlink()
        self.assert_warned(self.run_print(), "BIOS の曲線（pwm2_auto_point*_temp・_pwm）がないので")

    def test_unreadable_bios_curve_is_refused(self):
        (self.fx.nct / "pwm2_auto_point3_pwm").write_text("garbage\n")
        self.assert_refused(self.run_print(), "BIOS の曲線の点 3", "止めます")
        (self.fx.nct / "pwm2_auto_point3_pwm").write_text("178\n")
        (self.fx.nct / "pwm2_auto_point3_temp").unlink()
        self.assert_refused(self.run_print(), "BIOS の曲線の点 3")

    def test_bios_curve_with_many_points_is_read_in_order(self):
        # 点の番号が 10 以上でも、番号の順に読む（glob の文字の順では 10 が 2 より前に来る）
        for f in self.fx.nct.glob("pwm2_auto_point*"):
            f.unlink()
        for m in range(1, 11):
            (self.fx.nct / f"pwm2_auto_point{m}_temp").write_text(f"{20000 + 5000 * m}\n")
            (self.fx.nct / f"pwm2_auto_point{m}_pwm").write_text(f"{min(255, 25 * m)}\n")
        r = self.run_print(CASE_FAN_RAD_CPU_CURVE="20:20 70:100")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("10 点", r.stderr)


@unittest.skipUnless(sys.platform.startswith("linux"), "--probe は Linux 専用")
class IdentifyHwmonTests(unittest.TestCase):
    """--identify が操る hwmon の選び方を、--probe の「--identify が使う hwmon」の行で確かめる（root 不要）"""

    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def identify_line(self, **env):
        full = {
            **os.environ,
            # 流す機械の fan2go・nvidia-smi・カーネルのログに依らないように
            "PATH": make_fake_tools(self.fx.base / "tools"),
            "UBUNTU_HOST": "no-such-host-for-tests",
            "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
            "CASE_FAN_HWMON": "",
            **env,
        }
        r = subprocess.run([BASH, str(INSTALL), "--probe"], env=full,
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = [l for l in r.stdout.splitlines() if "--identify が使う hwmon:" in l]
        self.assertEqual(len(lines), 1, r.stdout)
        return lines[0]

    def test_empty_hwmon_picks_the_only_superio_with_pwm(self):
        # pwm のない Super I/O は数えない
        make_hwmon(self.fx.hwmon, 2, "nct6686", {"fan1_input": 500})
        line = self.identify_line()
        self.assertIn("nct6799（hwmon0。CASE_FAN_HWMON が空なので", line)

    def test_empty_hwmon_without_superio_pwm_is_refused(self):
        (self.fx.nct / "pwm1").unlink()
        (self.fx.nct / "pwm2").unlink()
        (self.fx.nct / "pwm3").unlink()
        line = self.identify_line()
        self.assertIn("決まらない", line)
        self.assertIn("hwmon0: nct6799（pwm なし）", line)
        self.assertIn("--probe --load-module", line)

    def test_empty_hwmon_with_two_superio_is_refused(self):
        make_hwmon(self.fx.hwmon, 2, "nct6798", {"pwm1": 1, "pwm1_enable": 5, "fan1_input": 1})
        line = self.identify_line()
        self.assertIn("決まらない", line)
        self.assertIn("2 個", line)
        self.assertIn("hwmon0: nct6799", line)
        self.assertIn("hwmon2: nct6798", line)

    def test_written_hwmon_is_used_as_is(self):
        # 書いてあれば Super I/O から選ばない（もう 1 つあっても決まる）
        make_hwmon(self.fx.hwmon, 2, "nct6798", {"pwm1": 1, "pwm1_enable": 5, "fan1_input": 1})
        line = self.identify_line(CASE_FAN_HWMON="nct6799")
        self.assertIn("nct6799（hwmon0。hosts/ubuntu/no-such-host-for-tests.env の CASE_FAN_HWMON）", line)
        line = self.identify_line(CASE_FAN_HWMON="nct6797")
        self.assertIn("決まらない（hwmon nct6797 が1つに決まりません）", line)


# にせの systemctl: fan2go の状態は試験が FAKE_FAN2GO_STATE で決める（既定は inactive）。流す機械の fan2go に依らないように
FAKE_SYSTEMCTL = """#!/bin/sh
state="${FAKE_FAN2GO_STATE:-inactive}"
if [ "$1" = is-active ]; then
  shift
  quiet=false
  [ "$1" = --quiet ] && { quiet=true; shift; }
  [ "$1" = fan2go ] || [ "$1" = fan2go.service ] || state=inactive
  $quiet || echo "$state"
  [ "$state" = active ]
  exit $?
fi
echo "fake systemctl: $*" >&2
exit 1
"""


def make_fake_tools(directory):
    """流す機械の状態に依らないように、--probe・--identify が呼ぶ道具のにせものを置き、PATH の先頭に足す値を返す。
    systemctl（FAKE_FAN2GO_STATE）、nvidia-smi（1 枚、40℃）、journalctl（カーネルのログは空）"""
    directory.mkdir(exist_ok=True)
    tools = {
        "systemctl": FAKE_SYSTEMCTL,
        "nvidia-smi": "#!/bin/sh\necho '0, 00000000:01:00.0, Fake GPU, 40, 30 %, 20.00 W'\n",
        "journalctl": "#!/bin/sh\nexit 0\n",
    }
    for name, text in tools.items():
        (directory / name).write_text(text)
        (directory / name).chmod(0o755)
    return f"{directory}:{os.environ.get('PATH', '')}"


@unittest.skipUnless(sys.platform.startswith("linux"), "--identify は Linux 専用")
class IdentifyTests(unittest.TestCase):
    """--identify（全開・--stop）を、にせの hwmon の木に対して sudo なしで動かし、元に戻ることを確かめる"""

    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        nct = self.fx.nct
        # pwm2: ふつうのファン（BIOS の曲線が 255 でない点を持つ）。pwm3: ポンプと見られる（全点 255）。pwm1: 曲線のファイルなし。
        # pwm4: 曲線はふつうだが、BIOS が全開にしている（enable=0）
        for m, v in enumerate([60, 90, 120, 200, 255], start=1):
            (nct / f"pwm2_auto_point{m}_pwm").write_text(f"{v}\n")
            (nct / f"pwm3_auto_point{m}_pwm").write_text("255\n")
            (nct / f"pwm4_auto_point{m}_pwm").write_text(f"{v}\n")
        (nct / "pwm3").write_text("255\n")
        (nct / "pwm4").write_text("200\n")
        (nct / "pwm4_enable").write_text("0\n")
        self.path = make_fake_tools(self.fx.base / "tools")

    def env(self, **env):
        if os.geteuid() == 0:
            self.skipTest("root では流さない（sudo なしの入口を試す）")
        return {
            **os.environ,
            "PATH": self.path,
            "FAKE_FAN2GO_STATE": "inactive",
            "UBUNTU_HOST": "no-such-host-for-tests",
            "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
            "CASE_FAN_HWMON": "nct6799",
            "CASE_FAN_TEST_IDENTIFY_SECONDS": "1",
            **env,
        }

    def run_identify(self, *args, **env):
        return subprocess.run([BASH, str(INSTALL), "--identify", *args], env=self.env(**env),
                              capture_output=True, text=True, timeout=60)

    def state(self, ch):
        return ((self.fx.nct / f"pwm{ch}_enable").read_text().strip(),
                (self.fx.nct / f"pwm{ch}").read_text().strip())

    def start_and_wait_first_tick(self, *args, seconds="60"):
        """長く動かし（既定 60 秒）、最初の「1s:」の行が出たところで返す（そのとき pwm は変えたまま）"""
        p = subprocess.Popen([BASH, str(INSTALL), "--identify", *args],
                             env=self.env(CASE_FAN_TEST_IDENTIFY_SECONDS=seconds),
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: p.poll() is None and p.kill())
        assert p.stdout is not None and p.stderr is not None
        lines = []
        for line in p.stdout:
            lines.append(line)
            if line.strip().startswith("1s:"):
                return p, lines
        p.wait(timeout=10)
        self.fail("1s: の行が出ませんでした: " + "".join(lines) + p.stderr.read())

    def test_running_fan2go_is_refused(self):
        # fan2go が動いていれば、全開でも --stop でも何も変えずに止まる
        for args, ch, before in [(["2"], 2, ("5", "90")), (["2", "--stop"], 2, ("5", "90")),
                                 (["3", "--stop", "--allow-pump"], 3, ("5", "255"))]:
            with self.subTest(args=args):
                r = self.run_identify(*args, FAKE_FAN2GO_STATE="active")
                self.assertNotEqual(r.returncode, 0)
                self.assertIn("fan2go が動いています", r.stderr)
                self.assertNotIn("秒だけ", r.stdout)
                self.assertEqual(self.state(ch), before)

    def test_full_speed_restores(self):
        # --stop なしは今までどおり 255 にして戻す
        r = self.run_identify("2")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("全開にします（元: enable=5 pwm=90）", r.stdout)
        self.assertIn("1s: fan1=1100 fan2=800 fan3=0 fan4=600", r.stdout)
        self.assertIn("pwm2 を元（enable=5 pwm=90）へ戻しました", r.stdout)
        self.assertEqual(self.state(2), ("5", "90"))

    def test_full_speed_sets_255_while_running(self):
        p, _ = self.start_and_wait_first_tick("2")
        self.assertEqual(self.state(2), ("1", "255"))
        p.send_signal(signal.SIGTERM)
        p.communicate(timeout=10)
        self.assertEqual(self.state(2), ("5", "90"))

    def test_full_speed_does_not_check_for_pump(self):
        r = self.run_identify("3")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("ポンプ", r.stdout + r.stderr)
        self.assertEqual(self.state(3), ("5", "255"))

    def test_stop_sets_zero_while_running(self):
        p, lines = self.start_and_wait_first_tick("2", "--stop")
        self.assertEqual(self.state(2), ("1", "0"))
        out = "".join(lines)
        self.assertIn("60 秒だけ止めます（pwm=0。元: enable=5 pwm=90）", out)
        self.assertIn("止まらなければ、回転が下がるかを見る", out)
        self.assertIn("目で見て止まるかを見る", out)
        self.assertIn("1s: fan1=1100 fan2=800 fan3=0 fan4=600", out)
        p.send_signal(signal.SIGTERM)
        p.communicate(timeout=10)
        self.assertEqual(self.state(2), ("5", "90"))

    def test_stop_runs_to_the_end_and_restores(self):
        r = self.run_identify("2", "--stop", CASE_FAN_TEST_IDENTIFY_SECONDS="2")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(" 2s: fan1=1100", r.stdout)
        self.assertIn("pwm2 を元（enable=5 pwm=90）へ戻しました", r.stdout)
        self.assertEqual(self.state(2), ("5", "90"))
        # ほかのチャネルには触れない
        self.assertEqual(self.state(1), ("5", "120"))
        self.assertEqual(self.state(3), ("5", "255"))

    def test_signals_restore(self):
        for sig, code in [(signal.SIGINT, 130), (signal.SIGTERM, 143), (signal.SIGHUP, 129)]:
            with self.subTest(sig=sig.name):
                p, _ = self.start_and_wait_first_tick("2", "--stop")
                self.assertEqual(self.state(2), ("1", "0"))
                started = time.monotonic()
                # Ctrl+C の端末とちがい、bash にだけ送る（前面の sleep は INT を受けない）
                p.send_signal(sig)
                out, err = p.communicate(timeout=10)
                self.assertLess(time.monotonic() - started, 5)
                self.assertEqual(p.returncode, code, err)
                self.assertIn("pwm2 を元（enable=5 pwm=90）へ戻しました", out)
                self.assertEqual(self.state(2), ("5", "90"))

    def test_failure_midway_restores(self):
        # pwm に書けない（途中の失敗）。enable は 1 にしたあとなので、EXIT の trap で戻ること
        (self.fx.nct / "pwm2").chmod(0o444)
        r = self.run_identify("2", "--stop")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.state(2), ("5", "90"))

    def test_failed_restore_is_reported(self):
        # 止めている・全開にしている途中で pwm か enable のファイルを書けなくする。戻しが失敗したら、
        # 「戻しました」を出さず、何が戻っていないかと手で戻すコマンドを出し、0 でない終了コードで終わる
        for before in [("1", "90"), ("5", "90")]:
            for args in [["2", "--stop"], ["2"]]:
                for broken in ["pwm2", "pwm2_enable"]:
                    with self.subTest(before=before, args=args, broken=broken):
                        (self.fx.nct / "pwm2").chmod(0o644)
                        (self.fx.nct / "pwm2_enable").chmod(0o644)
                        (self.fx.nct / "pwm2_enable").write_text(before[0] + "\n")
                        (self.fx.nct / "pwm2").write_text(before[1] + "\n")
                        p, _ = self.start_and_wait_first_tick(*args, seconds="2")
                        (self.fx.nct / broken).chmod(0o444)
                        out, err = p.communicate(timeout=10)
                        self.assertEqual(p.returncode, 1, out + err)
                        self.assertNotIn("戻しました", out)
                        self.assertIn(f"pwm2 を元へ戻せませんでした（戻したい値: enable={before[0]} pwm={before[1]}。いま: enable=", err)
                        self.assertIn(f"{broken} への書き込みが失敗", err)
                        self.assertIn(f"sudo sh -c 'echo {before[1]} > {self.fx.nct}/pwm2; "
                                      f"echo {before[0]} > {self.fx.nct}/pwm2_enable'", err)
                        self.assertIn("再起動でも BIOS の制御に戻る", err)
        (self.fx.nct / "pwm2").chmod(0o644)
        (self.fx.nct / "pwm2_enable").chmod(0o644)

    def test_failed_restore_keeps_the_signal_exit_code(self):
        (self.fx.nct / "pwm2_enable").write_text("1\n")
        p, _ = self.start_and_wait_first_tick("2", "--stop")
        (self.fx.nct / "pwm2").chmod(0o444)
        p.send_signal(signal.SIGINT)
        out, err = p.communicate(timeout=10)
        (self.fx.nct / "pwm2").chmod(0o644)
        self.assertEqual(p.returncode, 130, out + err)
        self.assertNotIn("戻しました", out)
        self.assertIn("pwm2 を元へ戻せませんでした（戻したい値: enable=1 pwm=90。いま: enable=1 pwm=0。", err)

    def test_manual_channel_restores_both_values(self):
        # 元が手動（enable=1 / pwm=90）でも、書き戻しが通れば「戻しました」で 0
        (self.fx.nct / "pwm2_enable").write_text("1\n")
        r = self.run_identify("2", "--stop")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("pwm2 を元（enable=1 pwm=90）へ戻しました", r.stdout)
        self.assertEqual(self.state(2), ("1", "90"))

    def test_pump_is_refused_without_allow(self):
        r = self.run_identify("3", "--stop")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("pwm3: ポンプと見られる（BIOS の曲線 pwm3_auto_point*_pwm = 255 255 255 255 255）", r.stderr)
        self.assertIn("CPU が冷えなくなる", r.stderr)
        self.assertNotIn("enable=0", r.stderr)
        self.assertIn("--identify 3 --stop --allow-pump", r.stderr)
        self.assertNotIn("止めます（pwm=0", r.stdout)
        self.assertEqual(self.state(3), ("5", "255"))

    def test_pump_with_allow_is_stopped_and_restored(self):
        p, lines = self.start_and_wait_first_tick("3", "--stop", "--allow-pump")
        self.assertEqual(self.state(3), ("1", "0"))
        self.assertIn("--allow-pump があるので止めます", "".join(lines))
        p.send_signal(signal.SIGINT)
        p.communicate(timeout=10)
        self.assertEqual(self.state(3), ("5", "255"))

    def test_unreadable_curve_is_refused(self):
        (self.fx.nct / "pwm2_auto_point3_pwm").write_text("garbage\n")
        r = self.run_identify("2", "--stop")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("ポンプかどうか判定できない", r.stderr)
        self.assertEqual(self.state(2), ("5", "90"))

    def test_bios_full_speed_is_refused_without_allow(self):
        r = self.run_identify("4", "--stop")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("pwm4: BIOS が全開にしている（enable=0）。ポンプなど、止めてはいけないものの見込み", r.stderr)
        self.assertIn("--identify 4 --stop --allow-pump", r.stderr)
        self.assertNotIn("止めます（pwm=0", r.stdout)
        self.assertEqual(self.state(4), ("0", "200"))

    def test_bios_full_speed_with_allow_is_stopped_and_restored(self):
        p, lines = self.start_and_wait_first_tick("4", "--stop", "--allow-pump")
        self.assertEqual(self.state(4), ("1", "0"))
        self.assertIn("--allow-pump があるので止めます", "".join(lines))
        p.send_signal(signal.SIGTERM)
        out, _ = p.communicate(timeout=10)
        self.assertIn("pwm4 を元（enable=0 pwm=200）へ戻しました", out)
        self.assertEqual(self.state(4), ("0", "200"))

    def test_bios_full_speed_and_pump_curve_both_reported(self):
        (self.fx.nct / "pwm3_enable").write_text("0\n")
        r = self.run_identify("3", "--stop")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("ポンプと見られる", r.stderr)
        self.assertIn("BIOS が全開にしている（enable=0）", r.stderr)
        self.assertEqual(self.state(3), ("0", "255"))

    def test_full_speed_mode_ignores_bios_full_speed(self):
        # --stop なしには効かせない
        r = self.run_identify("4")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("ポンプ", r.stdout + r.stderr)
        self.assertEqual(self.state(4), ("0", "200"))

    def test_channel_without_curve_files_is_not_refused(self):
        r = self.run_identify("1", "--stop")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("pwm1_auto_point*_pwm がありません", r.stdout)
        self.assertIn("判定できない", r.stdout)
        self.assertIn("止めます（pwm=0。元: enable=5 pwm=120）", r.stdout)
        self.assertEqual(self.state(1), ("5", "120"))

    def test_bad_arguments(self):
        for args in [["2", "--allow-pump"], ["2", "--stop", "--stop"], ["2", "--allow-pump", "--stop"],
                     ["2", "--stop", "--allow-pump", "x"], ["--stop", "2"]]:
            with self.subTest(args=args):
                r = self.run_identify(*args)
                self.assertEqual(r.returncode, 2)
                self.assertEqual(self.state(2), ("5", "90"))

    def test_real_sysfs_is_not_entered_without_sudo(self):
        # CASE_FAN_HWMON_ROOT が /sys の下・ないパスなら、試験の入口にならない（sudo で起動し直そうとする）。
        # 本物の sudo には届かないように、PATH はにせの sudo と、起動し直す前に使う道具だけにする
        fake_bin = self.fx.base / "bin"
        fake_bin.mkdir()
        log = self.fx.base / "sudo.log"
        (fake_bin / "sudo").write_text(f"#!/bin/sh\necho \"$@\" > '{log}'\nexit 7\n")
        (fake_bin / "sudo").chmod(0o755)
        for tool in ["realpath", "dirname", "uname"]:
            found = shutil.which(tool)
            if found is None:
                self.skipTest(f"{tool} がありません")
            (fake_bin / tool).symlink_to(found)
        bash = shutil.which(BASH)
        if bash is None:
            self.skipTest(f"{BASH} がありません")
        for root in ["/sys/class/hwmon", "/sys/class/hwmon/", str(self.fx.base / "no-such-dir")]:
            with self.subTest(root=root):
                if log.exists():
                    log.unlink()
                r = subprocess.run([bash, str(INSTALL), "--identify", "2", "--stop"],
                                   env=self.env(CASE_FAN_HWMON_ROOT=root, PATH=str(fake_bin)),
                                   capture_output=True, text=True, timeout=60)
                self.assertEqual(r.returncode, 7, r.stderr)
                self.assertIn("--identify 2 --stop", log.read_text())


@unittest.skipUnless(sys.platform.startswith("linux"), "--probe は Linux 専用")
class ProbePumpLineTests(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def probe(self):
        r = subprocess.run([BASH, str(INSTALL), "--probe"], env={
            **os.environ,
            # 流す機械の fan2go・nvidia-smi・カーネルのログに依らないように
            "PATH": make_fake_tools(self.fx.base / "tools"),
            "UBUNTU_HOST": "no-such-host-for-tests",
            "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
            "CASE_FAN_HWMON": "",
        }, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout

    LINE = "--identify --stop が断るチャネル（ポンプなど、止めてはいけないものと見られる。止めるなら --allow-pump）: "

    def test_pump_line(self):
        for m in range(1, 6):
            (self.fx.nct / f"pwm3_auto_point{m}_pwm").write_text("255\n")
            (self.fx.nct / f"pwm2_auto_point{m}_pwm").write_text(f"{50 * m}\n")
        out = self.probe()
        self.assertIn(self.LINE + "pwm3（BIOS の曲線が全点 255）\n", out)
        self.assertIn("判定できないチャネル（--stop は注意を出して進める）: pwm1\n", out)

    def test_pump_line_with_bios_full_speed(self):
        # chibihamuntu と同じ形: 全点 255 のチャネルと、enable=0 のチャネル。両方に当たれば両方の理由
        for m in range(1, 6):
            (self.fx.nct / f"pwm3_auto_point{m}_pwm").write_text("255\n")
            (self.fx.nct / f"pwm2_auto_point{m}_pwm").write_text(f"{50 * m}\n")
            (self.fx.nct / f"pwm1_auto_point{m}_pwm").write_text("255\n")
        (self.fx.nct / "pwm2_enable").write_text("0\n")
        (self.fx.nct / "pwm1_enable").write_text("0\n")
        out = self.probe()
        self.assertIn(self.LINE + "pwm1（BIOS の曲線が全点 255、BIOS が全開 enable=0） pwm2（BIOS が全開 enable=0） "
                      "pwm3（BIOS の曲線が全点 255）\n", out)
        self.assertNotIn("判定できないチャネル", out)

    def test_no_pump(self):
        out = self.probe()
        self.assertIn(self.LINE + "なし\n", out)
        self.assertIn("判定できないチャネル（--stop は注意を出して進める）: pwm1 pwm2 pwm3\n", out)


@unittest.skipUnless(sys.platform.startswith("linux"), "--probe は Linux 専用")
class ProbeTests(unittest.TestCase):
    """--probe が nvidia-smi の失敗で落ちないこと、ラジエーターの組の BIOS の曲線との比べの行"""

    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        self.tools = self.fx.base / "tools"
        self.path = make_fake_tools(self.tools)

    def probe(self, **env):
        r = subprocess.run([BASH, str(INSTALL), "--probe"], env={
            **os.environ,
            "PATH": self.path,
            "UBUNTU_HOST": "no-such-host-for-tests",
            "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
            "CASE_FAN_HWMON": "",
            **RAD_OFF,
            **env,
        }, capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        return r.stdout

    def test_failing_nvidia_smi_does_not_stop_probe(self):
        (self.tools / "nvidia-smi").write_text(
            "#!/bin/sh\necho 'Failed to initialize NVML: Driver/library version mismatch'\nexit 18\n")
        out = self.probe()
        self.assertIn("  Failed to initialize NVML: Driver/library version mismatch\n", out)
        self.assertIn("nvidia-smi が失敗しました（終了コード 18。", out)
        self.assertIn("期待する枚数（NVIDIA_EXPECTED_GPUS）", out)
        self.assertIn("== 見立て", out)
        self.assertIn("--identify が使う hwmon:", out)

    def test_working_nvidia_smi(self):
        out = self.probe()
        self.assertIn("  0, 00000000:01:00.0, Fake GPU, 40, 30 %, 20.00 W\n", out)
        self.assertNotIn("nvidia-smi が失敗しました", out)

    def test_no_radiator_line_without_group(self):
        self.assertNotIn("ラジエーター", self.probe())

    def test_radiator_bios_comparison_lines(self):
        add_radiator(self.fx)
        env = {**RAD_ON, "CASE_FAN_HWMON": "nct6799"}
        out = self.probe(**env)
        self.assertIn("ラジエーターの pwm2: CASE_FAN_RAD_CPU_CURVE は、BIOS の曲線（temp9。5 点）より弱い所がない", out)
        self.assertIn("CASE_FAN_RAD_CHANNELS=2", out)
        out = self.probe(**{**env, "CASE_FAN_RAD_CPU_CURVE": "20:20 45:40 65:60 70:100"})
        self.assertIn("ラジエーターの pwm2: CASE_FAN_RAD_CPU_CURVE が BIOS の曲線（temp9）より弱い所があります: "
                      "65℃ で BIOS 178、こちら 153（PWM 0..255）。入れるスクリプトは止まる", out)
        out = self.probe(**{**env, "CASE_FAN_RAD_CPU_TEMP_CHANNEL": "3"})
        self.assertIn("ラジエーターの pwm2: BIOS の温度の源は temp9", out)
        out = self.probe(**{**env, "CASE_FAN_RAD_CPU_CURVE": ""})
        self.assertIn("CASE_FAN_RAD_CPU_CURVE が空か読めない", out)

    def test_radiator_bios_mode_lines(self):
        # 見立ての行も、入れるときと同じく BIOS のモードを見る（にせの木なので記録は CASE_FAN_TEST_CONFIG_DIR から）
        add_radiator(self.fx)
        etc = self.fx.base / "etc-fan2go"
        etc.mkdir()
        env = {**RAD_ON, "CASE_FAN_HWMON": "nct6799", "CASE_FAN_TEST_CONFIG_DIR": str(etc)}
        out = self.probe(**env)
        self.assertIn("より弱い所がない（BIOS のモード: SmartFan IV（pwm2_enable=5。いまの値）。", out)
        (self.fx.nct / "pwm2_enable").write_text("0\n")
        out = self.probe(**env)
        self.assertIn("ラジエーターの pwm2: BIOS が全開にしている（pwm2_enable=0。いまの値）チャネルは、ラジエーターの組に入れられない", out)
        self.assertIn("入れるスクリプトは止まる", out)
        (self.fx.nct / "pwm2_enable").write_text("1\n")
        out = self.probe(**env)
        self.assertIn("ラジエーターの pwm2: いまは手動（pwm2_enable=1）で、BIOS のモードの記録がない", out)
        (etc / "case-fan-restore.conf").write_text("nct6799 2 5\n")
        out = self.probe(**env)
        self.assertIn("より弱い所がない（BIOS のモード: SmartFan IV（pwm2_enable=5。いまは pwm2_enable=1 なので、", out)


# にせの fan2go: viper と同じく、-c のパスの拡張子が .yaml / .yml でなければ読めずに落ちる
FAKE_FAN2GO = """#!/bin/sh
printf '%s\\n' "$*" >> "$FAKE_LOG"
[ "$1" = -c ] || exit 3
case "$2" in
  *.yaml|*.yml) ;;
  *) echo "FATAL: Error reading config file, Unsupported Config Type" >&2; exit 1 ;;
esac
[ "$(stat -c %a "$2")" = 644 ] || { echo "bad mode" >&2; exit 4; }
grep -q '^fans:' "$2" || exit 5
# 本物（internal/configuration/validation.go）と同じく、function の曲線は 2 本以上を要る
awk '/^      curves:$/ { n = 0; inside = 1; next }
     inside && /^        - / { n++; next }
     inside { if (n < 2) bad = 1; inside = 0 }
     END { if (inside && n < 2) bad = 1; exit bad }' "$2" ||
  { echo "function curves must reference at least 2 other curves" >&2; exit 6; }
exit "${FAKE_EXIT:-0}"
"""


class WriteConfigTests(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        self.etc = self.fx.base / "etc-fan2go"
        self.etc.mkdir()
        self.fan2go = self.fx.base / "fan2go"
        self.fan2go.write_text(FAKE_FAN2GO)
        self.fan2go.chmod(0o755)
        self.log = self.fx.base / "fan2go.log"

    def run_write(self, **env):
        full = {
            **os.environ,
            "UBUNTU_HOST": "no-such-host-for-tests",
            "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
            "CASE_FAN_HWMON": "nct6799",
            "CASE_FAN_CHANNELS": "2 3",
            "CASE_FAN_TEST_CONFIG_DIR": str(self.etc),
            "CASE_FAN_TEST_FAN2GO": str(self.fan2go),
            "FAKE_LOG": str(self.log),
            **RAD_OFF,
            **env,
        }
        return subprocess.run([BASH, str(INSTALL), "--test-write-config"], env=full,
                              capture_output=True, text=True)

    def test_validates_a_yaml_named_file_then_replaces(self):
        r = self.run_write()
        self.assertEqual(r.returncode, 0, r.stderr)
        args = self.log.read_text().split()
        self.assertEqual(args[:2], ["-c", str(self.etc / "fan2go.new.yaml")])
        self.assertIn("validate", args)
        self.assertIn("platform: nct6799", (self.etc / "fan2go.yaml").read_text())
        self.assertEqual(oct((self.etc / "fan2go.yaml").stat().st_mode & 0o777), "0o644")
        self.assertEqual(sorted(p.name for p in self.etc.iterdir()), ["fan2go.yaml"])

    def test_validates_with_cpu_curve(self):
        r = self.run_write(CASE_FAN_CPU_CURVE="60:30 95:100")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("- cpu_curve", (self.etc / "fan2go.yaml").read_text())

    def test_validates_with_radiator_group(self):
        add_radiator(self.fx)
        for extra in [{}, RAD_BACKUP]:
            with self.subTest(backup=bool(extra)):
                r = self.run_write(**RAD_ON, **extra)
                self.assertEqual(r.returncode, 0, r.stderr)
                y = (self.etc / "fan2go.yaml").read_text()
                self.assertIn("  - id: rad_pwm2\n", y)
                self.assertIn("  - id: rad_fans\n", y)
                self.assertEqual(sorted(p.name for p in self.etc.iterdir()), ["fan2go.yaml"])

    @unittest.skipUnless(os.environ.get("FAN2GO_FOR_TESTS"), "本物の fan2go は FAN2GO_FOR_TESTS で渡したときだけ使う")
    def test_real_fan2go_accepts_radiator_group(self):
        # 本物の fan2go（0.15.0）の config validate に、組あり（保険あり・なし）と組なしの設定を通す。
        # 本物は設定のファイルの持ち主が root でないと断る（「owner is not root」）ので、root で流したときだけ
        if os.geteuid() != 0:
            self.skipTest("本物の fan2go は持ち主が root でない設定を断るので、root のときだけ流す")
        add_radiator(self.fx)
        real = os.environ.get("FAN2GO_FOR_TESTS", "")
        for name, extra in [("off", {"CASE_FAN_RAD_CHANNELS": ""}), ("on", RAD_ON), ("backup", {**RAD_ON, **RAD_BACKUP})]:
            with self.subTest(name=name):
                r = self.run_write(CASE_FAN_TEST_FAN2GO=real, CASE_FAN_CPU_CURVE="60:30 95:100", **extra)
                self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_rejected_config_keeps_the_old_one_and_leaves_nothing(self):
        (self.etc / "fan2go.yaml").write_text("old\n")
        r = self.run_write(FAKE_EXIT="1")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("受け付けませんでした", r.stderr)
        self.assertEqual((self.etc / "fan2go.yaml").read_text(), "old\n")
        self.assertEqual(sorted(p.name for p in self.etc.iterdir()), ["fan2go.yaml"])

    def test_leftover_from_an_earlier_run_is_replaced(self):
        left = self.etc / "fan2go.new.yaml"
        left.write_text("garbage\n")
        left.chmod(0o600)
        r = self.run_write()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(left.exists())
        self.assertIn("fans:", (self.etc / "fan2go.yaml").read_text())


class GpuTempTests(unittest.TestCase):
    def run_sensor(self, output, exit_code=0, expected="2", sleep=0, ignore_term=False):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            smi = base / "nvidia-smi"
            smi.write_text(
                "#!/bin/sh\n"
                + ("trap '' TERM\n" if ignore_term else "")
                + f"sleep {sleep}\n"
                f"printf '%s' '{output}'\n"
                f"exit {exit_code}\n"
            )
            smi.chmod(0o755)
            status = base / "status"
            started = time.monotonic()
            r = subprocess.run(
                [BASH, str(GPU_TEMP), expected, "100"],
                env={**os.environ, "CASE_FAN_NVIDIA_SMI": str(smi), "CASE_FAN_STATUS_FILE": str(status)},
                capture_output=True, text=True, timeout=10,
            )
            self.elapsed = time.monotonic() - started
            return r, status.read_text() if status.exists() else ""

    def test_maximum_of_two_gpus_in_millidegrees(self):
        r, status = self.run_sensor("33\n61\n")
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "61000\n")
        self.assertIn("ok 61 gpus=2", status)

    def test_smi_failure_is_full_speed(self):
        r, status = self.run_sensor("Unable to determine the device handle", exit_code=15)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "100000\n")
        self.assertIn("failsafe", status)

    def test_missing_gpu_is_full_speed(self):
        r, _ = self.run_sensor("40\n")
        self.assertEqual(r.stdout, "100000\n")

    def test_count_not_checked_when_zero(self):
        r, _ = self.run_sensor("40\n", expected="0")
        self.assertEqual(r.stdout, "40000\n")

    def test_garbage_is_full_speed(self):
        r, _ = self.run_sensor("40\n[N/A]\n")
        self.assertEqual(r.stdout, "100000\n")

    def test_hang_is_full_speed(self):
        r, _ = self.run_sensor("40\n41\n", sleep=5)
        self.assertEqual(r.stdout, "100000\n")

    def test_hang_ignoring_term_ends_before_fan2go_timeout(self):
        # fan2go 0.15.0 の cmd センサーの時間切れは 2 秒。超えると読み取りが捨てられ、全開に倒れない
        r, status = self.run_sensor("40\n41\n", sleep=5, ignore_term=True)
        self.assertEqual(r.returncode, 0)
        self.assertEqual(r.stdout, "100000\n")
        self.assertIn("failsafe", status)
        # 時間は Linux でだけ確かめる。TERM を無視するものに timeout -k 0.3 1.2 をかけると、
        # Linux（coreutils 9.4）は 1.50 秒で終わるが、macOS の timeout は素で約 1.8 秒かかる
        if sys.platform.startswith("linux"):
            self.assertLess(self.elapsed, 1.8)


class RestoreConfTests(unittest.TestCase):
    """BIOS の pwmN_enable の記録（case-fan-restore.conf）に、ラジエーターのチャネルの行も入る"""

    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        add_radiator(self.fx)
        self.etc = self.fx.base / "etc-fan2go"
        self.etc.mkdir()
        self.conf = self.etc / "case-fan-restore.conf"
        (self.fx.nct / "pwm3_enable").write_text("2\n")

    def run_write(self, **env):
        return subprocess.run([BASH, str(INSTALL), "--test-write-restore-conf"], env={
            **os.environ,
            "UBUNTU_HOST": "no-such-host-for-tests",
            "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
            "CASE_FAN_HWMON": "nct6799",
            "CASE_FAN_TEST_CONFIG_DIR": str(self.etc),
            **RAD_OFF,
            **RAD_ON,
            **env,
        }, capture_output=True, text=True)

    def lines(self):
        return [l for l in self.conf.read_text().splitlines() if not l.startswith("#")]

    def test_both_groups_are_recorded_and_restored(self):
        r = self.run_write()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.lines(), ["nct6799 3 2", "nct6799 2 5"])
        # fan2go が操っている（enable=1）ところから、case-fan-restore-bios が 2 チャネルとも戻す
        (self.fx.nct / "pwm2_enable").write_text("1\n")
        (self.fx.nct / "pwm3_enable").write_text("1\n")
        r = subprocess.run([BASH, str(RESTORE)], env={
            **os.environ, "CASE_FAN_RESTORE_CONF": str(self.conf), "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
        }, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.fx.nct / "pwm2_enable").read_text().strip(), "5")
        self.assertEqual((self.fx.nct / "pwm3_enable").read_text().strip(), "2")
        self.assertIn("nct6799 pwm2 を pwm2_enable=5", r.stdout)
        self.assertIn("nct6799 pwm3 を pwm3_enable=2", r.stdout)

    def test_without_group_only_case_fans(self):
        r = self.run_write(CASE_FAN_RAD_CHANNELS="")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.lines(), ["nct6799 3 2"])

    def test_manual_radiator_channel_uses_the_earlier_record(self):
        # 前の入れ方（ケースファンだけ）の記録があり、ラジエーターのチャネルの記録はない
        self.conf.write_text("# old\nnct6799 3 2\nnct6799 2 5\n")
        (self.fx.nct / "pwm2_enable").write_text("1\n")
        r = self.run_write()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.lines(), ["nct6799 3 2", "nct6799 2 5"])

    def test_manual_radiator_channel_without_record_is_refused(self):
        self.conf.write_text("# old\nnct6799 3 2\n")
        (self.fx.nct / "pwm2_enable").write_text("1\n")
        r = self.run_write()
        self.assertNotEqual(r.returncode, 0)
        # 記録を書く前に、BIOS の曲線との比べ（BIOS のモードが分からない）で止まる
        self.assertIn("いまは手動（pwm2_enable=1）で、BIOS のモードの記録がない", r.stderr)
        self.assertEqual(self.conf.read_text(), "# old\nnct6799 3 2\n")

    def test_manual_case_fan_channel_without_record_is_refused(self):
        # ケースファンの組のチャネルは、今までどおり記録を書くところで止まる
        self.conf.write_text("# old\nnct6799 2 5\n")
        (self.fx.nct / "pwm3_enable").write_text("1\n")
        r = self.run_write()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("pwm3 が手動（enable=1）のまま", r.stderr)
        self.assertEqual(self.conf.read_text(), "# old\nnct6799 2 5\n")


class DroppedChannelTests(unittest.TestCase):
    """組から外したチャネル（ラジエーターの組をやめた pwm2）を、記録を書き直す前に BIOS の制御へ戻す"""

    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)
        add_radiator(self.fx)
        self.etc = self.fx.base / "etc-fan2go"
        self.etc.mkdir()
        self.conf = self.etc / "case-fan-restore.conf"
        # 前の入れ方（ケースファンの pwm3 とラジエーターの pwm2）の記録
        self.old = "# old\nnct6799 3 2\nnct6799 2 5\n"
        self.conf.write_text(self.old)
        (self.fx.nct / "pwm3_enable").write_text("2\n")
        self.enable2 = self.fx.nct / "pwm2_enable"

    def run_write(self, **env):
        # 組をやめた形: ケースファンは pwm3、CASE_FAN_RAD_CHANNELS は空（ほかの CASE_FAN_RAD_* は残っている）
        return subprocess.run([BASH, str(INSTALL), "--test-write-restore-conf"], env={
            **os.environ,
            "UBUNTU_HOST": "no-such-host-for-tests",
            "CASE_FAN_HWMON_ROOT": str(self.fx.hwmon),
            "CASE_FAN_HWMON": "nct6799",
            "CASE_FAN_TEST_CONFIG_DIR": str(self.etc),
            **RAD_OFF,
            **RAD_ON,
            **RAD_BACKUP,
            "CASE_FAN_RAD_CHANNELS": "",
            **env,
        }, capture_output=True, text=True)

    def lines(self):
        return [l for l in self.conf.read_text().splitlines() if not l.startswith("#")]

    def test_dropped_channel_already_back_to_bios_is_left_alone(self):
        # ふつうの入れ直し: fan2go を止めたときに pwm2 は 5 へ戻っている
        self.enable2.write_text("5\n")
        r = self.run_write()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.lines(), ["nct6799 3 2"])
        self.assertEqual(self.enable2.read_text().strip(), "5")
        self.assertIn("組から外した nct6799 pwm2 は BIOS の制御（pwm2_enable=5）です", r.stdout)

    def test_dropped_channel_left_manual_is_restored_before_the_record_is_rewritten(self):
        # fan2go の戻しも ExecStopPost も効かず、pwm2 が手動のまま残った
        self.enable2.write_text("1\n")
        r = self.run_write()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.enable2.read_text().strip(), "5")
        self.assertEqual(self.lines(), ["nct6799 3 2"])
        self.assertIn("前の記録の pwm2_enable=5（BIOS の制御）へ戻しました", r.stdout)

    def test_dropped_channel_with_unusable_record_is_refused(self):
        self.old = "# old\nnct6799 3 2\nnct6799 2 1\n"
        self.conf.write_text(self.old)
        self.enable2.write_text("1\n")
        r = self.run_write()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("前の記録の値（1）では BIOS の制御へ戻せません", r.stderr)
        self.assertEqual(self.conf.read_text(), self.old)

    @unittest.skipIf(hasattr(os, "geteuid") and os.geteuid() == 0, "root は読むだけのファイルにも書ける")
    def test_dropped_channel_that_cannot_be_restored_keeps_the_old_record(self):
        self.enable2.write_text("1\n")
        self.enable2.chmod(0o444)
        self.addCleanup(self.enable2.chmod, 0o644)
        r = self.run_write()
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("pwm2_enable=5（BIOS の制御）へ戻せませんでした。記録は書き直していません", r.stderr)
        self.assertEqual(self.conf.read_text(), self.old)
        # 前の記録が残るので、case-fan-restore-bios はまだ pwm2 を戻しに行ける
        self.assertIn("nct6799 2 5", self.conf.read_text())

    def test_channel_kept_in_the_group_is_not_touched(self):
        # 組を続ける（CASE_FAN_RAD_CHANNELS=2）なら、外したチャネルはなく、記録は 2 行のまま
        self.enable2.write_text("5\n")
        r = self.run_write(CASE_FAN_RAD_CHANNELS="2")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.lines(), ["nct6799 3 2", "nct6799 2 5"])
        self.assertNotIn("組から外した", r.stdout + r.stderr)


class RestoreTests(unittest.TestCase):
    def test_restores_recorded_enable_values(self):
        fx = Fixture()
        self.addCleanup(fx.close)
        (fx.nct / "pwm2_enable").write_text("1\n")
        (fx.nct / "pwm3_enable").write_text("1\n")
        conf = fx.base / "restore.conf"
        conf.write_text("# comment\nnct6799 2 5\nnct6799 3 2\n")
        r = subprocess.run([BASH, str(RESTORE)], env={
            **os.environ, "CASE_FAN_RESTORE_CONF": str(conf), "CASE_FAN_HWMON_ROOT": str(fx.hwmon),
        }, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((fx.nct / "pwm2_enable").read_text().strip(), "5")
        self.assertEqual((fx.nct / "pwm3_enable").read_text().strip(), "2")
        self.assertEqual((fx.nct / "pwm1_enable").read_text().strip(), "5")

    def test_missing_chip_is_reported(self):
        fx = Fixture()
        self.addCleanup(fx.close)
        conf = fx.base / "restore.conf"
        conf.write_text("nct6798 2 5\n")
        r = subprocess.run([BASH, str(RESTORE)], env={
            **os.environ, "CASE_FAN_RESTORE_CONF": str(conf), "CASE_FAN_HWMON_ROOT": str(fx.hwmon),
        }, capture_output=True, text=True)
        self.assertNotEqual(r.returncode, 0)


if __name__ == "__main__":
    unittest.main()
