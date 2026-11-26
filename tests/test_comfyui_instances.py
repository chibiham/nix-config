"""ComfyUI の 2 つ目以降の常駐（COMFY_EXTRA_INSTANCES）を、にせのコマンドの環境で確かめる。

実機（systemd・GPU・ネットワーク）には触らない。PATH の先頭に systemctl・curl・nvidia-smi・uv などのまねを置き、
HOME を一時ディレクトリにして、スクリプトを UBUNTU_HOST=dekahamuntu・chibihamuntu・設定ファイルのないホストで流す。

  python3 -m unittest -v tests/test_comfyui_instances.py

変更の前のリポジトリ（例: origin/develop を git worktree add で出した場所）を BASE_REPO に渡すと、
chibihamuntu・設定ファイルのないホストで、unit・出力・systemctl の呼び出しが変更の前と同じかも確かめる。

  BASE_REPO=/tmp/nixcfg-base python3 -m unittest -v tests/test_comfyui_instances.py

macOS の bash 3.2 でも流れる（TEST_BASH で別の bash を選べる）。
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
BASE_REPO = os.environ.get("BASE_REPO")
BASH = os.environ.get("TEST_BASH", "bash")

# 本番（dekahamuntu）の今の comfyui.service（2026-11-27 に読んだもの）。/home/chibiham は HOME に読み替える
LIVE_MAIN_UNIT = """\
[Unit]
Description=ComfyUI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/chibiham/ComfyUI
Environment=CC=/usr/bin/cc
Environment=CXX=/usr/bin/c++
Environment=CUDA_DEVICE_ORDER=PCI_BUS_ID
Environment=CUDA_VISIBLE_DEVICES=0,1
ExecStart=/home/chibiham/ComfyUI/.venv/bin/python /home/chibiham/ComfyUI/main.py --listen 127.0.0.1 --port 8188 --enable-manager
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
"""

EXPECTED_GPU1_UNIT = """\
# install-comfyui-ubuntu.sh が COMFY_EXTRA_INSTANCES から書く
# 「gpu1:8189:1」。手で直さず、hosts/ubuntu/<ホスト名>.env を変えて install-comfyui-ubuntu.sh --unit-only を流す
[Unit]
Description=ComfyUI (gpu1, GPU 1)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/chibiham/ComfyUI
Environment=CC=/usr/bin/cc
Environment=CXX=/usr/bin/c++
Environment=CUDA_DEVICE_ORDER=PCI_BUS_ID
Environment=CUDA_VISIBLE_DEVICES=1
ExecStart=/home/chibiham/ComfyUI/.venv/bin/python /home/chibiham/ComfyUI/main.py --listen 127.0.0.1 --port 8189 --temp-directory /home/chibiham/ComfyUI/temp-gpu1
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
"""

FAKE_SYSTEMCTL = r'''#!/usr/bin/env python3
import json, os, sys
state = os.environ["FAKE_STATE"]
args = sys.argv[1:]
with open(os.path.join(state, "calls.jsonl"), "a") as f:
    f.write(json.dumps(["systemctl"] + args) + "\n")
words = [a for a in args if not a.startswith("-")]
flags = [a for a in args if a.startswith("-")]
active = os.path.join(state, "active")
os.makedirs(active, exist_ok=True)
cmd, units = (words[0], words[1:]) if words else ("", [])
def fail(u):
    return os.path.exists(os.path.join(state, "fail", u))
if cmd == "is-active":
    sys.exit(0 if all(os.path.exists(os.path.join(active, u)) for u in units) else 3)
if cmd in ("start", "restart") or (cmd == "enable" and "--now" in flags):
    for u in units:
        if fail(u):
            sys.exit(1)
        open(os.path.join(active, u), "w").close()
if cmd == "stop" or (cmd == "disable" and "--now" in flags):
    for u in units:
        p = os.path.join(active, u)
        if os.path.exists(p):
            os.remove(p)
sys.exit(0)
'''

FAKE_CURL = r'''#!/usr/bin/env python3
import json, os, re, sys
state = os.environ["FAKE_STATE"]
args = sys.argv[1:]
with open(os.path.join(state, "calls.jsonl"), "a") as f:
    f.write(json.dumps(["curl"] + args) + "\n")
url = next(a for a in args if a.startswith("http"))
m = re.match(r"http://127\.0\.0\.1:(\d+)(/.*)", url)
port, path = m.group(1), m.group(2)
if path == "/queue":
    q = os.path.join(state, "queue", port)
    if os.path.exists(q):
        print(open(q).read())
        sys.exit(0)
    sys.exit(7)
if path == "/system_stats":
    print(json.dumps({"system": {"comfyui_version": "0.45.2"}}))
    sys.exit(0)
sys.exit(0)
'''

FAKE_LOG = r'''#!/usr/bin/env python3
import json, os, sys
with open(os.path.join(os.environ["FAKE_STATE"], "calls.jsonl"), "a") as f:
    f.write(json.dumps([os.path.basename(sys.argv[0])] + sys.argv[1:]) + "\n")
'''

FAKE_UV = FAKE_LOG + r'''if sys.argv[1:3] == ["pip", "freeze"]:
    print("torch==2.13.0+cu130")
'''

FAKE_ARIA2C = FAKE_LOG + r'''d = next(a.split("=", 1)[1] for a in sys.argv if a.startswith("--dir="))
o = next(a.split("=", 1)[1] for a in sys.argv if a.startswith("--out="))
os.makedirs(d, exist_ok=True)
open(os.path.join(d, o), "w").write("x")
'''

FAKE_UVX = FAKE_LOG + r'''print("{{ fake template }}")
'''

FAKE_PYTHON = r'''#!/usr/bin/env python3
import os, sys
sys.stdin.read()
print("fake-cuda CUDA_VISIBLE_DEVICES=" + os.environ.get("CUDA_VISIBLE_DEVICES", "(なし)"))
'''


class Sandbox:
    """にせのコマンドと一時 HOME。repo は流すリポジトリ（変更の後か、BASE_REPO）"""

    def __init__(self, base: Path, repo: Path):
        self.repo = repo
        self.home = base / "home"
        self.state = base / "state"
        self.bin = base / "bin"
        for d in (self.home, self.state, self.bin, self.state / "queue", self.state / "fail"):
            d.mkdir(parents=True)
        fakes = {
            "systemctl": FAKE_SYSTEMCTL,
            "curl": FAKE_CURL,
            "nvidia-smi": FAKE_LOG,
            "apt-get": FAKE_LOG,
            "sudo": FAKE_LOG,
            "uv": FAKE_UV,
            "aria2c": FAKE_ARIA2C,
            "uvx": FAKE_UVX,
            "llama-server": FAKE_LOG,
            "uname": "#!/bin/sh\necho Linux\n",
            # git lfs だけまねる（ほかは本物の git）
            "git": f'#!/bin/sh\nif [ "$1" = lfs ]; then exit 0; fi\nexec {shutil.which("git")} "$@"\n',
            "sleep": "#!/bin/sh\nexit 0\n",
        }
        for name, body in fakes.items():
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)
        venv = self.home / "ComfyUI/.venv/bin"
        venv.mkdir(parents=True)
        (venv / "python").write_text(FAKE_PYTHON)
        (venv / "python").chmod(0o755)
        self.units = self.home / ".config/systemd/user"

    def run(self, script, *args, host="dekahamuntu", env=None):
        e = {
            "PATH": f"{self.bin}:{os.environ['PATH']}",
            "HOME": str(self.home),
            "FAKE_STATE": str(self.state),
            "UBUNTU_HOST": host,
            # macOS の bash 3.2 は UTF-8 のロケールで「$変数」の直後の全角文字を変数名に含めてしまうので C で流す
            # （Ubuntu の bash 5 では違いがない。出力のバイトは UTF-8 のまま）
            "LC_ALL": "C",
            "GIT_CONFIG_NOSYSTEM": "1",
            "USER": "chibiham",
        }
        e.update(env or {})
        return subprocess.run(
            [BASH, str(self.repo / "scripts" / script), *args],
            env=e, capture_output=True, text=True, cwd=str(self.home),
        )

    def calls(self, prog=None):
        path = self.state / "calls.jsonl"
        if not path.exists():
            return []
        calls = [json.loads(line) for line in path.read_text().splitlines()]
        return [c for c in calls if prog is None or c[0] == prog]

    def set_queue(self, port, running=0, pending=0):
        (self.state / "queue" / str(port)).write_text(
            json.dumps({"queue_running": [[i] for i in range(running)], "queue_pending": [[i] for i in range(pending)]})
        )

    def systemctl_cmds(self, cmd):
        return [c for c in self.calls("systemctl") if cmd in c]

    def unit(self, name):
        return (self.units / name).read_text().replace(str(self.home), "/home/chibiham")

    def normalize(self, text):
        text = text.replace(str(self.home), "<HOME>").replace(str(self.repo), "<REPO>").replace(str(self.state), "<STATE>")
        # diff -u の見出しの時刻と、控えのディレクトリの UTC 時刻
        text = re.sub(r"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d(\.\d+)?( [+-]\d{4})?", "<TIME>", text)
        return re.sub(r"\d{8}T\d{6}Z", "<UTC>", text)


def git(*args, cwd, home):
    # 時刻を決めておく（変更の前と後の写しで commit が同じになるように）
    env = {"PATH": os.environ["PATH"], "HOME": str(home), "GIT_CONFIG_NOSYSTEM": "1",
           "GIT_AUTHOR_DATE": "2026-11-27T00:00:00Z", "GIT_COMMITTER_DATE": "2026-11-27T00:00:00Z"}
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "-c", "commit.gpgsign=false",
                    "-c", "tag.gpgsign=false", "-c", "init.defaultBranch=master", *args],
                   cwd=str(cwd), check=True, capture_output=True, env=env)


class InstallUnitOnlyDekahamuntuTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.sb = Sandbox(Path(self.tmp.name), REPO)

    def tearDown(self):
        self.tmp.cleanup()

    def test_first_run_writes_both_units_and_starts_them(self):
        r = self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        # 1 つ目は本番の今の unit と 1 バイトも違わない
        self.assertEqual(self.sb.unit("comfyui.service"), LIVE_MAIN_UNIT)
        self.assertEqual(self.sb.unit("comfyui-gpu1.service"), EXPECTED_GPU1_UNIT)
        self.assertIn(["systemctl", "--user", "enable", "comfyui-gpu1.service"], self.sb.calls("systemctl"))
        self.assertIn(["systemctl", "--user", "restart", "comfyui.service"], self.sb.calls("systemctl"))
        self.assertIn(["systemctl", "--user", "restart", "comfyui-gpu1.service"], self.sb.calls("systemctl"))
        self.assertIn("comfyui-gpu1 に見せるGPU: 1", r.stdout)
        self.assertIn("fake-cuda CUDA_VISIBLE_DEVICES=1", r.stdout)
        # 両方のキューと起動を見る
        urls = [c[-1] for c in self.sb.calls("curl")]
        for port in ("8188", "8189"):
            self.assertIn(f"http://127.0.0.1:{port}/queue", urls)
            self.assertIn(f"http://127.0.0.1:{port}/system_stats", urls)
        self.assertFalse((self.sb.home / ".local/state/comfyui-update/unit-apply-pending").exists())

    def test_second_run_changes_nothing(self):
        self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        (self.sb.state / "calls.jsonl").unlink()
        r = self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("comfyui.service は変わらず、comfyui.service は動いています。何もしません", r.stdout)
        self.assertIn("comfyui-gpu1.service は変わらず、comfyui-gpu1.service は動いています。何もしません", r.stdout)
        self.assertEqual(self.sb.systemctl_cmds("restart"), [])
        self.assertEqual(self.sb.systemctl_cmds("daemon-reload"), [])

    def test_only_changed_extra_is_restarted(self):
        self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        gpu1 = self.sb.units / "comfyui-gpu1.service"
        gpu1.write_text(gpu1.read_text().replace("--port 8189", "--port 8199"))
        (self.sb.state / "calls.jsonl").unlink()
        r = self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("-ExecStart=", r.stdout)
        self.assertEqual(self.sb.systemctl_cmds("restart"), [["systemctl", "--user", "restart", "comfyui-gpu1.service"]])
        self.assertEqual(self.sb.unit("comfyui-gpu1.service"), EXPECTED_GPU1_UNIT)

    def test_busy_queue_on_extra_stops_without_writing(self):
        self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        gpu1 = self.sb.units / "comfyui-gpu1.service"
        changed = gpu1.read_text().replace("--port 8189", "--port 8199")
        gpu1.write_text(changed)
        self.sb.set_queue(8189, running=1)
        (self.sb.state / "calls.jsonl").unlink()
        r = self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("キューが空ではありません", r.stderr)
        self.assertEqual(gpu1.read_text(), changed)
        self.assertEqual(self.sb.systemctl_cmds("restart"), [])

    def test_stopped_extra_is_started_main_is_left_alone(self):
        self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        (self.sb.state / "active/comfyui-gpu1.service").unlink()
        self.sb.set_queue(8188, running=1)  # 1 つ目は回している。起こし直さないので見ない
        (self.sb.state / "calls.jsonl").unlink()
        r = self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("comfyui-gpu1.service が動いていません", r.stdout)
        self.assertEqual(self.sb.systemctl_cmds("restart"), [["systemctl", "--user", "restart", "comfyui-gpu1.service"]])
        self.assertNotIn("http://127.0.0.1:8188/queue", [c[-1] for c in self.sb.calls("curl")])

    def test_bad_config_stops_before_anything(self):
        for value in ("gpu1:8188:1", "gpu1:8189", "GPU1:8189:1", "gpu1:8189:1 gpu1:8190:1", "a:8189:1 b:8189:1", "gpu1:80:1"):
            with self.subTest(value=value):
                r = self.sb.run("install-comfyui-ubuntu.sh", "--unit-only", env={"COMFY_EXTRA_INSTANCES": value})
                self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
                self.assertIn("COMFY_EXTRA_INSTANCES", r.stderr)
                self.assertFalse(self.sb.units.exists())

    def test_removed_extra_is_reported_and_removed_with_remove(self):
        self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        # 設定から外す（env の `:=` は空を「未設定」と読むので、空白 1 つで外したことにする）: 「何もしません」と一緒に、消し方を出す
        r = self.sb.run("install-comfyui-ubuntu.sh", "--unit-only", env={"COMFY_EXTRA_INSTANCES": " "})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("--remove gpu1", r.stdout)
        # 設定に残っているうちは消さない
        r = self.sb.run("install-comfyui-ubuntu.sh", "--remove", "gpu1")
        self.assertEqual(r.returncode, 1)
        self.assertTrue((self.sb.units / "comfyui-gpu1.service").exists())
        # 列が空でなければ止まる
        self.sb.set_queue(8189, pending=2)
        r = self.sb.run("install-comfyui-ubuntu.sh", "--remove", "gpu1", env={"COMFY_EXTRA_INSTANCES": " "})
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertTrue((self.sb.units / "comfyui-gpu1.service").exists())
        (self.sb.state / "queue/8189").unlink()
        (self.sb.state / "calls.jsonl").unlink()
        r = self.sb.run("install-comfyui-ubuntu.sh", "--remove", "gpu1", env={"COMFY_EXTRA_INSTANCES": " "})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse((self.sb.units / "comfyui-gpu1.service").exists())
        self.assertIn(["systemctl", "--user", "disable", "--now", "comfyui-gpu1.service"], self.sb.calls("systemctl"))
        self.assertIn(["systemctl", "--user", "daemon-reload"], self.sb.calls("systemctl"))
        self.assertTrue((self.sb.units / "comfyui.service").exists())

    def test_remove_refuses_unit_without_mark(self):
        self.sb.units.mkdir(parents=True)
        (self.sb.units / "comfyui-other.service").write_text("[Service]\nExecStart=/bin/true --port 9000\n")
        r = self.sb.run("install-comfyui-ubuntu.sh", "--remove", "other")
        self.assertEqual(r.returncode, 1)
        self.assertTrue((self.sb.units / "comfyui-other.service").exists())

    def test_full_install_enables_both(self):
        (self.sb.home / "ComfyUI/.git").mkdir()
        (self.sb.home / "ComfyUI/requirements.txt").write_text("")
        r = self.sb.run("install-comfyui-ubuntu.sh")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.sb.unit("comfyui.service"), LIVE_MAIN_UNIT)
        self.assertEqual(self.sb.unit("comfyui-gpu1.service"), EXPECTED_GPU1_UNIT)
        calls = self.sb.calls("systemctl")
        self.assertIn(["systemctl", "--user", "enable", "--now", "comfyui.service"], calls)
        self.assertIn(["systemctl", "--user", "enable", "--now", "comfyui-gpu1.service"], calls)


def make_comfy_repo(sb):
    """本物の git で、v0.45.2 のタグを持つ origin と ~/ComfyUI（master を追う）を作る"""
    origin = sb.home.parent / "origin"
    origin.mkdir()
    git("init", "-q", "-b", "master", cwd=origin, home=sb.home)
    (origin / "requirements.txt").write_text("torch\n")
    (origin / ".gitignore").write_text(".venv/\n")
    git("add", ".", cwd=origin, home=sb.home)
    git("commit", "-q", "-m", "init", cwd=origin, home=sb.home)
    git("tag", "v0.45.2", cwd=origin, home=sb.home)
    comfy = sb.home / "ComfyUI"
    git("init", "-q", "-b", "master", cwd=comfy, home=sb.home)
    git("remote", "add", "origin", str(origin), cwd=comfy, home=sb.home)
    git("fetch", "-q", "origin", cwd=comfy, home=sb.home)
    git("checkout", "-q", "-f", "master", cwd=comfy, home=sb.home)


class UpdateComfyuiTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.sb = Sandbox(Path(self.tmp.name), REPO)
        make_comfy_repo(self.sb)
        self.sb.run("install-comfyui-ubuntu.sh", "--unit-only")
        (self.sb.state / "calls.jsonl").unlink()

    def tearDown(self):
        self.tmp.cleanup()

    def test_checks_both_queues_and_restarts_both(self):
        r = self.sb.run("update-comfyui-ubuntu.sh")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        urls = [c[-1] for c in self.sb.calls("curl")]
        for port in ("8188", "8189"):
            self.assertIn(f"http://127.0.0.1:{port}/queue", urls)
            self.assertIn(f"http://127.0.0.1:{port}/system_stats", urls)
        self.assertEqual(self.sb.systemctl_cmds("restart"),
                         [["systemctl", "--user", "restart", "comfyui.service", "comfyui-gpu1.service"]])

    def test_busy_extra_queue_stops_before_git(self):
        self.sb.set_queue(8188)
        self.sb.set_queue(8189, running=1)
        r = self.sb.run("update-comfyui-ubuntu.sh")
        self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
        self.assertIn("キューが空ではありません", r.stderr)
        self.assertEqual(self.sb.systemctl_cmds("restart"), [])
        self.assertFalse((self.sb.home / ".local/state/comfyui-update").exists() and
                         any(p.is_dir() for p in (self.sb.home / ".local/state/comfyui-update").iterdir()))

    def test_copy_does_not_touch_extra(self):
        copy = self.sb.home / "ComfyUI-copy"
        subprocess.run(["cp", "-R", str(self.sb.home / "ComfyUI"), str(copy)], check=True)
        self.sb.set_queue(8189, running=1)  # 本番の 2 つ目は回している
        r = self.sb.run("update-comfyui-ubuntu.sh", "--no-restart", env={"COMFY_DIR": str(copy)})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.sb.calls("systemctl"), [])
        r = self.sb.run("update-comfyui-ubuntu.sh", env={"COMFY_DIR": str(copy), "COMFY_PORT": "8288"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("2 つ目以降の常駐（COMFY_EXTRA_INSTANCES）には触りません", r.stdout)
        self.assertNotIn("comfyui-gpu1.service", json.dumps(self.sb.calls("systemctl")))
        self.assertNotIn("http://127.0.0.1:8189/queue", [c[-1] for c in self.sb.calls("curl")])

    def test_extra_without_unit_is_skipped(self):
        (self.sb.units / "comfyui-gpu1.service").unlink()
        r = self.sb.run("update-comfyui-ubuntu.sh")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("comfyui-gpu1.service の unit がないので飛ばします", r.stdout)
        self.assertEqual(self.sb.systemctl_cmds("restart"), [["systemctl", "--user", "restart", "comfyui.service"]])


class OtherScriptsDekahamuntuTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.sb = Sandbox(Path(self.tmp.name), REPO)

    def tearDown(self):
        self.tmp.cleanup()

    def test_art_studio_dropin_has_both_urls(self):
        r = self.sb.run("configure-art-studio-ubuntu.sh", "--dry-run")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("Environment=COMFYUI_URL=http://127.0.0.1:8188,http://127.0.0.1:8189\n", r.stdout)

    def test_qwen_dual_conflicts_with_gpu1(self):
        r = self.sb.run("install-qwen38-ubuntu.sh")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        dual = (self.sb.units / "qwen38-dual.service").read_text()
        self.assertIn("\nConflicts=qwen38.service comfyui.service comfyui-gpu1.service\n", dual)
        # 2 つ目は GPU 1 だけ。GPU 0 だけを束ねるなら入れない
        r = self.sb.run("install-qwen38-ubuntu.sh", env={"LLM_DUAL_CUDA_DEVICES": "0"})
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        dual = (self.sb.units / "qwen38-dual.service").read_text()
        self.assertIn("\nConflicts=qwen38.service comfyui.service\n", dual)


AI_MODE_SCRIPT = os.environ.get("AI_MODE_SCRIPT")


@unittest.skipUnless(AI_MODE_SCRIPT, "AI_MODE_SCRIPT（dekahamuntu の ai-mode の本文）が未設定")
class AiModeDekahamuntuTests(unittest.TestCase):
    """dekahamuntu の ai-mode。本文は次で取り出す（Nix の curl・jq のパスは、にせのコマンドに読み替える）:

      nix eval --raw '.#homeConfigurations."chibiham@dekahamuntu".config.chibiham.ubuntu.aiMode.text' > /tmp/ai-mode.sh
      AI_MODE_SCRIPT=/tmp/ai-mode.sh python3 -m unittest -v tests/test_comfyui_instances.py
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.sb = Sandbox(Path(self.tmp.name), REPO)
        text = Path(AI_MODE_SCRIPT).read_text()
        text = re.sub(r"/nix/store/[^/]+-curl-[^/]+/bin/curl", "curl", text)
        text = re.sub(r"/nix/store/[^/]+-jq-[^/]+/bin/jq", "jq", text)
        self.script = Path(self.tmp.name) / "ai-mode"
        self.script.write_text(text)
        (self.sb.bin / "nvidia-smi").write_text(FAKE_LOG)

    def tearDown(self):
        self.tmp.cleanup()

    def ai_mode(self, mode):
        env = {"PATH": f"{self.sb.bin}:{os.environ['PATH']}", "HOME": str(self.sb.home),
               "FAKE_STATE": str(self.sb.state), "LC_ALL": "C"}
        return subprocess.run([BASH, str(self.script), mode], env=env, capture_output=True, text=True)

    def test_split_starts_both_and_frees_both(self):
        r = self.ai_mode("split")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(["systemctl", "--user", "start", "comfyui.service", "comfyui-gpu1.service", "qwen38.service"],
                      self.sb.calls("systemctl"))
        frees = [c[-1] for c in self.sb.calls("curl") if c[-1].endswith("/free")]
        self.assertEqual(frees, ["http://127.0.0.1:8188/free", "http://127.0.0.1:8189/free"])

    def test_image_dual_starts_both_and_frees_gpu1(self):
        r = self.ai_mode("image-dual")
        self.assertIn(["systemctl", "--user", "start", "comfyui.service", "comfyui-gpu1.service", "qwen38.service"],
                      self.sb.calls("systemctl"))
        frees = [c[-1] for c in self.sb.calls("curl") if c[-1].endswith("/free")]
        self.assertEqual(frees, ["http://127.0.0.1:8189/free"])
        # にせの curl は Router（8080）の /models に空を返す（モデルは載っていない）
        self.assertEqual(r.returncode, 0, r.stderr)

    def test_llm_dual_stops_gpu1_before_dual(self):
        r = self.ai_mode("llm-dual")
        self.assertEqual(r.returncode, 0, r.stderr)
        calls = self.sb.calls("systemctl")
        stop = ["systemctl", "--user", "stop", "comfyui-gpu1.service"]
        start = ["systemctl", "--user", "start", "qwen38-dual.service"]
        self.assertIn(stop, calls)
        self.assertLess(calls.index(stop), calls.index(start))

    def test_stop_and_status_include_gpu1(self):
        self.assertEqual(self.ai_mode("stop").returncode, 0)
        self.assertIn(["systemctl", "--user", "stop", "qwen38-dual.service", "qwen38.service", "comfyui.service",
                       "comfyui-gpu1.service", "applio.service"], self.sb.calls("systemctl"))
        self.assertEqual(self.ai_mode("status").returncode, 0)
        status = [c for c in self.sb.calls("systemctl") if "status" in c]
        self.assertIn("comfyui-gpu1.service", status[0])

    def test_applio_leaves_gpu1(self):
        self.assertEqual(self.ai_mode("applio").returncode, 0)
        self.assertNotIn("comfyui-gpu1.service", json.dumps(self.sb.calls("systemctl")))


@unittest.skipUnless(BASE_REPO, "BASE_REPO（変更の前のリポジトリ）が未設定")
class SameAsBeforeTests(unittest.TestCase):
    """chibihamuntu・設定ファイルのないホスト・（Qwen は）dekahamuntu で、変更の前と比べる"""

    def pair(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        base = Path(tmp.name)
        return Sandbox(base / "new", REPO), Sandbox(base / "old", Path(BASE_REPO))

    def assert_same_run(self, script, *args, host, prepare=None, env=None):
        new, old = self.pair()
        results = []
        for sb in (new, old):
            if prepare:
                prepare(sb)
            r = sb.run(script, *args, host=host, env=env)
            units = {}
            if sb.units.exists():
                units = {p.name: sb.unit(p.name) for p in sorted(sb.units.iterdir()) if p.is_file()}
            calls = [[sb.normalize(a) for a in c] for c in sb.calls()]
            results.append((r.returncode, sb.normalize(r.stdout), sb.normalize(r.stderr), units, calls))
        self.assertEqual(results[0], results[1])
        return results[0]

    def test_install_unit_only_same(self):
        for host in ("chibihamuntu", "nohost-test"):
            with self.subTest(host=host):
                rc, _out, _err, units, _calls = self.assert_same_run("install-comfyui-ubuntu.sh", "--unit-only", host=host)
                self.assertEqual(rc, 0)
                self.assertEqual(list(units), ["comfyui.service"])

    def test_install_unit_only_rerun_same(self):
        def prepare(sb):
            sb.run("install-comfyui-ubuntu.sh", "--unit-only", host="chibihamuntu")
            (sb.state / "calls.jsonl").unlink()
        for host in ("chibihamuntu", "nohost-test"):
            with self.subTest(host=host):
                self.assert_same_run("install-comfyui-ubuntu.sh", "--unit-only", host=host, prepare=prepare)

    def test_install_unit_only_busy_and_changed_same(self):
        def prepare(sb):
            sb.run("install-comfyui-ubuntu.sh", "--unit-only", host="chibihamuntu")
            f = sb.units / "comfyui.service"
            f.write_text(f.read_text().replace("RestartSec=5", "RestartSec=6"))
            sb.set_queue(8188, running=1)
            (sb.state / "calls.jsonl").unlink()
        self.assert_same_run("install-comfyui-ubuntu.sh", "--unit-only", host="chibihamuntu", prepare=prepare)

    def test_full_install_same(self):
        for host in ("chibihamuntu", "nohost-test"):
            with self.subTest(host=host):
                def prepare(sb):
                    (sb.home / "ComfyUI/.git").mkdir()
                    (sb.home / "ComfyUI/requirements.txt").write_text("")
                self.assert_same_run("install-comfyui-ubuntu.sh", host=host, prepare=prepare)

    def test_update_same(self):
        def prepare(sb):
            make_comfy_repo(sb)
            sb.run("install-comfyui-ubuntu.sh", "--unit-only", host="chibihamuntu")
            (sb.state / "calls.jsonl").unlink()
        for host in ("chibihamuntu", "nohost-test"):
            for args in ((), ("--no-restart",), ("--ref", "v0.45.2")):
                with self.subTest(host=host, args=args):
                    rc, out, _err, _units, calls = self.assert_same_run(
                        "update-comfyui-ubuntu.sh", *args, host=host, prepare=prepare)
                    self.assertEqual(rc, 0, out)

    def test_update_busy_same(self):
        def prepare(sb):
            make_comfy_repo(sb)
            sb.run("install-comfyui-ubuntu.sh", "--unit-only", host="chibihamuntu")
            sb.set_queue(8188, pending=1)
            (sb.state / "calls.jsonl").unlink()
        rc, *_ = self.assert_same_run("update-comfyui-ubuntu.sh", host="chibihamuntu", prepare=prepare)
        self.assertEqual(rc, 1)

    def test_qwen_same(self):
        # chibihamuntu は qwen38.service だけ（束ねる unit はない）。dekahamuntu は Conflicts= の 1 行だけが違うはずなので別に見る
        for host in ("chibihamuntu", "nohost-test"):
            with self.subTest(host=host):
                self.assert_same_run("install-qwen38-ubuntu.sh", host=host)

    def test_qwen_dekahamuntu_differs_only_in_conflicts(self):
        new, old = self.pair()
        for sb in (new, old):
            r = sb.run("install-qwen38-ubuntu.sh", host="dekahamuntu")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(new.unit("qwen38.service"), old.unit("qwen38.service"))
        a = new.unit("qwen38-dual.service").splitlines()
        b = old.unit("qwen38-dual.service").splitlines()
        diff = [(x, y) for x, y in zip(a, b) if x != y]
        self.assertEqual(len(a), len(b))
        self.assertEqual(diff, [("Conflicts=qwen38.service comfyui.service comfyui-gpu1.service",
                                 "Conflicts=qwen38.service comfyui.service")])

    def test_art_studio_same(self):
        for host in ("chibihamuntu", "nohost-test"):
            with self.subTest(host=host):
                self.assert_same_run("configure-art-studio-ubuntu.sh", "--dry-run", host=host)

    def test_dekahamuntu_main_unit_same_as_before(self):
        new, old = self.pair()
        for sb in (new, old):
            r = sb.run("install-comfyui-ubuntu.sh", "--unit-only", host="dekahamuntu")
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(new.unit("comfyui.service"), old.unit("comfyui.service"))
        self.assertEqual(new.unit("comfyui.service"), LIVE_MAIN_UNIT)


if __name__ == "__main__":
    unittest.main()
