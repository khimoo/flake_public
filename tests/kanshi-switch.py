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
        "KANSHI_SWITCH_SCRIPT",
        str(pathlib.Path(__file__).resolve().parent.parent / "modules/home-manager/gui/kanshi-switch.py"),
    )
)
SPEC = importlib.util.spec_from_file_location("kanshi_switch", SCRIPT_PATH)
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class KanshiSwitchTest(unittest.TestCase):
    def test_parse_named_profiles_handles_anonymous_nested_quoted_and_include(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            extra = root / "extra.conf"
            extra.write_text(
                'profile "home desk" {\n'
                '    output "Dell" enable\n'
                "}\n"
                "profile extend {\n"
                "    output eDP-1 enable\n"
                "}\n",
                encoding="utf-8",
            )
            cfg = root / "config"
            cfg.write_text(
                "# comment line\n"
                "profile {\n"
                "    output * enable\n"
                "}\n"
                "profile extend {\n"
                '    output "BOE 123" {\n'
                "        mode 2256x1504\n"
                "    }\n"
                "}\n"
                "profile external-only {\n"
                '    output "BOE 123" disable\n'
                "}\n"
                f'include "{extra}"\n',
                encoding="utf-8",
            )
            self.assertEqual(
                MOD.parse_named_profiles(cfg),
                ["extend", "external-only", "home desk"],
            )

    def test_picker_switches_selected_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = pathlib.Path(tmp) / "config"
            cfg.write_text(
                "profile extend {\n    output eDP-1 enable\n}\n"
                "profile external-only {\n    output eDP-1 disable\n}\n",
                encoding="utf-8",
            )
            calls = []

            def fake_run(argv, input_text=None, env=None):
                calls.append((list(argv), input_text))
                if argv == ["kanshictl", "status"]:
                    return subprocess.CompletedProcess(
                        argv, 0, json.dumps({"current_profile": "extend"}), ""
                    )
                if argv[0] == "fuzzel":
                    return subprocess.CompletedProcess(argv, 0, "1\n", "")
                return subprocess.CompletedProcess(argv, 0, "", "")

            with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
                rc = MOD.main(["kanshi-switch", "--config", str(cfg)])

            self.assertEqual(rc, 0)
            fuzzel_call = [c for c in calls if c[0][0] == "fuzzel"][0]
            self.assertIn("--select-index=0", fuzzel_call[0])
            self.assertIn("● extend  (現在・既定)", fuzzel_call[1])
            self.assertIn("○ external-only", fuzzel_call[1])
            self.assertIn("★ 起動時の既定を変更", fuzzel_call[1])
            self.assertIn(["kanshictl", "switch", "external-only"], [c[0] for c in calls])

    def test_picker_cancel_does_not_switch(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = pathlib.Path(tmp) / "config"
            cfg.write_text("profile extend {\n    output eDP-1 enable\n}\n", encoding="utf-8")
            calls = []

            def fake_run(argv, input_text=None, env=None):
                calls.append(list(argv))
                if argv == ["kanshictl", "status"]:
                    return subprocess.CompletedProcess(argv, 0, "{}", "")
                if argv[0] == "fuzzel":
                    return subprocess.CompletedProcess(argv, 2, "", "")
                return subprocess.CompletedProcess(argv, 0, "", "")

            with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
                rc = MOD.main(["kanshi-switch", "--config", str(cfg)])

            self.assertEqual(rc, 0)
            self.assertFalse(any(c[:2] == ["kanshictl", "switch"] for c in calls))

    def test_status_json_outputs_profiles_and_current(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = pathlib.Path(tmp) / "config"
            cfg.write_text(
                "profile desk {\n    output DP-3 enable\n}\n"
                "profile movie {\n    output HDMI-A-1 enable\n}\n",
                encoding="utf-8",
            )

            def fake_run(argv, input_text=None, env=None):
                if argv == ["kanshictl", "status"]:
                    return subprocess.CompletedProcess(
                        argv, 0, json.dumps({"current_profile": "movie"}), ""
                    )
                return subprocess.CompletedProcess(argv, 0, "", "")

            buf = io.StringIO()
            with mock.patch.object(MOD, "run_cmd", side_effect=fake_run), mock.patch("sys.stdout", buf):
                rc = MOD.main(["kanshi-switch", "--config", str(cfg), "--status-json"])

            self.assertEqual(rc, 0)
            self.assertEqual(
                json.loads(buf.getvalue()),
                {"profiles": ["desk", "movie"], "current": "movie", "default": "desk", "kanshi_ok": True},
            )

    def test_create_appends_named_profile_with_shadowed_kanshictl(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = pathlib.Path(tmp) / "config"
            cfg.write_text("# header\n\nprofile desk {\n\toutput DP-3 enable\n}\n", encoding="utf-8")
            calls = []

            def fake_run(argv, input_text=None, env=None):
                calls.append((list(argv), env))
                if argv == ["wdisplays", "--kanshi"]:
                    draft_path = pathlib.Path(env["WDISPLAYS_KANSHI_CONFIG"])
                    first_path_dir = pathlib.Path(env["PATH"].split(":")[0])
                    self.assertTrue((first_path_dir / "kanshictl").is_file())
                    draft_path.write_text(
                        'profile {\n\toutput "Sony VPL-HW20 0x01010101" enable mode 1920x1080@60.000Hz position 0,0 scale 1 transform normal\n}\n',
                        encoding="utf-8",
                    )
                return subprocess.CompletedProcess(argv, 0, "", "")

            with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
                rc = MOD.main(["kanshi-switch", "--config", str(cfg), "--create", "movie"])

            self.assertEqual(rc, 0)
            saved = cfg.read_text(encoding="utf-8")
            self.assertIn("profile desk {\n", saved)
            self.assertIn("profile movie {\n", saved)
            self.assertIn('output "Sony VPL-HW20 0x01010101" enable', saved)
            cmd_list = [c[0] for c in calls]
            self.assertIn(["kanshictl", "reload"], cmd_list)
            self.assertIn(["kanshictl", "switch", "movie"], cmd_list)

    def test_create_rejects_duplicate_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = pathlib.Path(tmp) / "config"
            cfg.write_text("profile desk {\n\toutput DP-3 enable\n}\n", encoding="utf-8")
            calls = []

            def fake_run(argv, input_text=None, env=None):
                calls.append(list(argv))
                return subprocess.CompletedProcess(argv, 0, "", "")

            with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
                rc = MOD.main(["kanshi-switch", "--config", str(cfg), "--create", "desk"])

            self.assertEqual(rc, 1)
            self.assertFalse(any(c[0] == "wdisplays" for c in calls))

    def test_edit_replaces_only_target_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = pathlib.Path(tmp) / "config"
            cfg.write_text(
                "# header\n\n"
                "profile desk {\n\toutput DP-3 enable\n}\n\n"
                "profile movie {\n\toutput HDMI-A-1 disable\n}\n",
                encoding="utf-8",
            )
            calls = []

            def fake_run(argv, input_text=None, env=None):
                calls.append(list(argv))
                if argv == ["wdisplays", "--kanshi"]:
                    draft = pathlib.Path(env["WDISPLAYS_KANSHI_CONFIG"])
                    self.assertIn("profile movie {", draft.read_text(encoding="utf-8"))
                    draft.write_text("profile movie {\n\toutput HDMI-A-1 enable\n}\n", encoding="utf-8")
                return subprocess.CompletedProcess(argv, 0, "", "")

            with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
                rc = MOD.main(["kanshi-switch", "--config", str(cfg), "--edit", "movie"])

            self.assertEqual(rc, 0)
            saved = cfg.read_text(encoding="utf-8")
            self.assertIn("profile desk {\n\toutput DP-3 enable\n}\n", saved)
            self.assertIn("profile movie {\n\toutput HDMI-A-1 enable\n}\n", saved)
            self.assertNotIn("HDMI-A-1 disable", saved)
            self.assertIn(["kanshictl", "reload"], calls)
            self.assertIn(["kanshictl", "switch", "movie"], calls)

    def test_delete_removes_only_target_profile(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = pathlib.Path(tmp) / "config"
            cfg.write_text(
                "# header\n\n"
                "profile desk {\n\toutput DP-3 enable\n}\n\n"
                "profile movie {\n\toutput HDMI-A-1 enable\n}\n",
                encoding="utf-8",
            )
            calls = []

            def fake_run(argv, input_text=None, env=None):
                calls.append(list(argv))
                return subprocess.CompletedProcess(argv, 0, "", "")

            with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
                rc = MOD.main(["kanshi-switch", "--config", str(cfg), "--delete", "desk"])

            self.assertEqual(rc, 0)
            saved = cfg.read_text(encoding="utf-8")
            self.assertNotIn("profile desk", saved)
            self.assertIn("profile movie {\n\toutput HDMI-A-1 enable\n}\n", saved)
            self.assertIn(["kanshictl", "reload"], calls)

    def test_set_default_moves_profile_to_top_preserving_header(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = pathlib.Path(tmp) / "config"
            cfg.write_text(
                "# header comment\n\n"
                "profile desk {\n\toutput DP-3 enable\n}\n\n"
                "profile draw {\n\toutput DP-2 enable\n}\n\n"
                "profile movie {\n\toutput HDMI-A-1 enable\n}\n",
                encoding="utf-8",
            )
            calls = []

            def fake_run(argv, input_text=None, env=None):
                calls.append(list(argv))
                return subprocess.CompletedProcess(argv, 0, "", "")

            with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
                rc = MOD.main(["kanshi-switch", "--config", str(cfg), "--set-default", "movie"])

            self.assertEqual(rc, 0)
            saved = cfg.read_text(encoding="utf-8")
            self.assertTrue(saved.startswith("# header comment\n\nprofile movie {\n"))
            self.assertEqual(MOD.parse_local_named_profiles(cfg), ["movie", "desk", "draw"])
            self.assertIn(["kanshictl", "reload"], calls)

    def test_set_default_noop_when_already_first(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = pathlib.Path(tmp) / "config"
            original = "# header\n\nprofile desk {\n\toutput DP-3 enable\n}\n\nprofile movie {\n\toutput HDMI-A-1 enable\n}\n"
            cfg.write_text(original, encoding="utf-8")
            calls = []

            def fake_run(argv, input_text=None, env=None):
                calls.append(list(argv))
                return subprocess.CompletedProcess(argv, 0, "", "")

            with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
                rc = MOD.main(["kanshi-switch", "--config", str(cfg), "--set-default", "desk"])

            self.assertEqual(rc, 0)
            self.assertEqual(cfg.read_text(encoding="utf-8"), original)
            self.assertNotIn(["kanshictl", "reload"], calls)

    def test_list_option_outputs_named_profiles(self):
        with tempfile.TemporaryDirectory() as tmp:
            cfg = pathlib.Path(tmp) / "config"
            cfg.write_text(
                "profile desk {\n    output DP-1 enable\n}\n"
                "profile laptop {\n    output eDP-1 enable\n}\n",
                encoding="utf-8",
            )
            buf = io.StringIO()
            with mock.patch("sys.stdout", buf):
                rc = MOD.main(["kanshi-switch", "--config", str(cfg), "--list"])
            self.assertEqual(rc, 0)
            self.assertEqual(buf.getvalue().splitlines(), ["desk", "laptop"])


if __name__ == "__main__":
    unittest.main()
