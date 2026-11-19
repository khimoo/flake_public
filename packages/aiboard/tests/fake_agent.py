#!/usr/bin/env python3
"""Fake resident used by test_aiboard.py (stands in for `hermes chat --oneshot`)."""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

AIBOARD = str(Path(__file__).resolve().parent.parent / "aiboard.py")


def board(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, AIBOARD, *args], capture_output=True, text=True)


prompt = sys.stdin.read()
handle = os.environ.get("AIBOARD_AGENT", "?")
focus = os.environ.get("AIBOARD_FOCUS_THREAD", "?")
key = handle.replace("-", "_").upper()

pdir = os.environ.get("FAKE_PROMPT_DIR")
if pdir:
    Path(pdir, f"{handle}-{focus}-{os.getpid()}.txt").write_text(prompt, encoding="utf-8")

if os.environ.get("FAKE_HANG") == "1":
    time.sleep(120)

time.sleep(float(os.environ.get("FAKE_SLEEP", "0.5")))
extra = []

if os.environ.get("AIBOARD_CONSULT") == "1":
    r = board("reply", focus, "@b 追加で聞きたい", "--as", handle)
    w = board("wait", focus, "--timeout", "30", "--as", handle)
    board("note", "--as", handle, "--append", "consult done")
    print(f"SUMMARY: 結論は {handle} が整理した。wait_rc={w.returncode}\nWAITOUT:{w.stdout}")
    sys.exit(0)

script = os.environ.get(f"FAKE_SCRIPT_{key}")
if script and os.environ.get("AIBOARD_WORKER") == "1":
    # Session-worker mode: a JSON list of steps, e.g.
    #   [{"reply": "@b どう思う？"}, {"wait": 30}, {"reply": "合意"}, {"print": "完了"}]
    # Every step is logged as a JSON line to <FAKE_PROMPT_DIR>/<handle>-<focus>-<pid>.log for assertions.
    tlog = Path(pdir, f"{handle}-{focus}-{os.getpid()}.log") if pdir else None
    last_no = None
    final = "完了"

    def record(entry: dict) -> None:
        if tlog:
            with tlog.open("a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")

    for step in json.loads(script):
        if "reply" in step:
            r = board("reply", focus, step["reply"], "--as", handle)
            m = re.search(r"Posted >>(\d+)", r.stdout)
            if m:
                last_no = int(m.group(1))
            record({"op": "reply", "rc": r.returncode, "no": last_no, "out": r.stdout, "err": r.stderr})
        elif "wait" in step:
            args = ["wait", focus, "--timeout", str(step["wait"]), "--as", handle]
            if step.get("since", True) and last_no is not None:
                args[2:2] = ["--since", str(last_no)]
            t0 = time.monotonic()
            r = board(*args)
            record({"op": "wait", "rc": r.returncode, "elapsed": time.monotonic() - t0, "out": r.stdout})
        elif "sleep" in step:
            time.sleep(float(step["sleep"]))
        elif "print" in step:
            final = step["print"]
    print(final)
    sys.exit(0)

if os.environ.get("FAKE_TRY_FOCUS") == "1":
    r = board("reply", focus, "impersonate", "--as", "zzz")
    extra.append(f"impersonate_rc={r.returncode}")
    r = board("stop")
    extra.append(f"stop_rc={r.returncode}")

side_tid = os.environ.get(f"FAKE_SIDE_TID_{key}")
if side_tid:
    r = board("reply", side_tid, "寄り道で一言 @c", "--as", handle)
    extra.append(f"side_rc={r.returncode}")
    board("note", "--as", handle, "--set", f"{handle} visited {side_tid}")

if os.environ.get("FAKE_TRY_FOCUS") == "1":
    # Session workers may now post to their focus thread with `aiboard reply` (normal, non-side post).
    # stdout must then NOT be posted a second time by run_worker.
    r = board("reply", focus, f"本題へ直接 reply {' '.join(extra)}", "--as", handle)
    if pdir:
        Path(pdir, f"focusrc-{handle}-{focus}.out").write_text(f"{r.returncode}\n{r.stdout}{r.stderr}",
                                                               encoding="utf-8")
    print("完了 (stdout は二重投稿されないはず)")
    sys.exit(0)

mention = os.environ.get(f"FAKE_MENTION_{key}", "")
print(f"{handle} の意見です {mention} {' '.join(extra)}".strip())
