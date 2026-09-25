"""Run cargo-remote-run against a fake remote host whose home is a local directory.

Only the transport (ssh, rsync host paths) and nix are faked. cargo and the
built binaries are real, so argument passing, default-run selection and path
mapping are exercised as cargo actually behaves.
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(sys.argv.pop(1)).resolve()
HOST = "fakehost"

FAKES = {
    # ssh joins its arguments and hands them to the remote login shell.
    "ssh": """
shift
cd "$REMOTE_HOME"
HOME=$REMOTE_HOME exec bash -c "$*"
""",
    "rsync": """
args=()
for a in "$@"; do
  case $a in
    fakehost:/*) args+=("${a#fakehost:}") ;;
    fakehost:*) args+=("$REMOTE_HOME/${a#fakehost:}") ;;
    *) args+=("$a") ;;
  esac
done
exec "$REAL_RSYNC" "${args[@]}"
""",
    # Like the real rc, this one creates NIX_BUILD_TOP, and its shellHook prints to stdout
    # and fails outside the project (as `just --list` does).
    "nix": """
printf '%s\\n' "$*" >> "$NIX_LOG"
case $1 in
  copy)
    # The dev env is built here or by a remote builder and has no signature, so the host
    # rejects it unless the client skips the check.
    case " $* " in
      *" --no-check-sigs "*) ;;
      *) echo "error: cannot add path because it lacks a signature by a trusted key" >&2; exit 1 ;;
    esac
    ;;
  print-dev-env)
    while [ "$1" != --profile ]; do shift; done
    ln -sfn "$FAKE_ENV" "$2"
    echo 'export NIX_BUILD_TOP="$(mktemp -d "$HOME/nix-shell.XXXXXX")"'
    echo 'echo shell-hook-output'
    echo '[ -e Cargo.toml ] || echo shell-hook-outside-project >&2'
    ;;
esac
""",
}

MAIN_RS = """
fn main() {
    println!("args={:?}", std::env::args().skip(1).collect::<Vec<_>>());
    println!("cwd={}", std::env::current_dir().unwrap().display());
    println!("manifest={}", std::env::var("CARGO_MANIFEST_DIR").unwrap());
}
"""


class CargoRemoteRun(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()
        self.remote_home = self.root / "remote"
        self.remote_home.mkdir()
        self.fake_env = self.root / "store" / "dev-env"
        self.fake_env.mkdir(parents=True)
        self.nix_log = self.root / "nix.log"
        tools = self.root / "tools"
        tools.mkdir()
        bash = shutil.which("bash")
        for name, body in FAKES.items():
            (tools / name).write_text(f"#!{bash}\nset -euo pipefail\n{body}")
            (tools / name).chmod(0o755)

        self.ws = self.root / "local" / "ws"
        app = self.ws / "app"
        (app / "src").mkdir(parents=True)
        (self.ws / ".envrc").write_text("use flake\n")
        (self.ws / "Cargo.toml").write_text('[workspace]\nmembers = ["app"]\nresolver = "2"\n')
        (app / "Cargo.toml").write_text(
            '[package]\nname = "app"\nversion = "0.1.0"\nedition = "2021"\ndefault-run = "app"\n'
            '[[bin]]\nname = "app"\npath = "src/main.rs"\n'
            '[[bin]]\nname = "other"\npath = "src/other.rs"\n')
        (app / "src" / "main.rs").write_text(MAIN_RS)
        (app / "src" / "other.rs").write_text("fn main() { std::process::exit(3) }\n")

        self.env = os.environ | {
            "PATH": f"{tools}:{os.environ['PATH']}",
            "HOME": str(self.root / "home"),
            "CARGO_HOME": str(self.root / "cargo-home"),
            "CARGO_REMOTE_RUN_HOST": HOST,
            "REMOTE_HOME": str(self.remote_home),
            "REAL_RSYNC": shutil.which("rsync"),
            "FAKE_ENV": str(self.fake_env),
            "NIX_LOG": str(self.nix_log),
        }

    def run_script(self, *args, cwd=None):
        return subprocess.run(["bash", "-euo", "pipefail", str(SCRIPT), "remote-run", *args],
                              cwd=cwd or self.ws / "app", env=self.env, capture_output=True, text=True)

    def remote_ws(self):
        [path] = self.remote_home.glob(".cache/cargo-remote-run/*" + str(self.ws))
        return path

    def test_runs_default_binary_here_with_local_paths(self):
        result = self.run_script("--", "x", "y z")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('args=["x", "y z"]', result.stdout)
        self.assertIn(f"cwd={self.ws / 'app'}", result.stdout)
        self.assertIn(f"manifest={self.ws / 'app'}", result.stdout)
        self.assertTrue((self.remote_ws() / "target/debug/app").exists())
        self.assertFalse((self.ws / "target/debug/app").exists())
        self.assertEqual(list(self.remote_home.glob("nix-shell.*")), [])
        self.assertNotIn("shell-hook-outside-project", result.stderr)

    def test_ships_the_local_dev_env_to_the_host(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        [copy] = [line.split() for line in self.nix_log.read_text().splitlines() if line.startswith("copy ")]
        self.assertIn(f"ssh-ng://{HOST}", copy)
        self.assertEqual(copy[-1], str(self.fake_env))

    def test_passes_cargo_run_arguments_and_exit_status(self):
        result = self.run_script("--bin", "other", cwd=self.ws)
        self.assertEqual(result.returncode, 3, result.stderr)

    def test_does_not_upload_local_target(self):
        (self.ws / "target").mkdir()
        (self.ws / "target" / "local-only").write_text("")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.remote_ws() / "target/local-only").exists())

    def test_failed_build_does_not_run_previous_binary(self):
        self.assertEqual(self.run_script().returncode, 0)
        (self.ws / "app/src/main.rs").write_text("fn main() { compile_error!(\"broken\"); }\n")
        result = self.run_script()
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("args=", result.stdout)


if __name__ == "__main__":
    unittest.main()
