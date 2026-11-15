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


@unittest.skipUnless(sys.platform.startswith("linux"), "--probe は Linux 専用")
class IdentifyHwmonTests(unittest.TestCase):
    """--identify が操る hwmon の選び方を、--probe の「--identify が使う hwmon」の行で確かめる（root 不要）"""

    def setUp(self):
        self.fx = Fixture()
        self.addCleanup(self.fx.close)

    def identify_line(self, **env):
        full = {
            **os.environ,
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

    def env(self, **env):
        if os.geteuid() == 0:
            self.skipTest("root では流さない（sudo なしの入口を試す）")
        return {
            **os.environ,
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

    def start_and_wait_first_tick(self, *args):
        """長く動かし、最初の「1s:」の行が出たところで返す（そのとき pwm は変えたまま）"""
        p = subprocess.Popen([BASH, str(INSTALL), "--identify", *args],
                             env=self.env(CASE_FAN_TEST_IDENTIFY_SECONDS="60"),
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
