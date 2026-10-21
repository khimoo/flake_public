"""Run agent-sync against a temporary agent configuration checkout and home."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(sys.argv.pop(1)).read_text()
MARKER = "# agent-sync が生成する。手で編集しない。"


class AgentSync(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name) / "home"
        self.root = self.home / "config"
        (self.root / "claude/profiles").mkdir(parents=True)
        (self.root / "codex").mkdir(parents=True)
        self.bin = self.home / ".local/share/agent-launchers/bin"
        self.settings = self.home / ".claude/settings.json"

    def run_sync(self, *args):
        script = SCRIPT.replace("@test-home@", str(self.home))
        return subprocess.run(["bash", "-euo", "pipefail", "-c", script, "agent-sync", *args],
                              capture_output=True, text=True)

    def write_source(self, data):
        (self.root / "claude/settings.json").write_text(json.dumps(data))

    def test_profiles_become_launchers_and_codex_links(self):
        (self.root / "claude/profiles/opus.json").write_text("{}")
        (self.root / "codex/astra.config.toml").write_text("")
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        claude = self.bin / "claude-opus"
        self.assertIn(f"--settings {self.root}/claude/profiles/opus.json", claude.read_text())
        self.assertTrue(os.access(claude, os.X_OK))
        self.assertIn("--profile astra", (self.bin / "codex-astra").read_text())
        link = self.home / ".codex/astra.config.toml"
        self.assertEqual(os.readlink(link), str(self.root / "codex/astra.config.toml"))

    def test_unsafe_profile_names_are_skipped(self):
        (self.root / "claude/profiles/opus; rm -rf x.json").write_text("{}")
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.bin.exists() and any(self.bin.iterdir()))
        self.assertIn("飛ばす", result.stderr)

    def test_removed_profiles_are_cleaned_up_but_foreign_files_stay(self):
        (self.root / "claude/profiles/opus.json").write_text("{}")
        (self.root / "codex/astra.config.toml").write_text("")
        self.assertEqual(self.run_sync().returncode, 0)
        (self.bin / "mine").write_text("#!/bin/sh\necho hi\n")
        manual = self.home / ".codex/manual.config.toml"
        manual.write_text("keep")
        (self.root / "claude/profiles/opus.json").unlink()
        (self.root / "codex/astra.config.toml").unlink()
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.bin / "claude-opus").exists())
        self.assertFalse((self.bin / "codex-astra").exists())
        self.assertFalse((self.home / ".codex/astra.config.toml").is_symlink())
        self.assertTrue((self.bin / "mine").exists())
        self.assertEqual(manual.read_text(), "keep")

    def test_settings_merge_keeps_unmanaged_keys_and_drops_removed_ones(self):
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text(json.dumps({"theme": "dark", "hooks": {"old": 1}}))
        self.write_source({"hooks": {"new": 1}, "outputStyle": "x"})
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        # hooks.old は設定 repo が置いたものではないので残る。
        self.assertEqual(json.loads(self.settings.read_text()),
                         {"theme": "dark", "hooks": {"old": 1, "new": 1}, "outputStyle": "x"})
        self.write_source({"hooks": {}})
        self.assertEqual(self.run_sync().returncode, 0)
        self.assertEqual(json.loads(self.settings.read_text()), {"theme": "dark", "hooks": {"old": 1}})

    def test_user_added_entries_under_managed_objects_stay(self):
        self.write_source({"enabledPlugins": {"a@m": True}, "env": {"X": "1"}})
        self.assertEqual(self.run_sync().returncode, 0)
        data = json.loads(self.settings.read_text())
        data["enabledPlugins"]["trial@m"] = True
        self.settings.write_text(json.dumps(data))
        self.write_source({"enabledPlugins": {"b@m": True}, "env": {"X": "1"}})
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.settings.read_text()),
                         {"enabledPlugins": {"trial@m": True, "b@m": True}, "env": {"X": "1"}})

    def test_object_source_replaces_a_scalar_value(self):
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text(json.dumps({"env": "broken"}))
        self.write_source({"env": {"X": "1"}})
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.settings.read_text()), {"env": {"X": "1"}})

    def test_settings_changed_by_the_app_are_overwritten_with_a_warning(self):
        self.write_source({"outputStyle": "x"})
        self.assertEqual(self.run_sync().returncode, 0)
        data = json.loads(self.settings.read_text())
        data["outputStyle"] = "changed-in-app"
        self.settings.write_text(json.dumps(data))
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("outputStyle", result.stderr)
        self.assertEqual(json.loads(self.settings.read_text())["outputStyle"], "x")

    def test_unchanged_settings_are_not_rewritten(self):
        self.write_source({"outputStyle": "x"})
        self.assertEqual(self.run_sync().returncode, 0)
        before = self.settings.stat().st_mtime_ns
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("反映する", result.stdout)
        self.assertEqual(self.settings.stat().st_mtime_ns, before)

    def test_broken_source_leaves_settings_alone(self):
        self.settings.parent.mkdir(parents=True)
        self.settings.write_text('{"theme": "dark"}')
        (self.root / "claude/settings.json").write_text("{broken")
        result = self.run_sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.settings.read_text(), '{"theme": "dark"}')

    def test_dry_run_changes_nothing(self):
        (self.root / "claude/profiles/opus.json").write_text("{}")
        (self.root / "codex/astra.config.toml").write_text("")
        self.write_source({"outputStyle": "x"})
        result = self.run_sync("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("claude-opus", result.stdout)
        self.assertFalse(self.bin.exists())
        self.assertFalse(self.settings.exists())
        self.assertFalse((self.home / ".codex").exists())
        self.assertFalse((self.home / ".local/state").exists())

    def test_missing_checkout_is_not_an_error(self):
        for path in sorted(self.root.rglob("*"), reverse=True):
            path.rmdir()
        self.root.rmdir()
        result = self.run_sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("clone-repos", result.stderr)
        self.assertFalse(self.bin.exists())


if __name__ == "__main__":
    unittest.main()
