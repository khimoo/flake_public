"""Run mc-setup-hooks against a temporary prismlauncher.cfg and a fake pgrep."""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(sys.argv.pop(1)).resolve()
PRE = 'PreLaunchCommand=mc-check \\"$INST_ID\\"'
POST = 'PostExitCommand=mc-backup \\"$INST_ID\\"'


class SetupHooks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.cfg = root / "PrismLauncher" / "prismlauncher.cfg"
        bin_dir = root / "bin"
        bin_dir.mkdir()
        pgrep = bin_dir / "pgrep"
        pgrep.write_text('#!/bin/sh\n[ -n "$PRISM_RUNNING" ]\n')
        pgrep.chmod(0o755)
        self.env = os.environ | {"MC_PRISM_CFG": str(self.cfg), "PATH": f"{bin_dir}:{os.environ['PATH']}"}

    def run_script(self, *args, **env):
        return subprocess.run(["bash", "-euo", "pipefail", str(SCRIPT), *args],
                              env=self.env | env, capture_output=True, text=True)

    def write(self, text):
        self.cfg.parent.mkdir(parents=True, exist_ok=True)
        self.cfg.write_text(text)

    def test_replaces_existing_values_and_keeps_other_lines(self):
        self.write("[General]\nLanguage=ja\nPreLaunchCommand=old\nPostExitCommand=old\n\n[Other]\nPreLaunchCommand=keep\n")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.cfg.read_text(),
                         f"[General]\nLanguage=ja\n{PRE}\n{POST}\n\n[Other]\nPreLaunchCommand=keep\n")

    def test_adds_missing_keys_to_general(self):
        self.write("[General]\nLanguage=ja\n[Other]\nx=1\n")
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.cfg.read_text(), f"[General]\nLanguage=ja\n{PRE}\n{POST}\n[Other]\nx=1\n")

    def test_creates_the_file(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.cfg.read_text(), f"[General]\n{PRE}\n{POST}\n")

    def test_is_idempotent(self):
        self.assertEqual(self.run_script().returncode, 0)
        first = self.cfg.read_text()
        self.assertEqual(self.run_script().returncode, 0)
        self.assertEqual(self.cfg.read_text(), first)

    def test_dry_run_changes_nothing(self):
        self.write("[General]\nPreLaunchCommand=old\n")
        result = self.run_script("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(PRE, result.stdout)
        self.assertEqual(self.cfg.read_text(), "[General]\nPreLaunchCommand=old\n")

    def test_refuses_while_prism_runs(self):
        self.write("[General]\n")
        result = self.run_script(PRISM_RUNNING="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.cfg.read_text(), "[General]\n")
        self.assertEqual(list(self.cfg.parent.glob("*.cfg.*")), [])


if __name__ == "__main__":
    unittest.main()
