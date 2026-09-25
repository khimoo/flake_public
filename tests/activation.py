"""Run generated activation snippets with fake network/secret tools in a temp tree."""
import json
import os
import shutil
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
        jq_prefix = str(Path(shutil.which("jq")).resolve().parents[1])
        script = (script.replace("@test-home@", str(self.home))
                  .replace("@tools@", str(self.tools.parent)).replace("@jq@", jq_prefix))
        # Isolate the snippet's home without modifying the runner's HOME.
        script = script.replace("$HOME", "${TEST_HOME}")
        env = os.environ | {"TEST_HOME": str(self.home), "CALL_LOG": str(self.log), "DRY_RUN_CMD": ""} | overrides
        return subprocess.run(["bash", "-euo", "pipefail", "-c", script], env=env,
                              capture_output=True, text=True)

    def test_dry_run_has_no_side_effects(self):
        for name in ["clone", "secrets", "settings"]:
            with self.subTest(name=name):
                result = self.run_activation(name, DRY_RUN_CMD="echo")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(self.home.exists())
                self.assertFalse(self.log.exists())

    def settings_link(self, content):
        source = self.home / "config/claude/settings.json"
        source.parent.mkdir(parents=True)
        if content is not None:
            source.write_text(content)
        link = self.home / ".claude/settings.json"
        link.parent.mkdir(parents=True)
        link.symlink_to(source)
        return source, link

    def test_settings_link_becomes_a_file_without_managed_keys(self):
        source, link = self.settings_link(
            '{"model": "opus", "theme": "dark", "hooks": {}, "enabledPlugins": {},'
            ' "extraKnownMarketplaces": {}, "outputStyle": "x", "language": "Japanese"}')
        for _ in range(2):
            result = self.run_activation("settings")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(link.is_symlink())
            self.assertEqual(json.loads(link.read_text()), {"model": "opus", "theme": "dark"})
        self.assertIn('"hooks"', source.read_text())
        self.assertEqual(list(link.parent.glob("settings.json.*")), [])

    def test_settings_missing_source_becomes_an_empty_object(self):
        _, link = self.settings_link(None)
        result = self.run_activation("settings")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(link.read_text()), {})

    def test_settings_invalid_json_keeps_the_link(self):
        source, link = self.settings_link("not json")
        self.assertNotEqual(self.run_activation("settings").returncode, 0)
        self.assertEqual(link.readlink(), source)
        self.assertEqual(list(link.parent.glob("settings.json.*")), [])

    def test_settings_dry_run_keeps_the_link(self):
        source, link = self.settings_link('{"model": "opus"}')
        result = self.run_activation("settings", DRY_RUN_CMD="echo")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(link.readlink(), source)

    def test_settings_leaves_other_files_alone(self):
        link = self.home / ".claude/settings.json"
        link.parent.mkdir(parents=True)
        link.write_text('keep')
        self.assertEqual(self.run_activation("settings").returncode, 0)
        self.assertEqual(link.read_text(), 'keep')
        link.unlink()
        other = self.root / "elsewhere.json"
        other.write_text('{"hooks": {}}')
        link.symlink_to(other)
        self.assertEqual(self.run_activation("settings").returncode, 0)
        self.assertEqual(link.readlink(), other)

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
        self.assertNotEqual(self.run_activation("secrets", FAIL_TOOL="1").returncode, 0)
        self.assertFalse((self.home / ".ssh/id_github").exists())
        self.assertEqual(list((self.home / ".ssh").glob("*.tmp.*")), [])
        result = self.run_activation("secrets")
        self.assertEqual(result.returncode, 0, result.stderr)
        key = self.home / ".ssh/id_github"
        self.assertEqual(key.stat().st_mode & 0o777, 0o600)
        calls = self.log.read_text()
        self.assertEqual(self.run_activation("secrets").returncode, 0)
        self.assertEqual(self.log.read_text(), calls)


if __name__ == "__main__":
    unittest.main()
