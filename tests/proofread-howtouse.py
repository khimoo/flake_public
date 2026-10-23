"""Run the howtouse proofreading hook against a temporary repository and a fake rewrite.py."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(sys.argv.pop(1)).resolve()
FAKE_REWRITE = """\
import json, os, sys
from pathlib import Path
names = sys.argv[2:]
Path(os.environ["CALLS"]).write_text(json.dumps(names))
if os.environ.get("FAKE_FAIL"):
    sys.exit(1)
diff = ""
if not os.environ.get("FAKE_UNCHANGED"):
    for name in names:
        Path(name).write_text(Path(name).read_text() + "校正済み。\\n")
    diff = "".join(f"+++ b/{name}\\n" for name in names)
json.dump({"diff": diff, "skipped": [], "originals": {}, "comments": [], "proposals": []}, sys.stdout)
"""


class ProofreadHowtouse(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.repo = root / "repo"
        hook = self.repo / ".agents/hooks/proofread-howtouse.py"
        hook.parent.mkdir(parents=True)
        shutil.copy(SCRIPT, hook)
        self.hook = hook
        skill = root / "skill"
        (skill / "scripts").mkdir(parents=True)
        (skill / "scripts/rewrite.py").write_text(FAKE_REWRITE)
        self.calls_file = root / "calls.json"
        self.env = os.environ | {
            "HOME": str(root),
            "GEMINI_PROOFREAD_SKILL_DIR": str(skill),
            "CALLS": str(self.calls_file),
            "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
            "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com",
        }
        self.env.pop("GEMINI_PROOFREAD", None)
        self.git("init", "-q")
        self.write("docs/howtouse/a.md", "使い方。\n")
        self.write("README.md", "readme\n")
        self.git("add", ".")
        self.git("commit", "-qm", "init")

    def git(self, *args, cwd=None):
        subprocess.run(["git", *args], cwd=cwd or self.repo, env=self.env, check=True)

    def write(self, name, text):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def run_hook(self, command, cwd=None, **env):
        payload = {"tool_name": "Bash", "tool_input": {"command": command}, "cwd": str(cwd or self.repo)}
        return subprocess.run([sys.executable, str(self.hook)], input=json.dumps(payload),
                              env=self.env | env, capture_output=True, text=True)

    def calls(self):
        return json.loads(self.calls_file.read_text()) if self.calls_file.exists() else None

    def stage_doc_change(self):
        self.write("docs/howtouse/a.md", "使い方を直した。\n")
        self.write("README.md", "readme changed\n")
        self.git("add", ".")

    def test_proofreads_staged_howtouse_docs_and_blocks_the_commit(self):
        self.stage_doc_change()
        result = self.run_hook("git commit -m 'docs: x'")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertEqual(self.calls(), ["docs/howtouse/a.md"])
        self.assertEqual((self.repo / "docs/howtouse/a.md").read_text(), "使い方を直した。\n校正済み。\n")
        self.assertIn("GEMINI_PROOFREAD=0", result.stderr)

    def test_lets_the_commit_through_with_the_skip_mark(self):
        self.stage_doc_change()
        result = self.run_hook("GEMINI_PROOFREAD=0 git commit -m 'docs: x'")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(self.calls())

    def test_ignores_commits_without_howtouse_docs(self):
        self.write("README.md", "readme changed\n")
        self.git("add", ".")
        self.assertEqual(self.run_hook("git commit -m x").returncode, 0)
        self.assertIsNone(self.calls())

    def test_ignores_commands_other_than_git_commit(self):
        self.stage_doc_change()
        for command in ["git status", "git commit-tree HEAD^{tree}", "git log --grep commit"]:
            self.assertEqual(self.run_hook(command).returncode, 0, command)
        self.assertIsNone(self.calls())

    def test_lets_the_commit_through_when_proofreading_changes_nothing(self):
        self.stage_doc_change()
        result = self.run_hook("git commit -m x", FAKE_UNCHANGED="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["docs/howtouse/a.md"])

    def test_blocks_and_explains_when_proofreading_fails(self):
        self.stage_doc_change()
        result = self.run_hook("git commit -m x", FAKE_FAIL="1")
        self.assertEqual(result.returncode, 2)
        self.assertIn("校正できなかった", result.stderr)
        self.assertEqual((self.repo / "docs/howtouse/a.md").read_text(), "使い方を直した。\n")

    def test_does_nothing_without_the_skill(self):
        self.stage_doc_change()
        result = self.run_hook("git commit -m x", GEMINI_PROOFREAD_SKILL_DIR=str(self.repo / "missing"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(self.calls())

    def test_includes_unstaged_docs_for_commit_all(self):
        self.write("docs/howtouse/a.md", "使い方を直した。\n")
        self.assertEqual(self.run_hook("git commit -am x").returncode, 2)
        self.assertEqual(self.calls(), ["docs/howtouse/a.md"])

    def test_finds_git_commit_after_global_options(self):
        self.stage_doc_change()
        self.assertEqual(self.run_hook(f"cd /tmp && git -C {self.repo} --no-pager commit -m x").returncode, 2)

    def test_ignores_commits_in_another_repository(self):
        other = Path(self.temp.name) / "other"
        other.mkdir()
        self.git("init", "-q", cwd=other)
        self.stage_doc_change()
        self.assertEqual(self.run_hook("git commit -m x", cwd=other).returncode, 0)
        self.assertIsNone(self.calls())


if __name__ == "__main__":
    unittest.main()
