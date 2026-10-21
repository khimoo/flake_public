"""Run generated activation snippets and commands with fake network/secret tools in a temp tree."""
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
        for name in ("mv", "chmod"):
            real_tool = shutil.which(name)
            self.assertIsNotNone(real_tool)
            path = self.tools / name
            path.write_text(
                f"#!{sys.executable}\nimport os, sys\n"
                f"if os.environ.get('FAIL_{name.upper()}'): raise SystemExit(19)\n"
                f"os.execv({real_tool!r}, [{name!r}, *sys.argv[1:]])\n"
            )
            path.chmod(0o755)
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

    def test_clone_move_failure_cleans_up(self):
        self.place_github_key()
        result = self.run_activation("clone", FAIL_MV="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("failed to move checkout", result.stderr)
        self.assertFalse((self.home / "config").exists())
        self.assertEqual(list(self.home.glob(".private-clone.*")), [])

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
        return self.home / ".local/state/flake-secrets/placed"

    def records(self):
        return set(self.state.read_text().splitlines()) if self.state.exists() else set()

    def sync(self, secret="v2", **env):
        return self.run_activation("secrets", FAKE_SECRET=secret, **env)

    def assert_no_temps(self):
        self.assertEqual(list(self.key.parent.glob("id_github.*")), [])
        self.assertEqual(list(self.state.parent.glob("placed.*")), [])

    def test_activation_places_and_records_files(self):
        self.place_age_key()
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.key.read_text(), "v2\n")
        self.assertEqual(self.key.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.records(), {str(self.key)})
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o600)
        self.assert_no_temps()

    def test_activation_replaces_existing_files_and_corrects_mode(self):
        self.place_age_key()
        self.key.parent.mkdir(parents=True)
        self.key.write_text("manual\n")
        self.key.chmod(0o644)
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.key.read_text(), "v2\n")
        self.assertEqual(self.key.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.records(), {str(self.key)})

    def test_activation_preserves_identical_file_but_corrects_mode(self):
        self.place_age_key()
        self.assertEqual(self.sync().returncode, 0)
        self.key.chmod(0o644)
        before = self.key.stat()
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        after = self.key.stat()
        self.assertEqual((after.st_ino, after.st_mtime_ns), (before.st_ino, before.st_mtime_ns))
        self.assertEqual(after.st_mode & 0o777, 0o600)

    def test_activation_restores_hand_edited_file(self):
        self.place_age_key()
        self.assertEqual(self.sync("v1").returncode, 0)
        self.key.write_text("manual\n")
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.key.read_text(), "v2\n")

    def test_activation_leaves_non_regular_destinations_and_warns(self):
        self.place_age_key()
        self.key.parent.mkdir(parents=True)
        target = self.root / "target"
        target.write_text("keep\n")
        for kind in ("symlink", "dangling", "directory", "fifo"):
            with self.subTest(kind=kind):
                if kind in ("symlink", "dangling"):
                    self.key.symlink_to(target if kind == "symlink" else self.root / "missing")
                elif kind == "directory":
                    self.key.mkdir()
                else:
                    os.mkfifo(self.key)
                result = self.sync()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("通常のファイルでない", result.stderr)
                self.assertTrue(self.key.exists() or self.key.is_symlink())
                self.assertEqual(target.read_text(), "keep\n")
                self.assertEqual(self.records(), set())
                self.assertFalse(self.log.exists())
                if kind == "directory":
                    self.key.rmdir()
                else:
                    self.key.unlink()

    def record_undeclared(self, name):
        path = self.home / ".ssh" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        self.state.parent.mkdir(parents=True, exist_ok=True)
        with self.state.open("a") as state:
            state.write(f"{path}\n")
        return path

    def test_activation_removes_undeclared_files_even_if_edited(self):
        self.place_age_key()
        stale = self.record_undeclared("old key with spaces")
        stale.write_text("manually edited\n")
        gone = self.record_undeclared("gone")
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(stale.exists())
        self.assertFalse(gone.exists())
        self.assertEqual(self.records(), {str(self.key)})

    def test_activation_does_not_remove_undeclared_non_regular_files(self):
        self.place_age_key()
        target = self.root / "target"
        target.write_text("keep\n")
        link = self.record_undeclared("old_link")
        link.symlink_to(target)
        dangling = self.record_undeclared("old_dangling")
        dangling.symlink_to(self.root / "missing")
        directory = self.record_undeclared("old_directory")
        directory.mkdir()
        fifo = self.record_undeclared("old_fifo")
        os.mkfifo(fifo)
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("削除せず記録から外す", result.stderr)
        self.assertTrue(link.is_symlink())
        self.assertTrue(dangling.is_symlink())
        self.assertTrue(directory.is_dir())
        self.assertTrue(fifo.exists())
        self.assertEqual(target.read_text(), "keep\n")
        self.assertEqual(self.records(), {str(self.key)})

    def test_dry_run_reports_sync_and_removal_without_decryption(self):
        self.place_age_key()
        self.assertEqual(self.sync("v1").returncode, 0)
        stale = self.record_undeclared("old")
        stale.write_text("old\n")
        before = self.state.read_text()
        calls = self.log.read_text()
        (self.home / ".config/sops/age/keys.txt").unlink()
        result = self.sync(DRY_RUN_CMD="echo")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(str(self.key), result.stderr)
        self.assertIn(f"{stale}: 宣言から外れたので削除予定", result.stderr)
        self.assertEqual(self.key.read_text(), "v1\n")
        self.assertTrue(stale.exists())
        self.assertEqual(self.state.read_text(), before)
        self.assertEqual(self.log.read_text(), calls)
        self.assert_no_temps()

    def test_failure_preserves_destination_and_cleans_temps(self):
        self.place_age_key()
        self.assertEqual(self.sync("v1").returncode, 0)
        before = self.state.read_text()
        for failure in ("FAIL_TOOL", "FAIL_CHMOD", "FAIL_MV"):
            with self.subTest(failure=failure):
                result = self.sync(**{failure: "1"})
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.key.read_text(), "v1\n")
                self.assertEqual(self.state.read_text(), before)
                self.assert_no_temps()

    def test_without_age_key_fails_before_decryption(self):
        result = self.sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("age 復号鍵", result.stderr)
        self.assertFalse(self.key.exists())
        self.assertFalse(self.log.exists())
        self.assertFalse(self.state.exists())

    def test_key_failure_does_not_leave_empty_destination_and_can_retry(self):
        self.place_age_key()
        self.assertNotEqual(self.sync(FAIL_TOOL="1").returncode, 0)
        self.assertFalse(self.key.exists())
        self.assert_no_temps()
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.key.read_text(), "v2\n")

    def test_empty_declarations_remove_records_without_age_key(self):
        stale = self.record_undeclared("old")
        stale.write_text("old\n")
        result = self.run_activation("emptySecrets")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(stale.exists())
        self.assertEqual(self.records(), set())
        self.assertFalse(self.log.exists())
        self.assert_no_temps()

    def test_empty_declarations_without_records_do_nothing(self):
        result = self.run_activation("emptySecrets")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.home.exists())
        self.assertFalse(self.log.exists())

    def test_empty_declarations_dry_run_preserves_recorded_files(self):
        stale = self.record_undeclared("old")
        stale.write_text("old\n")
        before = self.state.read_text()
        result = self.run_activation("emptySecrets", DRY_RUN_CMD="echo")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("削除予定", result.stderr)
        self.assertEqual(stale.read_text(), "old\n")
        self.assertEqual(self.state.read_text(), before)
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
