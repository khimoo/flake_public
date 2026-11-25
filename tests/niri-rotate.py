import importlib.util
import json
import os
import pathlib
import subprocess
import unittest
from unittest import mock

SCRIPT_PATH = pathlib.Path(
    os.environ.get(
        "NIRI_ROTATE_SCRIPT",
        str(pathlib.Path(__file__).resolve().parent.parent / "modules/home-manager/gui/niri/rotate.py"),
    )
)
SPEC = importlib.util.spec_from_file_location("niri_rotate", SCRIPT_PATH)
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


class NiriRotateTest(unittest.TestCase):
    def test_toggle_stops_when_active(self):
        calls = []

        def fake_run(argv, check=True):
            calls.append(list(argv))
            if argv[:4] == ["systemctl", "--user", "is-active", "--quiet"]:
                return subprocess.CompletedProcess(argv, 0, "", "")
            return subprocess.CompletedProcess(argv, 0, "", "")

        with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
            self.assertEqual(MOD.main(["niri-rotate", "eDP-1", "toggle"]), 0)

        self.assertIn(["systemctl", "--user", "stop", "iio-niri.service"], calls)
        self.assertTrue(any(c[0] == "notify-send" and "オフ" in c[-1] for c in calls))

    def test_toggle_starts_when_inactive(self):
        calls = []

        def fake_run(argv, check=True):
            calls.append(list(argv))
            if argv[:4] == ["systemctl", "--user", "is-active", "--quiet"]:
                return subprocess.CompletedProcess(argv, 3, "", "")
            return subprocess.CompletedProcess(argv, 0, "", "")

        with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
            self.assertEqual(MOD.main(["niri-rotate", "eDP-1", "toggle"]), 0)

        self.assertIn(["systemctl", "--user", "start", "iio-niri.service"], calls)
        self.assertTrue(any(c[0] == "notify-send" and "オン" in c[-1] for c in calls))

    def test_rotate_cw_stops_iio_and_cycles_clockwise(self):
        cycle = [
            ("Normal", "270"),
            ("270", "180"),
            ("180", "90"),
            ("90", "normal"),
        ]
        for current, expected in cycle:
            with self.subTest(current=current, expected=expected):
                calls = []

                def fake_run(argv, check=True):
                    calls.append(list(argv))
                    if argv == ["niri", "msg", "--json", "outputs"]:
                        payload = {"eDP-1": {"logical": {"transform": current}}}
                        return subprocess.CompletedProcess(argv, 0, json.dumps(payload), "")
                    return subprocess.CompletedProcess(argv, 0, "", "")

                with mock.patch.object(MOD, "run_cmd", side_effect=fake_run):
                    self.assertEqual(MOD.main(["niri-rotate", "eDP-1", "cw"]), 0)

                self.assertEqual(calls[0], ["systemctl", "--user", "stop", "iio-niri.service"])
                self.assertIn(["niri", "msg", "output", "eDP-1", "transform", expected], calls)


if __name__ == "__main__":
    unittest.main()
