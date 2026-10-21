"""Run generated activation snippets and commands with fake network/secret tools in a temp tree."""
import hashlib
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
print(os.environ.get('FAKE_SECRET', 'fake-key-for-test'))
if os.environ.get('FAIL_TOOL'): raise SystemExit(18)
""",
        }.items():
            path = self.tools / name
            path.write_text(f"#!{sys.executable}\nimport os, sys\nfrom pathlib import Path\n"
                            "with open(os.environ['CALL_LOG'], 'a') as log: log.write('call\\n')\n" + body)
            path.chmod(0o755)

    def run_activation(self, name, *args, **overrides):
        script = Path(os.environ[name + "ScriptPath"]).read_text()
        script = (script.replace("@test-home@", str(self.home))
                  .replace("@tools@", str(self.tools.parent)))
        # Isolate the snippet's home without modifying the runner's HOME.
        script = script.replace("$HOME", "${TEST_HOME}")
        # Commands call their tools through PATH; activation snippets use the replaced store paths.
        env = os.environ | {"TEST_HOME": str(self.home), "CALL_LOG": str(self.log), "DRY_RUN_CMD": "",
                            "PATH": f"{self.tools}:{os.environ['PATH']}"} | overrides
        return subprocess.run(["bash", "-euo", "pipefail", "-c", script, name, *args], env=env,
                              capture_output=True, text=True)

    def place_github_key(self):
        key = self.home / ".ssh/id_github"
        key.parent.mkdir(parents=True, exist_ok=True)
        key.write_text("fake-key")

    def test_dry_run_has_no_side_effects(self):
        for name, args, env in [("clone", ["--dry-run"], {}), ("secrets", [], {"DRY_RUN_CMD": "echo"})]:
            with self.subTest(name=name):
                result = self.run_activation(name, *args, **env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse(self.home.exists())
                self.assertFalse(self.log.exists())

    def test_clone_without_key_fails_before_git(self):
        result = self.run_activation("clone")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("id_github", result.stderr)
        self.assertFalse(self.log.exists())
        self.assertFalse((self.home / "config").exists())

    def test_clone_failure_can_retry_and_existing_checkout_is_untouched(self):
        self.place_github_key()
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
        self.place_github_key()
        (self.home / "config").mkdir(parents=True)
        marker = self.home / "config" / "user-file"
        marker.write_text("keep")
        self.assertNotEqual(self.run_activation("clone").returncode, 0)
        self.assertEqual(marker.read_text(), "keep")
        self.assertFalse(self.log.exists())

    def place_age_key(self):
        age = self.home / ".config/sops/age/keys.txt"
        age.parent.mkdir(parents=True, exist_ok=True)
        age.write_text("fake-age-key")

    @property
    def key(self):
        return self.home / ".ssh/id_github"

    @property
    def state(self):
        return self.home / ".local/state/flake-secrets/managed"

    def records(self):
        if not self.state.exists():
            return {}
        return {path: digest for digest, path in
                (line.split("\t") for line in self.state.read_text().splitlines())}

    @staticmethod
    def digest(text):
        return hashlib.sha256((text + "\n").encode()).hexdigest()

    def update(self, secret="v2", *args, **env):
        return self.run_activation("update", *args, FAKE_SECRET=secret, **env)

    def test_activation_records_the_files_it_places(self):
        self.place_age_key()
        self.assertEqual(self.run_activation("secrets", FAKE_SECRET="v1").returncode, 0)
        self.assertEqual(self.key.read_text(), "v1\n")
        self.assertEqual(self.records(), {str(self.key): self.digest("v1")})

    def test_activation_does_not_record_existing_files(self):
        self.place_age_key()
        self.key.parent.mkdir(parents=True)
        self.key.write_text("manual\n")
        self.assertEqual(self.run_activation("secrets").returncode, 0)
        self.assertEqual(self.key.read_text(), "manual\n")
        self.assertEqual(self.records(), {})

    def test_update_replaces_a_managed_file(self):
        self.place_age_key()
        self.run_activation("secrets", FAKE_SECRET="v1")
        result = self.update("v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.key.read_text(), "v2\n")
        self.assertEqual(self.key.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.records(), {str(self.key): self.digest("v2")})
        self.assertEqual(list(self.key.parent.glob("id_github.*")), [])

    def test_update_places_a_missing_file(self):
        self.place_age_key()
        result = self.update("v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.key.read_text(), "v2\n")
        self.assertEqual(self.records(), {str(self.key): self.digest("v2")})

    def test_update_leaves_an_unchanged_file_alone(self):
        self.place_age_key()
        self.run_activation("secrets", FAKE_SECRET="v2")
        before = self.state.read_text()
        result = self.update("v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.key.read_text(), "v2\n")
        self.assertEqual(self.state.read_text(), before)

    def test_update_keeps_a_hand_edited_file(self):
        self.place_age_key()
        self.run_activation("secrets", FAKE_SECRET="v1")
        self.key.write_text("manual\n")
        result = self.update("v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.key.read_text(), "manual\n")
        self.assertIn("変更されている", result.stderr)
        self.assertEqual(self.records(), {str(self.key): self.digest("v1")})

    def test_update_records_a_file_already_matching(self):
        self.place_age_key()
        self.run_activation("secrets", FAKE_SECRET="v1")
        self.key.write_text("v2\n")
        self.assertEqual(self.update("v2").returncode, 0)
        self.assertEqual(self.records(), {str(self.key): self.digest("v2")})

    def test_update_adopts_an_unrecorded_identical_file(self):
        self.place_age_key()
        self.key.parent.mkdir(parents=True)
        self.key.write_text("v2\n")
        self.assertEqual(self.update("v2").returncode, 0)
        self.assertEqual(self.records(), {str(self.key): self.digest("v2")})

    def test_update_ignores_an_unrecorded_different_file(self):
        self.place_age_key()
        self.key.parent.mkdir(parents=True)
        self.key.write_text("manual\n")
        result = self.update("v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.key.read_text(), "manual\n")
        self.assertEqual(self.records(), {})

    def test_update_ignores_a_symlink(self):
        self.place_age_key()
        target = self.root / "elsewhere"
        target.write_text("v1\n")
        self.key.parent.mkdir(parents=True)
        self.key.symlink_to(target)
        result = self.update("v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.key.is_symlink())
        self.assertEqual(target.read_text(), "v1\n")

    def write_undeclared(self, name, content, recorded):
        path = self.home / ".ssh" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if content is not None:
            path.write_text(content)
        self.state.parent.mkdir(parents=True, exist_ok=True)
        with self.state.open("a") as state:
            state.write(f"{self.digest(recorded)}\t{path}\n")
        return path

    def test_update_removes_unchanged_undeclared_files_only(self):
        self.place_age_key()
        stale = self.write_undeclared("id_old", "old\n", "old")
        edited = self.write_undeclared("id_edited", "edited\n", "original")
        gone = self.write_undeclared("id_gone", None, "gone")
        result = self.update("v2")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(stale.exists())
        self.assertEqual(edited.read_text(), "edited\n")
        self.assertEqual(self.records(), {str(self.key): self.digest("v2")})
        self.assertNotIn(str(gone), self.records())

    def test_update_dry_run_changes_nothing(self):
        self.place_age_key()
        self.run_activation("secrets", FAKE_SECRET="v1")
        stale = self.write_undeclared("id_old", "old\n", "old")
        before = self.state.read_text()
        result = self.update("v2", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("更新", result.stdout)
        self.assertEqual(self.key.read_text(), "v1\n")
        self.assertTrue(stale.exists())
        self.assertEqual(self.state.read_text(), before)

    def test_update_decryption_failure_changes_nothing(self):
        self.place_age_key()
        self.run_activation("secrets", FAKE_SECRET="v1")
        before = self.state.read_text()
        result = self.update("v2", FAIL_TOOL="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.key.read_text(), "v1\n")
        self.assertEqual(self.state.read_text(), before)
        self.assertEqual(list(self.key.parent.glob("id_github.*")), [])

    def test_update_without_age_key_fails(self):
        result = self.update("v2")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.key.exists())

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
