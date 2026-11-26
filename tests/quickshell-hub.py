import importlib.util
import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(
    os.environ.get(
        "HUB_VAULT_SCRIPT",
        pathlib.Path(__file__).resolve().parent.parent
        / "modules/home-manager/gui/quickshell/hub-vault.py",
    )
)


def load_module():
    spec = importlib.util.spec_from_file_location("hub_vault", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class HubVaultTest(unittest.TestCase):
    def test_parse_rbw_list(self):
        mod = load_module()
        raw = "id-1\tGitHub\talice@example.com\tDev\nid-2\tServer\troot\t\n\n"
        items = mod.parse_rbw_list(raw)
        self.assertEqual(
            items,
            [
                {"id": "id-1", "name": "GitHub", "user": "alice@example.com", "folder": "Dev"},
                {"id": "id-2", "name": "Server", "user": "root", "folder": ""},
            ],
        )

    def test_list_locked_returns_json_without_calling_list(self):
        with tempfile.TemporaryDirectory() as tmp:
            bindir = pathlib.Path(tmp) / "bin"
            bindir.mkdir()
            rbw = bindir / "rbw"
            rbw.write_text(
                "#!/bin/sh\n"
                "if [ \"$1\" = config ]; then echo '{}'; exit 0; fi\n"
                "if [ \"$1\" = unlocked ]; then echo 'locked' >&2; exit 1; fi\n"
                "echo 'SHOULD_NOT_RUN' >&2; exit 99\n",
                encoding="utf-8",
            )
            rbw.chmod(rbw.stat().st_mode | stat.S_IEXEC)
            env = dict(os.environ, PATH=f"{bindir}:{os.environ.get('PATH', '')}")
            res = subprocess.run(
                [sys.executable, str(SCRIPT), "list"],
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(res.returncode, 0)
            payload = json.loads(res.stdout)
            self.assertFalse(payload["ok"])
            self.assertIn("ロック中", payload["error"])

    def test_list_unlocked_returns_items(self):
        with tempfile.TemporaryDirectory() as tmp:
            bindir = pathlib.Path(tmp) / "bin"
            bindir.mkdir()
            rbw = bindir / "rbw"
            rbw.write_text(
                "#!/bin/sh\n"
                "if [ \"$1\" = config ]; then echo '{}'; exit 0; fi\n"
                "if [ \"$1\" = unlocked ]; then exit 0; fi\n"
                "printf 'id-1\\tGitHub\\talice\\tWork\\n'\n",
                encoding="utf-8",
            )
            rbw.chmod(rbw.stat().st_mode | stat.S_IEXEC)
            env = dict(os.environ, PATH=f"{bindir}:{os.environ.get('PATH', '')}")
            res = subprocess.run(
                [sys.executable, str(SCRIPT), "list"],
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(res.returncode, 0)
            payload = json.loads(res.stdout)
            self.assertTrue(payload["ok"])
            self.assertEqual(payload["items"][0]["name"], "GitHub")


if __name__ == "__main__":
    unittest.main()
