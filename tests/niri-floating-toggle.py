import importlib.util
import json
import os
import pathlib
import tempfile
import unittest
from unittest import mock

SCRIPT_PATH = pathlib.Path(
    os.environ.get(
        "TOGGLE_FLOATING_SCRIPT",
        str(pathlib.Path(__file__).resolve().parent.parent / "modules/home-manager/gui/niri/toggle-floating.py"),
    )
)
SPEC = importlib.util.spec_from_file_location("toggle_floating", SCRIPT_PATH)
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class ToggleFloatingTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": self.tmp.name})
        self.env.start()
        self.addCleanup(self.env.stop)

    def run_toggle(self, workspaces, windows):
        calls = []

        def fake_niri_msg(*args):
            calls.append(list(args))
            if args == ("--json", "workspaces"):
                return json.dumps(workspaces)
            if args == ("--json", "windows"):
                return json.dumps(windows)
            return ""

        with mock.patch.object(MOD, "niri_msg", side_effect=fake_niri_msg):
            rc = MOD.toggle()
        self.assertEqual(rc, 0)
        return [c for c in calls if c[0] == "action"]

    def test_hide_and_restore_floating_only(self):
        workspaces = [
            {"id": 1, "idx": 1, "name": "main", "output": "eDP-1", "is_focused": True},
            {"id": 2, "idx": 2, "name": "background", "output": "eDP-1", "is_focused": False},
            {"id": 3, "idx": 3, "name": None, "output": "eDP-1", "is_focused": False},
        ]
        windows = [
            {"id": 10, "workspace_id": 1, "is_floating": False, "is_focused": False},
            {"id": 11, "workspace_id": 1, "is_floating": True, "is_focused": True},
            {"id": 12, "workspace_id": 1, "is_floating": True, "is_focused": False},
            {"id": 13, "workspace_id": 2, "is_floating": True, "is_focused": False},
        ]

        # 1回目: 現在ワークスペースのフローティング 2 枚だけ一番下の空ワークスペース (idx 3) へ退避
        actions = self.run_toggle(workspaces, windows)
        self.assertEqual(
            actions,
            [
                ["action", "move-window-to-workspace", "--window-id", "11", "--focus", "false", "3"],
                ["action", "move-window-to-workspace", "--window-id", "12", "--focus", "false", "3"],
            ],
        )

        # 2回目: ワークスペース 2 に移動した状態で呼び戻すと、現在のワークスペース (idx 2) に戻り、元のフォーカスを復元
        workspaces_after = [
            {"id": 1, "idx": 1, "name": "main", "output": "eDP-1", "is_focused": False},
            {"id": 2, "idx": 2, "name": "background", "output": "eDP-1", "is_focused": True},
            {"id": 3, "idx": 3, "name": None, "output": "eDP-1", "is_focused": False},
            {"id": 4, "idx": 4, "name": None, "output": "eDP-1", "is_focused": False},
        ]
        windows_after = [
            {"id": 10, "workspace_id": 1, "is_floating": False, "is_focused": False},
            {"id": 11, "workspace_id": 3, "is_floating": True, "is_focused": False},
            {"id": 12, "workspace_id": 3, "is_floating": True, "is_focused": False},
        ]
        actions = self.run_toggle(workspaces_after, windows_after)
        self.assertEqual(
            actions,
            [
                ["action", "move-window-to-workspace", "--window-id", "11", "--focus", "false", "2"],
                ["action", "move-window-to-workspace", "--window-id", "12", "--focus", "false", "2"],
                ["action", "focus-window", "--id", "11"],
            ],
        )
        self.assertFalse(MOD.state_path().exists())

    def test_prunes_closed_and_preserves_other_output(self):
        MOD.save_state(
            MOD.state_path(),
            {
                "eDP-1": {"ids": [11, 99], "focused": 99},
                "DP-1": {"ids": [50], "focused": 50},
            },
        )
        workspaces = [
            {"id": 1, "idx": 1, "name": "main", "output": "eDP-1", "is_focused": True},
            {"id": 2, "idx": 2, "name": None, "output": "eDP-1", "is_focused": False},
        ]
        windows = [
            {"id": 11, "workspace_id": 2, "is_floating": True, "is_focused": False},
            {"id": 50, "workspace_id": 9, "is_floating": True, "is_focused": False},
        ]
        actions = self.run_toggle(workspaces, windows)
        self.assertEqual(
            actions,
            [
                ["action", "move-window-to-workspace", "--window-id", "11", "--focus", "false", "1"],
                ["action", "focus-window", "--id", "11"],
            ],
        )
        self.assertEqual(MOD.load_state(MOD.state_path()), {"DP-1": {"ids": [50], "focused": 50}})


if __name__ == "__main__":
    unittest.main()
