"""Exercise Kitty's IS_NVIM notifications with Neovim's real TUI."""

import errno
import os
from pathlib import Path
import pty
import re
import select
import subprocess
import sys
import tempfile
import time


OSC = re.compile(rb"\x1b\]1337;SetUserVar=IS_NVIM(=MQo)?\x07")
READY = b"\x1b]2;smart-splits-test-ready\x07"
BACKGROUND_QUERY = b"\x1b]11;?\x07"


def test_tui(command, env, cwd, *, keys, expected, redirect_stderr):
    master, slave = pty.openpty()
    output = bytearray()
    deadline = time.monotonic() + 15
    with tempfile.TemporaryFile() as log:
        with subprocess.Popen(
            command, cwd=cwd, env=env, stdin=slave, stdout=slave,
            stderr=log if redirect_stderr else slave,
        ) as nvim:
            os.close(slave)
            try:
                sent_commands = False
                while select.select([master], [], [], max(0, deadline - time.monotonic()))[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as exc:
                        if exc.errno != errno.EIO:  # Linux signals PTY EOF with EIO.
                            raise
                        break
                    if not chunk:
                        break
                    previous_end = len(output)
                    output.extend(chunk)
                    if BACKGROUND_QUERY in output[max(0, previous_end - len(BACKGROUND_QUERY) + 1):]:
                        os.write(master, b"\x1b]11;rgb:0000/0000/0000\x1b\\")
                    if not sent_commands and READY in output:
                        os.write(master, keys)
                        sent_commands = True
                assert sent_commands, f"Neovim did not reach VimEnter: {bytes(output)!r}"
                assert nvim.wait(timeout=2) == 0, f"Neovim failed: {bytes(output)!r}"
            finally:
                os.close(master)
                if nvim.poll() is None:
                    nvim.kill()
        log.seek(0)
        leaked = OSC.findall(log.read())
    observed = OSC.findall(output)
    assert observed == expected and not leaked, (
        f"expected {expected!r} on the TUI only; PTY={observed!r}, log={leaked!r}"
    )


def test_connect(nvim, env, cwd):
    # The target has no smart-splits. The original server must clear its own flag.
    socket = Path(cwd) / "remote.sock"
    exit_on_attach = "autocmd UIEnter * ++once lua vim.schedule(function() vim.cmd('qa!') end)"
    with subprocess.Popen(
        ["nvim", "--headless", "-n", "-i", "NONE", "-u", "NONE", "--listen", str(socket),
         "-c", exit_on_attach],
        cwd=cwd, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    ) as server:
        try:
            deadline = time.monotonic() + 5
            while not socket.exists() and server.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            assert socket.exists(), "target Neovim did not start"
            test_tui(nvim, env, cwd, keys=b":connect! " + os.fsencode(socket) + b"\r",
                     expected=[b"=MQo", b""], redirect_stderr=False)
            assert server.wait(timeout=2) == 0
        finally:
            if server.poll() is None:
                server.kill()


def main(plugin_path):
    with tempfile.TemporaryDirectory() as tmp:
        env = os.environ | {
            "HOME": tmp,
            "XDG_CONFIG_HOME": tmp,
            "XDG_DATA_HOME": tmp,
            "XDG_STATE_HOME": tmp,
            "XDG_CACHE_HOME": tmp,
            "SMART_SPLITS_PATH": plugin_path,
            "KITTY_LISTEN_ON": f"unix:{tmp}/unused-kitty.sock",
            "TERM": "xterm-kitty",
        }
        env.pop("NVIM", None)
        init = Path(tmp) / "init.lua"
        init.write_text(
            "vim.opt.runtimepath:prepend(vim.env.SMART_SPLITS_PATH)\n"
            "require('smart-splits').setup({ multiplexer_integration = 'kitty', at_edge = 'stop' })\n"
        )
        nvim = ["nvim", "-n", "-i", "NONE", "-u", str(init)]
        ready = "autocmd VimEnter * lua vim.api.nvim_ui_send(string.char(27)..']2;smart-splits-test-ready'..string.char(7))"
        # Exercise the plugin's suspend/resume handlers without stopping the test process.
        test_tui(nvim + ["-c", ready], env, tmp,
                 keys=b":doautocmd VimSuspend\r:doautocmd VimResume\r:qa!\r",
                 expected=[b"=MQo", b"", b"=MQo", b""], redirect_stderr=True)
        test_connect(nvim + ["-c", ready], env, tmp)
        headless = subprocess.run(
            nvim + ["--headless", "+qa!"], cwd=tmp, env=env,
            capture_output=True, timeout=10, check=True,
        )
        assert not OSC.search(headless.stdout + headless.stderr), "IS_NVIM leaked without a TUI"
        print("smart-splits Kitty OSC: startup, suspend/resume, shutdown, :connect!, and headless passed")


if __name__ == "__main__":
    main(sys.argv[1])
