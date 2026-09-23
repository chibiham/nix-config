"""Hardware-free checks that the LED command only targets the intended GPU."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/turn-off-gpu-led.sh"
GPU = "Gigabyte GeForce RTX 3090 Gaming OC"


class GpuLedOffTests(unittest.TestCase):
    def run_controller(self, listing, detect_exit=0, control_exit=0):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            app = base / "OpenRGB"
            calls = base / "calls.jsonl"
            app.write_text(
                "#!/usr/bin/python3\n"
                "import json, os, sys\n"
                "with open(os.environ['CALLS'], 'a') as f:\n"
                "    f.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                "if '--list-devices' in sys.argv:\n"
                "    print(os.environ['LISTING'])\n"
                "    sys.exit(int(os.environ['DETECT_EXIT']))\n"
                "sys.exit(int(os.environ['CONTROL_EXIT']))\n"
            )
            app.chmod(0o755)
            result = subprocess.run(
                ["bash", str(SCRIPT)],
                env={
                    **os.environ,
                    "OPENRGB_APP": str(app),
                    "OPENRGB_CONFIG": str(base / "config"),
                    "CALLS": str(calls),
                    "LISTING": listing,
                    "DETECT_EXIT": str(detect_exit),
                    "CONTROL_EXIT": str(control_exit),
                },
                capture_output=True,
                text=True,
            )
            return result, [json.loads(line) for line in calls.read_text().splitlines()]

    def test_selects_gpu_by_name_among_other_devices(self):
        result, calls = self.run_controller(f"0: ASUS Motherboard\n7: {GPU}\n9: RAM")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2)
        self.assertEqual(calls[1][-4:], ["--device", GPU, "--mode", "Off"])
        self.assertIn("--noautoconnect", calls[1])

    def test_missing_gpu_never_sends_control(self):
        result, calls = self.run_controller("0: ASUS Motherboard\n1: Gigabyte RTX 3080")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)

    def test_multiple_matching_gpus_never_send_control(self):
        result, calls = self.run_controller(f"0: {GPU}\n1: {GPU}")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)

    def test_description_is_not_mistaken_for_device_header(self):
        result, calls = self.run_controller(f"0: ASUS Motherboard\nDescription: {GPU}")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)

    def test_detection_error_never_sends_control(self):
        result, calls = self.run_controller(f"0: {GPU}", detect_exit=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)

    def test_control_error_is_reported_as_failure(self):
        result, calls = self.run_controller(f"0: {GPU}", control_exit=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 2)


if __name__ == "__main__":
    unittest.main()
