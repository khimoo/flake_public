"""Test the lock-only policy used by the privileged update PR job."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/ci/check-lock-update.py"
HASH_OLD = "sha256-" + "A" * 43 + "="
HASH_NEW = "sha256-" + "E" * 43 + "="


class LockUpdate(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.before = Path(temp.name) / "before.lock"
        self.after = Path(temp.name) / "after.lock"
        github = {"type": "github", "owner": "example", "repo": "package"}
        file = {"type": "file", "url": "https://example.com/source.tar.gz"}
        self.base = {"version": 7, "root": "root", "nodes": {
            "root": {"inputs": {"package": "package", "file": "file"}},
            "package": {
                "original": {**github, "ref": "main"},
                "locked": {**github, "rev": "1" * 40, "narHash": HASH_OLD, "lastModified": 1},
            },
            "file": {"flake": False, "original": file, "locked": {**file, "narHash": HASH_OLD}},
        }}
        self.before.write_text(json.dumps(self.base))
        self.updated = copy.deepcopy(self.base)

    def check(self, raw=None):
        self.after.write_text(json.dumps(self.updated) if raw is None else raw)
        return subprocess.run([sys.executable, str(SCRIPT), str(self.before), str(self.after)],
                              capture_output=True, text=True)

    def test_allows_pin_updates_and_summarizes_only_changed_nodes(self):
        self.updated["nodes"]["package"]["locked"].update(
            rev="2" * 40, narHash=HASH_NEW, lastModified=2)
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        for value in ("package", "1" * 40, "2" * 40, HASH_OLD, HASH_NEW):
            self.assertIn(value, result.stdout)
        self.assertNotIn("`file`", result.stdout)

    def test_allows_hash_only_file_update(self):
        self.updated["nodes"]["file"]["locked"]["narHash"] = HASH_NEW
        result = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("`file`", result.stdout)
        self.assertIn(HASH_NEW, result.stdout)

    def test_rejects_nodes_edges_sources_and_non_pin_fields(self):
        cases = {
            "added node": lambda d: d["nodes"].update(extra={}),
            "removed node": lambda d: d["nodes"].pop("file"),
            "rerouted input": lambda d: d["nodes"]["root"]["inputs"].update(package="file"),
            "added input alias": lambda d: d["nodes"]["root"]["inputs"].update(alias="package"),
            "locked owner": lambda d: d["nodes"]["package"]["locked"].update(owner="other"),
            "original repo": lambda d: d["nodes"]["package"]["original"].update(repo="different"),
            "original ref": lambda d: d["nodes"]["package"]["original"].update(ref="other"),
            "locked URL": lambda d: d["nodes"]["file"]["locked"].update(url="https://other.example/"),
            "pin added": lambda d: d["nodes"]["file"]["locked"].update(rev="2" * 40),
            "invalid rev": lambda d: d["nodes"]["package"]["locked"].update(rev="not-a-revision"),
            "invalid hash": lambda d: d["nodes"]["file"]["locked"].update(narHash="not-a-hash"),
            "invalid timestamp": lambda d: d["nodes"]["package"]["locked"].update(lastModified=True),
        }
        for name, mutate in cases.items():
            with self.subTest(name=name):
                self.updated = copy.deepcopy(self.base)
                mutate(self.updated)
                result = self.check()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("lock update rejected:", result.stderr)
                self.assertEqual(result.stdout, "")

    def test_rejects_duplicate_json_keys(self):
        raw = '{"root":"different",' + json.dumps(self.updated)[1:]
        result = self.check(raw)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate", result.stderr)


if __name__ == "__main__":
    unittest.main()
