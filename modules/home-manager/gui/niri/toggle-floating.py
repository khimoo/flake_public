import json
import os
import pathlib
import subprocess
import sys


def niri_msg(*args):
    result = subprocess.run(
        ["niri", "msg", *args],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def state_path():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return pathlib.Path(runtime_dir) / "niri-hidden-floating.json"


def load_state(path):
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def save_state(path, state):
    if not state:
        path.unlink(missing_ok=True)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state), encoding="utf-8")
    tmp.replace(path)


def toggle():
    workspaces = json.loads(niri_msg("--json", "workspaces"))
    windows = json.loads(niri_msg("--json", "windows"))

    current = next((ws for ws in workspaces if ws.get("is_focused")), None)
    if current is None:
        return 0

    output = current.get("output") or ""
    cur_id = current["id"]
    cur_idx = current["idx"]
    windows_by_id = {w["id"]: w for w in windows}

    path = state_path()
    state = load_state(path)
    entry = state.get(output) or {}
    # 閉じられた、またはタイルへ戻されたウィンドウ ID を掃除する。
    hidden_ids = [
        wid
        for wid in entry.get("ids", [])
        if wid in windows_by_id
        and windows_by_id[wid].get("is_floating")
        and windows_by_id[wid].get("workspace_id") != cur_id
    ]
    hidden_focused = entry.get("focused")
    if hidden_focused not in hidden_ids:
        hidden_focused = None

    visible_floating = [
        w for w in windows if w.get("workspace_id") == cur_id and w.get("is_floating")
    ]

    if visible_floating:
        # 同じ出力の一番下にある空の動的ワークスペースへ退避する。
        # 戻したときに空になると Niri がそのワークスペースを自動で消す。
        same_output = [ws for ws in workspaces if (ws.get("output") or "") == output]
        bottom = max(same_output, key=lambda ws: ws["idx"])
        stash_idx = bottom["idx"] if bottom["id"] != cur_id else cur_idx + 1

        new_ids = list(hidden_ids)
        focused = hidden_focused
        for w in visible_floating:
            wid = w["id"]
            niri_msg(
                "action",
                "move-window-to-workspace",
                "--window-id",
                str(wid),
                "--focus",
                "false",
                str(stash_idx),
            )
            if wid not in new_ids:
                new_ids.append(wid)
            if w.get("is_focused"):
                focused = wid

        state[output] = {"ids": new_ids, "focused": focused}
        save_state(path, state)
        return 0

    if not hidden_ids:
        if output in state:
            del state[output]
            save_state(path, state)
        return 0

    for wid in hidden_ids:
        niri_msg(
            "action",
            "move-window-to-workspace",
            "--window-id",
            str(wid),
            "--focus",
            "false",
            str(cur_idx),
        )

    target = hidden_focused if hidden_focused in hidden_ids else hidden_ids[-1]
    niri_msg("action", "focus-window", "--id", str(target))

    del state[output]
    save_state(path, state)
    return 0


if __name__ == "__main__":
    sys.exit(toggle())
