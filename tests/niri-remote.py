import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(sys.argv.pop(1)).resolve()


class RemoteSessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.log = self.root / "calls"
        systemctl = self.root / "systemctl"
        systemctl.write_text("#!" + shutil.which("bash") + """
printf '%s\\n' "$*" >> "$CALL_LOG"
case "$*" in
  '--user show -p ActiveState --value niri.service') echo "$LOCAL_STATE" ;;
  '--user start niri-headless.service') exit "${HEADLESS_EXIT:-0}" ;;
esac
""")
        systemctl.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": str(self.root) + os.pathsep + os.environ["PATH"],
            "MOCK_SYSTEMCTL": str(systemctl),
            "CALL_LOG": str(self.log),
            "LOCAL_STATE": "inactive",
            "XDG_RUNTIME_DIR": str(self.root),
        }

    def run_helper(self, command):
        return subprocess.run(
            [
                "bash", "-euo", "pipefail", "-c",
                'systemctl() { "$MOCK_SYSTEMCTL" "$@"; }; source "$@"',
                "remote-niri", str(SCRIPT), command,
            ],
            env=self.env, capture_output=True, text=True,
        )

    def calls(self):
        return self.log.read_text().splitlines()

    def test_start_waits_for_compositor_before_starting_streaming(self):
        self.assertEqual(self.run_helper("start").returncode, 0)
        self.assertEqual(self.calls()[1:], [
            "--user start niri-headless.service",
            "--user start sunshine.service",
        ])

    def test_failed_compositor_start_does_not_start_streaming(self):
        self.env["HEADLESS_EXIT"] = "1"
        self.assertNotEqual(self.run_helper("start").returncode, 0)
        self.assertNotIn("--user start sunshine.service", self.calls())

    def test_start_and_stop_preserve_local_sessions(self):
        for state in ["active", "activating", "deactivating", "reloading"]:
            for command in ["start", "stop"]:
                with self.subTest(state=state, command=command):
                    self.env["LOCAL_STATE"] = state
                    self.log.write_text("")
                    result = self.run_helper(command)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("local niri session", result.stderr)
                    self.assertEqual(self.calls(), ["--user show -p ActiveState --value niri.service"])

    def test_stop_ends_streaming_and_headless_session(self):
        self.assertEqual(self.run_helper("stop").returncode, 0)
        self.assertEqual(self.calls()[-1], "--user stop sunshine.service niri-headless.service")


if __name__ == "__main__":
    unittest.main()
