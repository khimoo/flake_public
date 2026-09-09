"""Run generated activation snippets with fake network/secret tools in a temp tree."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


class Activation(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.tools = self.root / "tools" / "bin"
        self.tools.mkdir(parents=True)
        self.log = self.root / "calls"
        for name, body in {
            "git": """
if sys.argv[1] != 'clone': raise SystemExit(2)
dest = Path(sys.argv[-1])
dest.mkdir()
(dest / 'partial').write_text('in progress')
if os.environ.get('FAIL_TOOL'): raise SystemExit(17)
(dest / '.git').mkdir()
""",
            "sops": """
print('fake-key-for-test')
if os.environ.get('FAIL_TOOL'): raise SystemExit(18)
""",
        }.items():
            path = self.tools / name
            path.write_text(f"#!{sys.executable}\nimport os, sys\nfrom pathlib import Path\n"
                            "with open(os.environ['CALL_LOG'], 'a') as log: log.write('call\\n')\n" + body)
            path.chmod(0o755)

    def run_activation(self, name, **overrides):
        script = Path(os.environ[name + "ScriptPath"]).read_text()
        script = script.replace("@test-home@", str(self.home)).replace("@tools@", str(self.tools.parent))
        # Isolate the snippet's home without modifying the runner's HOME.
        script = script.replace("$HOME", "${TEST_HOME}")
        env = os.environ | {"TEST_HOME": str(self.home), "CALL_LOG": str(self.log), "DRY_RUN_CMD": ""} | overrides
        return subprocess.run(["bash", "-euo", "pipefail", "-c", script], env=env,
                              capture_output=True, text=True)

    def test_dry_run_has_no_side_effects(self):
        for name in ["clone", "keys", "rustowl"]:
            with self.subTest(name=name):
                result = self.run_activation(name, DRY_RUN_CMD="echo")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(self.home.exists())
                self.assertFalse(self.log.exists())

    def test_clone_failure_can_retry_and_existing_checkout_is_untouched(self):
        result = self.run_activation("clone", FAIL_TOOL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / "config").exists())
        self.assertEqual(list(self.home.glob(".private-clone.*")), [])
        result = self.run_activation("clone")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.home / "config" / ".git").is_dir())
        calls = self.log.read_text()
        self.assertEqual(self.run_activation("clone").returncode, 0)
        self.assertEqual(self.log.read_text(), calls)

    def test_existing_non_checkout_is_rejected(self):
        (self.home / "config").mkdir(parents=True)
        marker = self.home / "config" / "user-file"
        marker.write_text("keep")
        self.assertNotEqual(self.run_activation("clone").returncode, 0)
        self.assertEqual(marker.read_text(), "keep")
        self.assertFalse(self.log.exists())

    def test_key_failure_does_not_leave_empty_destination(self):
        age = self.home / ".config/sops/age/keys.txt"
        age.parent.mkdir(parents=True)
        age.write_text("fake-age-key")
        self.assertNotEqual(self.run_activation("keys", FAIL_TOOL="1").returncode, 0)
        self.assertFalse((self.home / ".ssh/id_github").exists())
        self.assertEqual(list((self.home / ".ssh").glob("*.tmp.*")), [])
        result = self.run_activation("keys")
        self.assertEqual(result.returncode, 0, result.stderr)
        key = self.home / ".ssh/id_github"
        self.assertEqual(key.stat().st_mode & 0o777, 0o600)
        calls = self.log.read_text()
        self.assertEqual(self.run_activation("keys").returncode, 0)
        self.assertEqual(self.log.read_text(), calls)


if __name__ == "__main__":
    unittest.main()
