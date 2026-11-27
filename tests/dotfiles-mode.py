import importlib.util
import io
import json
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest import mock

SCRIPT_PATH = pathlib.Path(
    os.environ.get(
        "DOTFILES_MODE_SCRIPT",
        str(pathlib.Path(__file__).resolve().parent.parent / "modules/home-manager/dev/dotfiles-mode.py"),
    )
)
SPEC = importlib.util.spec_from_file_location("dotfiles_mode", SCRIPT_PATH)
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


def make_env(tmp):
    root = pathlib.Path(tmp)
    store_root = root / "store"
    dev_root = root / "checkout"
    state_home = root / "state"
    state_dir = state_home / "dotfiles-mode"
    links_dir = state_dir / "links"

    (store_root / "niri").mkdir(parents=True)
    (store_root / "niri" / "config.kdl").write_text("// store niri\n", encoding="utf-8")
    (store_root / "quickshell").mkdir(parents=True)
    (store_root / "quickshell" / "shell.qml").write_text("// store qs\n", encoding="utf-8")
    (store_root / "kanshi").mkdir(parents=True)
    (store_root / "kanshi" / "config").write_text("# store kanshi\n", encoding="utf-8")
    (store_root / "kitty").mkdir(parents=True)
    (store_root / "kitty" / "kitty.conf").write_text("# store kitty\n", encoding="utf-8")
    (store_root / "nvim").mkdir(parents=True)
    (store_root / "nvim" / "init.lua").write_text("-- store nvim\n", encoding="utf-8")
    (store_root / "nvim" / "lazy-lock.json").write_text('{"store": true}\n', encoding="utf-8")

    (dev_root / "niri").mkdir(parents=True)
    (dev_root / "niri" / "config.kdl").write_text("// dev niri\n", encoding="utf-8")
    (dev_root / "quickshell").mkdir(parents=True)
    (dev_root / "quickshell" / "shell.qml").write_text("// dev qs\n", encoding="utf-8")
    (dev_root / "kanshi").mkdir(parents=True)
    (dev_root / "kanshi" / "config").write_text("# dev kanshi\n", encoding="utf-8")
    (dev_root / "kitty").mkdir(parents=True)
    (dev_root / "kitty" / "kitty.conf").write_text("# dev kitty\n", encoding="utf-8")
    (dev_root / "nvim").mkdir(parents=True)
    (dev_root / "nvim" / "init.lua").write_text("-- dev nvim\n", encoding="utf-8")
    (dev_root / "nvim" / "lazy-lock.json").write_text('{"dev": true}\n', encoding="utf-8")

    manifest_path = root / "manifest.json"
    manifest = {
        "state_dir": str(state_dir),
        "links_dir": str(links_dir),
        "items": [
            {
                "name": "niri",
                "label": "Niri",
                "store": str(store_root / "niri" / "config.kdl"),
                "dev": str(dev_root / "niri" / "config.kdl"),
                "reload": "niri",
            },
            {
                "name": "quickshell",
                "label": "Hub",
                "store": str(store_root / "quickshell"),
                "dev": str(dev_root / "quickshell"),
                "reload": "quickshell",
            },
            {
                "name": "kanshi",
                "label": "kanshi",
                "store": str(store_root / "kanshi"),
                "dev": str(dev_root / "kanshi"),
                "reload": "kanshi",
            },
            {
                "name": "kitty",
                "label": "kitty",
                "store": str(store_root / "kitty" / "kitty.conf"),
                "dev": str(dev_root / "kitty" / "kitty.conf"),
                "reload": "kitty",
            },
            {
                "name": "nvim",
                "label": "nvim",
                "store": str(store_root / "nvim"),
                "dev": str(dev_root / "nvim"),
                "reload": "none",
            },
        ],
    }
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    return root, state_home, links_dir, manifest_path, manifest


class DotfilesModeTest(unittest.TestCase):
    def test_sync_store_sets_all_links_syncs_lockfile_and_cleans_stale(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, state_home, links_dir, manifest_path, manifest = make_env(tmp)
            links_dir.mkdir(parents=True)
            stale_link = links_dir / "obsolete"
            os.symlink("/tmp/old", stale_link)
            non_link = links_dir / "keep-file"
            non_link.write_text("user file", encoding="utf-8")
            (state_home / "dotfiles-mode" / "managed").write_text("obsolete\nkeep-file\n", encoding="utf-8")

            # First simulate niri currently in dev mode.
            os.symlink(manifest["items"][0]["dev"], links_dir / "niri")

            with mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_home)}):
                rc = MOD.main(["--manifest", str(manifest_path), "sync-store"])

            self.assertEqual(rc, 0)
            for item in manifest["items"]:
                self.assertEqual(os.readlink(links_dir / item["name"]), item["store"])
            self.assertFalse(os.path.lexists(stale_link))
            self.assertTrue(non_link.is_file())
            synced_lock = state_home / "nvim" / "lazy-lock.json"
            self.assertEqual(synced_lock.read_text(encoding="utf-8"), '{"store": true}\n')

    def test_sync_store_dry_run_makes_no_changes(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, state_home, links_dir, manifest_path, _ = make_env(tmp)
            with mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_home)}):
                rc = MOD.main(["--manifest", str(manifest_path), "sync-store", "--dry-run"])
            self.assertEqual(rc, 0)
            self.assertFalse(links_dir.exists())
            self.assertFalse((state_home / "nvim" / "lazy-lock.json").exists())

    def test_individual_toggle_only_changes_selected_item_and_reloads(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, state_home, links_dir, manifest_path, manifest = make_env(tmp)
            with mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_home)}):
                self.assertEqual(MOD.main(["--manifest", str(manifest_path), "sync-store"]), 0)

            calls = []

            def fake_run(argv):
                calls.append(list(argv))
                return subprocess.CompletedProcess(argv, 0, "", "")

            with (
                mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_home)}),
                mock.patch.object(MOD, "run_cmd", side_effect=fake_run),
                mock.patch.object(MOD.shutil, "which", return_value="/usr/bin/fake"),
            ):
                rc_on = MOD.main(["--manifest", str(manifest_path), "toggle", "niri", "--quiet"])
                self.assertEqual(rc_on, 0)
                self.assertEqual(os.readlink(links_dir / "niri"), manifest["items"][0]["dev"])
                self.assertEqual(os.readlink(links_dir / "kanshi"), manifest["items"][2]["store"])
                self.assertIn(["niri", "msg", "action", "load-config-file"], calls)

                buf = io.StringIO()
                with mock.patch("sys.stdout", buf):
                    self.assertEqual(MOD.main(["--manifest", str(manifest_path), "--status-json"]), 0)
                payload = json.loads(buf.getvalue())
                self.assertTrue(payload["any_dev"])
                by_name = {i["name"]: i for i in payload["items"]}
                self.assertTrue(by_name["niri"]["dev"])
                self.assertFalse(by_name["kanshi"]["dev"])

                rc_off = MOD.main(["--manifest", str(manifest_path), "toggle", "niri", "--quiet"])
                self.assertEqual(rc_off, 0)
                self.assertEqual(os.readlink(links_dir / "niri"), manifest["items"][0]["store"])

    def test_on_refuses_missing_checkout_target(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, state_home, links_dir, manifest_path, manifest = make_env(tmp)
            with mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_home)}):
                self.assertEqual(MOD.main(["--manifest", str(manifest_path), "sync-store"]), 0)
            os.unlink(manifest["items"][0]["dev"])

            with mock.patch.object(MOD, "notify") as mock_notify:
                rc = MOD.main(["--manifest", str(manifest_path), "on", "niri", "--no-reload"])

            self.assertEqual(rc, 1)
            self.assertEqual(os.readlink(links_dir / "niri"), manifest["items"][0]["store"])
            mock_notify.assert_called_once()

    def test_reset_restores_all_dev_items_and_restarts_quickshell_last(self):
        with tempfile.TemporaryDirectory() as tmp:
            _, state_home, links_dir, manifest_path, manifest = make_env(tmp)
            with mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_home)}):
                self.assertEqual(MOD.main(["--manifest", str(manifest_path), "sync-store"]), 0)
                self.assertEqual(
                    MOD.main(["--manifest", str(manifest_path), "on", "quickshell", "--no-reload", "--quiet"]),
                    0,
                )
                self.assertEqual(
                    MOD.main(["--manifest", str(manifest_path), "on", "kanshi", "--no-reload", "--quiet"]),
                    0,
                )

            calls = []

            def fake_run(argv):
                calls.append(list(argv))
                return subprocess.CompletedProcess(argv, 0, "", "")

            with (
                mock.patch.dict(os.environ, {"XDG_STATE_HOME": str(state_home)}),
                mock.patch.object(MOD, "run_cmd", side_effect=fake_run),
                mock.patch.object(MOD.shutil, "which", return_value="/usr/bin/fake"),
            ):
                rc = MOD.main(["--manifest", str(manifest_path), "reset", "--quiet"])

            self.assertEqual(rc, 0)
            for item in manifest["items"]:
                self.assertEqual(os.readlink(links_dir / item["name"]), item["store"])
            self.assertEqual(
                calls,
                [
                    ["kanshictl", "reload"],
                    ["systemctl", "--user", "restart", "--no-block", "quickshell-hub.service"],
                ],
            )


if __name__ == "__main__":
    unittest.main()
