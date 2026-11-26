#!/usr/bin/env python3
"""Quickshell ハブ用の Bitwarden (rbw) 連携ヘルパー。

サブコマンド:
  list             rbw list の結果を JSON（{"ok": true, "items": [...]}）で返す。
  copy-pass <id>   パスワードを wl-copy し、cliphist 記録をスキップ＋15秒後に自動消去する。
  copy-user <id>   ユーザー名を wl-copy する。
  copy-totp <id>   TOTP コードを wl-copy し、cliphist 記録をスキップ＋15秒後に自動消去する。
  unlock           rbw unlock を起動する（GUI pinentry を使用）。
"""

import json
import os
import pathlib
import subprocess
import sys
import time

SECRET_CLEAR_SECONDS = 15


def sentinel_path() -> pathlib.Path:
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    return pathlib.Path(runtime_dir) / "qs-hub-secret-copy"


def mark_secret_copy() -> None:
    p = sentinel_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(f"{time.time():.3f}\n", encoding="utf-8")


def parse_rbw_list(output: str) -> list[dict[str, str]]:
    items = []
    for line in output.splitlines():
        if not line.strip():
            continue
        parts = line.split("\t")
        while len(parts) < 4:
            parts.append("")
        entry_id, name, user, folder = parts[0], parts[1], parts[2], parts[3]
        if not entry_id:
            continue
        items.append({
            "id": entry_id,
            "name": name,
            "user": user,
            "folder": folder,
        })
    return items


def cmd_list() -> int:
    # 先に設定の有無を確かめ、未設定とロック中を誤認しないようにする。
    cfg = subprocess.run(["rbw", "config", "show"], capture_output=True, text=True)
    if cfg.returncode != 0:
        reason = "rbw 未設定（rbw_config 配布後に端末で rbw register を実行してください）"
        print(json.dumps({"ok": False, "error": reason}, ensure_ascii=False))
        return 0

    # rbw unlocked を確認してから list を呼ぶことで、検索画面を開いただけで pinentry が突然飛び出すのを防ぐ。
    check = subprocess.run(["rbw", "unlocked"], capture_output=True, text=True)
    if check.returncode != 0:
        reason = "Bitwarden はロック中です（「解錠 (rbw)」を押してください）"
        print(json.dumps({"ok": False, "error": reason}, ensure_ascii=False))
        return 0

    res = subprocess.run(
        ["rbw", "list", "--fields", "id,name,user,folder"],
        capture_output=True,
        text=True,
    )
    if res.returncode != 0:
        err = (res.stderr or "rbw list failed").strip()
        print(json.dumps({"ok": False, "error": err}, ensure_ascii=False))
        return 0
    print(json.dumps({"ok": True, "items": parse_rbw_list(res.stdout)}, ensure_ascii=False))
    return 0


def copy_text(value: str, secret: bool) -> None:
    if secret:
        mark_secret_copy()
    subprocess.run(["wl-copy"], input=value, text=True, check=True)
    if secret:
        # 15 秒後に、まだ同じ秘密がクリップボードに残っていれば空にする。
        subprocess.Popen(
            [
                sys.executable,
                "-c",
                (
                    "import subprocess, sys, time; "
                    f"time.sleep({SECRET_CLEAR_SECONDS}); "
                    "cur = subprocess.run(['wl-paste', '--no-newline'], capture_output=True, text=True); "
                    "cur.returncode == 0 and cur.stdout == sys.argv[1] and subprocess.run(['wl-copy', '--clear'])"
                ),
                value,
            ],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def notify(summary: str, body: str = "") -> None:
    subprocess.run(["notify-send", "-a", "Vault", summary, body], check=False)


def cmd_copy(mode: str, entry_id: str) -> int:
    if mode == "copy-pass":
        res = subprocess.run(["rbw", "get", entry_id], capture_output=True, text=True)
        if res.returncode == 0:
            copy_text(res.stdout.rstrip("\n"), secret=True)
            notify("パスワードをコピーしました", f"{SECRET_CLEAR_SECONDS} 秒後にクリップボードから自動消去します")
            return 0
    elif mode == "copy-user":
        res = subprocess.run(["rbw", "get", "--field", "username", entry_id], capture_output=True, text=True)
        if res.returncode == 0:
            copy_text(res.stdout.rstrip("\n"), secret=False)
            notify("ユーザー名をコピーしました")
            return 0
    elif mode == "copy-totp":
        res = subprocess.run(["rbw", "code", entry_id], capture_output=True, text=True)
        if res.returncode == 0:
            copy_text(res.stdout.strip(), secret=True)
            notify("TOTP コードをコピーしました", f"{SECRET_CLEAR_SECONDS} 秒後に自動消去します")
            return 0
    else:
        return 2
    err = (res.stderr or "取得に失敗しました").strip()
    notify("Vault エラー", err)
    return 1


def cmd_unlock() -> int:
    res = subprocess.run(["rbw", "unlock"], capture_output=True, text=True)
    if res.returncode == 0:
        notify("Bitwarden を解錠しました")
        return 0
    notify("Bitwarden の解錠に失敗しました", (res.stderr or "").strip())
    return 1


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        return 2
    sub = argv[1]
    if sub == "list":
        return cmd_list()
    if sub in ("copy-pass", "copy-user", "copy-totp") and len(argv) >= 3:
        return cmd_copy(sub, argv[2])
    if sub == "unlock":
        return cmd_unlock()
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
