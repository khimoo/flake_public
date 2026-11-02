import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


SCRIPT = Path(sys.argv.pop(1)).resolve()

FAKE = r'''
import json
import os
import signal
import sys
import time
from pathlib import Path

root = Path(os.environ["FAKE_ROOT"])
name = Path(sys.argv[0]).name

def listeners():
    entries = []
    for path in root.glob("listener-*"):
        try:
            entries.append(json.loads(path.read_text()))
        except FileNotFoundError:
            continue
    return entries

def event(kind, **fields):
    with (root / "events").open("a") as f:
        f.write(json.dumps(dict(kind=kind, **fields)) + "\n")

if name == "ssh":
    pid = os.getpid()
    args = sys.argv[1:]
    ports = [int(args[i + 1].split(":")[0])
             for i, arg in enumerate(args) if arg == "-L"]
    path = root / f"listener-{pid}"
    event("start", pid=pid, args=args, previous=listeners())

    def stop(signum, frame):
        time.sleep(0.25)
        if 15210 in bound and len(bound) > 1:
            bound.remove(15210)
            publish()
            time.sleep(0.25)
        path.unlink(missing_ok=True)
        sys.exit(0)

    bound = []

    def publish():
        temporary = root / f"pending-{pid}"
        temporary.write_text(json.dumps(dict(pid=pid, ports=bound, host=args[-1])))
        temporary.replace(path)

    signal.signal(signal.SIGTERM, stop)
    if os.environ.get("FAKE_SSH_FAIL"):
        print("fake ssh connection failed", file=sys.stderr)
        sys.exit(1)
    for port in ports:
        time.sleep(0.25)
        bound.append(port)
        publish()
    while True:
        time.sleep(1)
elif name == "ss":
    port = int(sys.argv[-1].split(":")[-1])
    for item in listeners():
        if port in item["ports"]:
            suffix = f' users:(("ssh",pid={item["pid"]},fd=5))' if "p" in sys.argv[1] else ""
            print(f"LISTEN 0 128 127.0.0.1:{port} 0.0.0.0:*{suffix}")
elif name == "xdg-open":
    event("open", args=sys.argv[1:], listeners=listeners())
'''


class AlookOpen(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.tools = self.root / "tools"
        self.tools.mkdir()
        for name in ("ssh", "ss", "xdg-open"):
            path = self.tools / name
            path.write_text(f"#!{sys.executable}\n" + FAKE)
            path.chmod(0o755)
        self.env = os.environ | {
            "PATH": f"{self.tools}:{os.environ['PATH']}",
            "XDG_RUNTIME_DIR": str(self.root / "runtime"),
            "FAKE_ROOT": str(self.root),
            "ALOOK_OPEN_REMOTES": "desktop-local=desktop desktop-ts=desktop-ts",
        }
        self.env.pop("FAKE_SSH_FAIL", None)
        self.children = []
        self.addCleanup(self.cleanup_processes)

    def events(self, kind):
        path = self.root / "events"
        entries = [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
        return [entry for entry in entries if entry["kind"] == kind]

    def wait_for(self, predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.02)
        self.fail("Timed out waiting for fake process")

    def cleanup_processes(self):
        pids = {event["pid"] for event in self.events("start")}
        pids.update(child.pid for child in self.children)
        for pid in pids:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        deadline = time.monotonic() + 3
        while list(self.root.glob("listener-*")) and time.monotonic() < deadline:
            time.sleep(0.02)
        for child in self.children:
            child.wait(timeout=3)

    def run_script(self, target, fail=False):
        env = self.env | ({"FAKE_SSH_FAIL": "1"} if fail else {})
        return subprocess.run(
            ["bash", "-euo", "pipefail", str(SCRIPT), target],
            env=env, capture_output=True, text=True, timeout=22,
        )

    def seed(self, ports, recorded=False):
        args = [str(self.tools / "ssh"), "-N"]
        for port in ports:
            args.extend(["-L", f"{port}:localhost:{port}"])
        child = subprocess.Popen(
            args + ["desktop"], env=self.env, start_new_session=True,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.children.append(child)
        listener = self.root / f"listener-{child.pid}"
        self.wait_for(lambda: listener.exists() and json.loads(listener.read_text())["ports"] == ports)
        if recorded:
            state = self.root / "runtime/alook-open"
            state.mkdir(parents=True)
            (state / "forward.pid").write_text(str(child.pid))
            (state / "forward.target").write_text("desktop-local")
        return child

    def assert_open(self, count, pid):
        self.wait_for(lambda: len(self.events("open")) == count)
        opened = self.events("open")[-1]
        self.assertEqual(opened["args"], ["http://localhost:15210"])
        self.assertIn(
            {"pid": pid, "ports": [15210, 15212], "host": self.events("start")[-1]["args"][-1]},
            opened["listeners"],
        )

    def recorded_pid(self):
        return int((self.root / "runtime/alook-open/forward.pid").read_text())

    def test_new_connection_waits_for_both_ports_and_reuses_same_process(self):
        result = self.run_script("desktop-local")
        self.assertEqual(result.returncode, 0, result.stderr)
        pid = self.recorded_pid()
        self.assert_open(1, pid)
        args = self.events("start")[0]["args"]
        for value in ("15210:localhost:15210", "15212:localhost:15212",
                      "ExitOnForwardFailure=yes", "ServerAliveInterval=15", "ServerAliveCountMax=2"):
            self.assertIn(value, args)
        result = self.run_script("desktop-local")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_open(2, pid)
        self.assertEqual(len(self.events("start")), 1)

    def test_legacy_connection_is_replaced(self):
        old = self.seed([15210], recorded=True)
        result = self.run_script("desktop-local")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotEqual(self.recorded_pid(), old.pid)
        self.assert_open(1, self.recorded_pid())
        self.assertEqual(old.wait(timeout=3), 0)
        self.assertEqual(self.events("start")[-1]["previous"], [])

    def test_unrelated_owner_is_preserved_and_conflicting_port_is_reported(self):
        for port in (15210, 15212):
            with self.subTest(port=port):
                old = self.seed([15210], recorded=True) if port == 15212 else None
                owner = self.seed([port])
                result = self.run_script("desktop-local")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(str(port), result.stderr)
                self.assertEqual(self.events("open"), [])
                self.assertIsNone(owner.poll())
                if old:
                    self.assertEqual(old.wait(timeout=3), 0)
                owner.terminate()
                owner.wait(timeout=3)

    def test_switch_waits_for_old_ports_and_forwards_both_to_new_host(self):
        old = self.seed([15210, 15212], recorded=True)
        result = self.run_script("desktop-ts")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(old.wait(timeout=3), 0)
        self.assertEqual(self.events("start")[-1]["previous"], [])
        self.assertEqual(self.events("start")[-1]["args"][-1], "desktop-ts")
        self.assert_open(1, self.recorded_pid())

    def test_ssh_failure_does_not_open_browser(self):
        result = self.run_script("desktop-local", fail=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fake ssh connection failed", result.stderr)
        self.assertEqual(self.events("open"), [])
        self.assertFalse((self.root / "runtime/alook-open/forward.pid").exists())

    def test_local_opens_existing_service_without_stopping_it(self):
        owner = self.seed([15210])
        result = self.run_script("local")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.wait_for(lambda: len(self.events("open")) == 1)
        self.assertEqual(self.events("open")[0]["args"], ["http://localhost:15210"])
        self.assertIsNone(owner.poll())


if __name__ == "__main__":
    unittest.main()
