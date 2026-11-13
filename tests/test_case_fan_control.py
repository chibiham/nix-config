"""Hardware-free checks for the case fan control (fan2go) scripts.

Uses a fake hwmon tree and a fake nvidia-smi. Needs bash 4 or later
(on macOS: BASH=$(nix build --print-out-paths nixpkgs#bash)/bin/bash).
"""

import os
from pathlib import Path
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
        self.assertIn("type: maximum", y)

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

    def test_min_duty_bounds(self):
        r = self.run_print(CASE_FAN_MIN_DUTY="5")
        self.assertNotEqual(r.returncode, 0)
        r = self.run_print(CASE_FAN_MIN_DUTY="50")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("minPwm: 128", r.stdout)


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
