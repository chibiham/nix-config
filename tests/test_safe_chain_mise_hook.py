"""miseのprecmd/chpwdフック実行後も npm run の子がSafe Chainを通ることを確かめる。

生成済みの .zshrc（home-manager の activationPackage）を使う。switchはしない:
  nix build --no-link --print-out-paths '.#homeConfigurations."chibiham@mac-mini".activationPackage'
  HM_GENERATION=<出力パス> python3 -m unittest tests/test_safe_chain_mise_hook.py
ネットワーク（Safe Chainのマルウェア判定）とmise管理のnodeが必要。
"""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

GENERATION = os.environ.get("HM_GENERATION")


@unittest.skipUnless(GENERATION, "HM_GENERATION が未設定")
class SafeChainMiseHookTests(unittest.TestCase):
    def zsh(self, body, cwd, timeout):
        zshrc = Path(GENERATION) / "home-files/.zshrc"
        # 対話シェルのプロンプト直前と同じく chpwd → precmd の全フックを順に呼ぶ
        script = (
            f"source {zshrc} >/dev/null 2>&1\n"
            "for f in $chpwd_functions; do $f; done\n"
            "for f in $precmd_functions; do $f; done\n"
            "unfunction npm 2>/dev/null\n"  # 関数ではなくPATH上の解決を試す
            + body
        )
        return subprocess.run(
            ["/bin/zsh", "-f", "-c", script],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )

    def test_npm_run_child_is_blocked_by_safe_chain(self):
        with tempfile.TemporaryDirectory() as directory:
            Path(directory, "package.json").write_text(
                json.dumps(
                    {
                        "name": "sct",
                        "version": "1.0.0",
                        "scripts": {
                            "inst": "npm install safe-chain-test --no-save"
                        },
                    }
                )
            )
            r = self.zsh(
                "print -r -- \"hooks=$precmd_functions\"\n"
                "print -r -- \"path1=${path[1]}\"\n"
                "npm run inst\n",
                directory,
                180,
            )
            out = r.stdout + r.stderr
            print(out)
            self.assertIn("_mise_hook_precmd", out)
            self.assertRegex(out, r"path1=\S*safe-chain-shims/bin")
            self.assertNotEqual(r.returncode, 0)
            self.assertIn("safe-chain-test", out)
            self.assertRegex(out.lower(), r"malware|blocked|safe-chain")
            self.assertFalse(Path(directory, "node_modules/safe-chain-test").exists())

    def test_npm_version_returns_promptly(self):
        with tempfile.TemporaryDirectory() as directory:
            r = self.zsh("npm --version\n", directory, 30)
            print(r.stdout + r.stderr)
            self.assertEqual(r.returncode, 0)
            self.assertRegex(r.stdout, r"\d+\.\d+\.\d+")


if __name__ == "__main__":
    unittest.main()
