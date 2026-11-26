import glob
import json
import os
import pathlib
import stat
import subprocess
import sys
import tempfile

INCLUDE_DEPTH_MAX = 16

FUZZEL_BASE_ARGS = [
    "fuzzel",
    "--dmenu",
    "--minimal-lines",
    "--lines=12",
    "--width=44",
    "--no-icons",
    "--cache=/dev/null",
    "--namespace=kanshi-switch",
    "--font=IBM Plex Sans JP:size=11,PlemolJP Console NF:size=11",
    "--background=1e1e2eee",
    "--text-color=cdd6f4ff",
    "--message-color=a6adc8ff",
    "--prompt-color=89b4faff",
    "--placeholder-color=6c7086ff",
    "--input-color=cdd6f4ff",
    "--match-color=89b4faff",
    "--selection-color=313244ff",
    "--selection-text-color=cdd6f4ff",
    "--selection-match-color=89b4faff",
    "--selection-radius=6",
    "--border-width=2",
    "--border-color=89b4faff",
    "--border-radius=12",
    "--horizontal-pad=16",
    "--vertical-pad=12",
    "--inner-pad=6",
]


def run_cmd(argv, input_text=None, env=None):
    return subprocess.run(argv, input=input_text, env=env, capture_output=True, text=True, check=False)


def spawn_detached(argv):
    subprocess.Popen(
        argv,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def notify(title, body=""):
    cmd = [
        "notify-send",
        "--app-name=kanshi-switch",
        "-h",
        "string:x-canonical-private-synchronous:kanshi-switch",
        title,
    ]
    if body:
        cmd.append(body)
    run_cmd(cmd)


def resolve_config_path(explicit_path=None):
    if explicit_path:
        return pathlib.Path(explicit_path)
    config_home = os.environ.get("XDG_CONFIG_HOME")
    if not config_home:
        home = os.environ.get("HOME", "")
        config_home = os.path.join(home, ".config") if home else ""
    if config_home:
        user_cfg = pathlib.Path(config_home) / "kanshi" / "config"
        if user_cfg.is_file() and os.access(user_cfg, os.R_OK):
            return user_cfg
    return pathlib.Path("/etc/kanshi/config")


def is_writable_config(path):
    real = pathlib.Path(os.path.realpath(path))
    if real.exists():
        return os.access(real, os.W_OK)
    return real.parent.is_dir() and os.access(real.parent, os.W_OK)


def atomic_write_text(path, text):
    real = pathlib.Path(os.path.realpath(path))
    real.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".config.", dir=str(real.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp_name, real)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def format_scfg_word(word):
    if word and not any(ch in word for ch in ' \t"\'{}\\#'):
        return word
    escaped = word.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def tokenize_line(line):
    """libscfg / kanshi 1.8.0 の1行をトークン列と末尾の '{' / '}' の有無に分解する。"""
    stripped = line.lstrip(" \t")
    if not stripped or stripped.startswith("#"):
        return [], False, False

    tokens = []
    i = 0
    n = len(stripped)
    opens = False
    closes = False
    while i < n:
        ch = stripped[i]
        if ch in " \t\r\n":
            i += 1
            continue
        if ch == "{":
            opens = True
            i += 1
            break
        if ch == "}":
            closes = True
            i += 1
            break
        if ch in "\"'":
            quote = ch
            i += 1
            buf = []
            while i < n and stripped[i] != quote:
                if stripped[i] == "\\" and quote == '"' and i + 1 < n:
                    i += 1
                buf.append(stripped[i])
                i += 1
            if i < n and stripped[i] == quote:
                i += 1
            tokens.append("".join(buf))
            continue
        buf = []
        while i < n and stripped[i] not in " \t\r\n{}":
            if stripped[i] == "\\" and i + 1 < n:
                i += 1
            buf.append(stripped[i])
            i += 1
        tokens.append("".join(buf))
    return tokens, opens, closes


def parse_profile_blocks(text):
    """トップレベルの profile ブロックを (name_or_None, start_line, end_line_inclusive) で返す。"""
    lines = text.splitlines(keepends=True)
    blocks = []
    brace_depth = 0
    active_start = None
    active_name = None

    for idx, line in enumerate(lines):
        tokens, opens, closes = tokenize_line(line)
        if closes and not tokens:
            brace_depth = max(0, brace_depth - 1)
            if brace_depth == 0 and active_start is not None:
                blocks.append((active_name, active_start, idx))
                active_start = None
                active_name = None
            continue
        if brace_depth == 0 and tokens and tokens[0] == "profile" and opens:
            active_start = idx
            active_name = tokens[1] if len(tokens) >= 2 else None
        if opens:
            brace_depth += 1
        if closes:
            brace_depth = max(0, brace_depth - 1)
            if brace_depth == 0 and active_start is not None:
                blocks.append((active_name, active_start, idx))
                active_start = None
                active_name = None

    return blocks


def parse_named_profiles(path, _depth=0, _visited=None):
    if _depth > INCLUDE_DEPTH_MAX:
        return []
    if _visited is None:
        _visited = set()
    try:
        real = os.path.realpath(path)
    except OSError:
        return []
    if real in _visited:
        return []
    _visited.add(real)
    try:
        text = pathlib.Path(path).read_text(encoding="utf-8")
    except OSError:
        return []

    profiles = []
    seen = set()
    brace_depth = 0

    def add_profile(name):
        if name and name not in seen:
            seen.add(name)
            profiles.append(name)

    for line in text.splitlines():
        tokens, opens, closes = tokenize_line(line)
        if closes and not tokens:
            brace_depth = max(0, brace_depth - 1)
            continue
        if brace_depth == 0 and tokens:
            directive = tokens[0]
            if directive == "profile" and opens and len(tokens) >= 2:
                add_profile(tokens[1])
            elif directive == "include" and len(tokens) == 2:
                pattern = os.path.expandvars(os.path.expanduser(tokens[1]))
                for inc in sorted(glob.glob(pattern)):
                    for name in parse_named_profiles(inc, _depth + 1, _visited):
                        add_profile(name)
        if opens:
            brace_depth += 1
        if closes:
            brace_depth = max(0, brace_depth - 1)

    return profiles


def parse_local_named_profiles(path):
    try:
        text = pathlib.Path(path).read_text(encoding="utf-8")
    except OSError:
        return []
    result = []
    seen = set()
    for name, _, _ in parse_profile_blocks(text):
        if name and name not in seen:
            seen.add(name)
            result.append(name)
    return result


def extract_named_block(draft_text, name):
    """wdisplays が出力した profile ブロックを取り出し、指定名を付けた文字列を返す。"""
    blocks = parse_profile_blocks(draft_text)
    if not blocks:
        return None
    lines = draft_text.splitlines(keepends=True)
    _, start, end = blocks[0]
    block_lines = list(lines[start : end + 1])
    block_lines[0] = f"profile {format_scfg_word(name)} {{\n"
    if block_lines and not block_lines[-1].endswith("\n"):
        block_lines[-1] += "\n"
    return "".join(block_lines)


def append_profile_block(config_text, block_text):
    out = config_text
    if out and not out.endswith("\n"):
        out += "\n"
    if out and not out.endswith("\n\n"):
        out += "\n"
    return out + block_text


def replace_profile_block(config_text, name, new_block_text):
    lines = config_text.splitlines(keepends=True)
    for bname, start, end in parse_profile_blocks(config_text):
        if bname == name:
            return "".join(lines[:start]) + new_block_text + "".join(lines[end + 1 :])
    return None


def remove_profile_block(config_text, name):
    lines = config_text.splitlines(keepends=True)
    for bname, start, end in parse_profile_blocks(config_text):
        if bname == name:
            before = lines[:start]
            after = lines[end + 1 :]
            # ブロック前後の余分な空行が連続しないように1行だけ詰める。
            while after and after[0].strip() == "" and (not before or before[-1].strip() == ""):
                after.pop(0)
            while before and before[-1].strip() == "" and not after:
                before.pop()
            return "".join(before + after)
    return None


def promote_profile_block(config_text, name):
    """指定名の profile ブロックを最初の profile 位置へ移動し、起動時の既定にする。"""
    blocks = parse_profile_blocks(config_text)
    if not blocks:
        return None
    target_idx = None
    for idx, (bname, _, _) in enumerate(blocks):
        if bname == name:
            target_idx = idx
            break
    if target_idx is None:
        return None
    if target_idx == 0:
        return config_text

    lines = config_text.splitlines(keepends=True)
    _, start, end = blocks[target_idx]
    target_lines = list(lines[start : end + 1])
    if target_lines and not target_lines[-1].endswith("\n"):
        target_lines[-1] += "\n"
    target_text = "".join(target_lines)

    remaining = remove_profile_block(config_text, name)
    rem_blocks = parse_profile_blocks(remaining)
    rem_lines = remaining.splitlines(keepends=True)
    insert_at = rem_blocks[0][1] if rem_blocks else len(rem_lines)
    return "".join(rem_lines[:insert_at]) + target_text + "\n" + "".join(rem_lines[insert_at:])


def get_current_profile():
    proc = run_cmd(["kanshictl", "status"])
    if proc.returncode != 0:
        return False, None
    try:
        data = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError:
        return True, None
    current = data.get("current_profile")
    return True, (str(current) if current else None)


def switch_profile(name, silent=False):
    proc = run_cmd(["kanshictl", "switch", name])
    if proc.returncode == 0:
        if not silent:
            notify("ディスプレイ配置を切り替えました", name)
        return 0
    if not silent:
        err = (proc.stderr or proc.stdout or "").strip()
        if "does not match" in err:
            notify("プロファイルを切り替えられません", f"「{name}」は現在のモニター構成に一致しません")
        elif "not found" in err.lower():
            notify("プロファイルが見つかりません", name)
        else:
            notify("プロファイル切替に失敗しました", err or name)
    return 1


def reload_kanshi(silent=False):
    proc = run_cmd(["kanshictl", "reload"])
    if proc.returncode == 0:
        if not silent:
            notify("kanshi の設定を再読み込みしました")
        return 0
    if not silent:
        err = (proc.stderr or proc.stdout or "").strip()
        notify("kanshi の再読み込みに失敗しました", err)
    return 1


def run_fuzzel_index(entries, prompt, mesg, select_idx=None):
    cmd = list(FUZZEL_BASE_ARGS) + ["--index", f"--prompt={prompt}", f"--mesg={mesg}"]
    if select_idx is not None:
        cmd.append(f"--select-index={select_idx}")
    stdin_text = "\n".join(entries) + "\n"
    proc = run_cmd(cmd, input_text=stdin_text)
    if proc.returncode != 0:
        return None
    try:
        idx = int(proc.stdout.strip())
    except ValueError:
        return None
    if 0 <= idx < len(entries):
        return idx
    return None


def run_fuzzel_prompt(prompt, mesg):
    cmd = list(FUZZEL_BASE_ARGS) + [f"--prompt-only={prompt}", f"--mesg={mesg}"]
    proc = run_cmd(cmd)
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def run_wdisplays_isolated(initial_text):
    """wdisplays 1.3.0 を一時 config と no-op kanshictl 上で起動し、終了後の draft 内容を返す。

    wdisplays 1.3.0（src/store.c）は Apply のたびに PATH 上の kanshictl reload を実行するため、
    編集中に kanshi が既存の先頭プロファイルへ巻き戻すのを防ぐ目的で一時的な no-op kanshictl を先頭に置く。
    """
    with tempfile.TemporaryDirectory(prefix="kanshi-switch-") as tmp:
        tmp_dir = pathlib.Path(tmp)
        draft = tmp_dir / "config"
        draft.write_text(initial_text, encoding="utf-8")

        noop = tmp_dir / "kanshictl"
        noop.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        noop.chmod(stat.S_IRWXU)

        env = os.environ.copy()
        env["WDISPLAYS_KANSHI_CONFIG"] = str(draft)
        env["PATH"] = f"{tmp_dir}:{env.get('PATH', '')}"

        run_cmd(["wdisplays", "--kanshi"], env=env)
        try:
            return draft.read_text(encoding="utf-8")
        except OSError:
            return ""


def create_profile_flow(config_path, explicit_name=None):
    if not is_writable_config(config_path):
        notify("設定ファイルへ書き込めません", str(config_path))
        return 1

    name = explicit_name
    if name is None:
        name = run_fuzzel_prompt(
            "新規プロファイル名 > ",
            "名前を入力して Enter（次に開く wdisplays で Apply → ウィンドウを閉じて保存）",
        )
        if name is None:
            return 0
    name = name.strip()
    if not name or "\n" in name or "\r" in name:
        notify("プロファイル名が無効です")
        return 1

    existing = parse_local_named_profiles(config_path)
    if name in existing:
        notify("同名のプロファイルが既にあります", f"「{name}」を変えるには編集を使ってください")
        return 1

    draft_text = run_wdisplays_isolated("")
    block_text = extract_named_block(draft_text, name)
    if block_text is None:
        reload_kanshi(silent=True)
        notify("プロファイル作成をキャンセルしました", "wdisplays で Apply されませんでした")
        return 0

    try:
        current_text = pathlib.Path(config_path).read_text(encoding="utf-8")
    except OSError:
        current_text = ""
    atomic_write_text(config_path, append_profile_block(current_text, block_text))
    reload_kanshi(silent=True)
    switch_profile(name, silent=True)
    notify("プロファイルを作成しました", name)
    return 0


def edit_profile_flow(config_path, explicit_name=None):
    if not is_writable_config(config_path):
        notify("設定ファイルへ書き込めません", str(config_path))
        return 1

    local_profiles = parse_local_named_profiles(config_path)
    if not local_profiles:
        notify("編集できる名前付きプロファイルがありません")
        return 1

    name = explicit_name
    if name is None:
        _, current = get_current_profile()
        labels = [f"● {p}  (現在)" if p == current else f"○ {p}" for p in local_profiles]
        select_idx = local_profiles.index(current) if current in local_profiles else None
        idx = run_fuzzel_index(
            labels,
            "編集するプロファイル > ",
            "選択すると wdisplays が開きます（Apply → ウィンドウを閉じて保存）",
            select_idx=select_idx,
        )
        if idx is None:
            return 0
        name = local_profiles[idx]

    if name not in local_profiles:
        notify("プロファイルが見つかりません", name)
        return 1

    current_text = pathlib.Path(config_path).read_text(encoding="utf-8")
    lines = current_text.splitlines(keepends=True)
    original_block = None
    for bname, start, end in parse_profile_blocks(current_text):
        if bname == name:
            original_block = "".join(lines[start : end + 1])
            break
    if original_block is None:
        notify("プロファイルが見つかりません", name)
        return 1

    # 編集対象の配置から始められるよう先に切り替える（現在の接続構成と一致しない場合はそのまま開く）。
    switch_profile(name, silent=True)
    draft_text = run_wdisplays_isolated(original_block)
    if draft_text == original_block:
        reload_kanshi(silent=True)
        return 0

    new_block = extract_named_block(draft_text, name)
    if new_block is None:
        reload_kanshi(silent=True)
        notify("プロファイル更新に失敗しました", name)
        return 1

    updated = replace_profile_block(current_text, name, new_block)
    if updated is None:
        notify("プロファイルが見つかりません", name)
        return 1

    atomic_write_text(config_path, updated)
    reload_kanshi(silent=True)
    switch_profile(name, silent=True)
    notify("プロファイルを更新しました", name)
    return 0


def delete_profile_flow(config_path, explicit_name=None):
    if not is_writable_config(config_path):
        notify("設定ファイルへ書き込めません", str(config_path))
        return 1

    local_profiles = parse_local_named_profiles(config_path)
    if not local_profiles:
        notify("削除できる名前付きプロファイルがありません")
        return 1

    name = explicit_name
    if name is None:
        _, current = get_current_profile()
        labels = [f"● {p}  (現在)" if p == current else f"○ {p}" for p in local_profiles]
        idx = run_fuzzel_index(
            labels,
            "削除するプロファイル > ",
            "選択したプロファイルを kanshi/config から削除します（Git で復元可能）",
        )
        if idx is None:
            return 0
        name = local_profiles[idx]

    current_text = pathlib.Path(config_path).read_text(encoding="utf-8")
    updated = remove_profile_block(current_text, name)
    if updated is None:
        notify("プロファイルが見つかりません", name)
        return 1

    atomic_write_text(config_path, updated)
    reload_kanshi(silent=True)
    notify("プロファイルを削除しました", name)
    return 0


def set_default_profile_flow(config_path, explicit_name=None):
    if not is_writable_config(config_path):
        notify("設定ファイルへ書き込めません", str(config_path))
        return 1

    local_profiles = parse_local_named_profiles(config_path)
    if not local_profiles:
        notify("既定に設定できる名前付きプロファイルがありません")
        return 1

    default_name = local_profiles[0]
    name = explicit_name
    if name is None:
        labels = [f"★ {p}  (現在の既定)" if p == default_name else f"○ {p}" for p in local_profiles]
        idx = run_fuzzel_index(
            labels,
            "起動時の既定 > ",
            "選んだプロファイルを kanshi/config の先頭へ移動します",
            select_idx=0,
        )
        if idx is None:
            return 0
        name = local_profiles[idx]

    current_text = pathlib.Path(config_path).read_text(encoding="utf-8")
    updated = promote_profile_block(current_text, name)
    if updated is None:
        notify("プロファイルが見つかりません", name)
        return 1

    if updated != current_text:
        atomic_write_text(config_path, updated)
        reload_kanshi(silent=True)
    notify("起動時の既定プロファイルを設定しました", name)
    return 0


def build_menu(profiles, local_profiles, writable, current_profile, kanshi_ok):
    entries = []
    select_idx = None
    default_profile = local_profiles[0] if local_profiles else None
    for name in profiles:
        is_current = bool(current_profile and name == current_profile)
        is_default = bool(len(profiles) > 1 and default_profile and name == default_profile)
        if is_current:
            select_idx = len(entries)
        tags = []
        if is_current:
            tags.append("現在")
        if is_default:
            tags.append("既定")
        prefix = "●" if is_current else ("★" if is_default else "○")
        suffix = f"  ({'・'.join(tags)})" if tags else ""
        entries.append(("switch", name, f"{prefix} {name}{suffix}"))

    if writable:
        entries.append(("create", None, "＋ 新規プロファイルを作成 (wdisplays)"))
        if len(local_profiles) >= 2:
            entries.append(("set_default", None, "★ 起動時の既定を変更"))
        if local_profiles:
            entries.append(("edit", None, "✎ 既存プロファイルを編集 (wdisplays)"))
            entries.append(("delete", None, "✕ プロファイルを削除"))
    entries.append(("reload", None, "↻ 再読み込み (kanshictl reload)"))
    entries.append(("wdisplays_temp", None, "⚙ 一時調整・保存なし (wdisplays --no-kanshi)"))

    if not kanshi_ok:
        mesg = "kanshi.service が応答しません"
    elif current_profile:
        mesg = f"現在: {current_profile}"
    elif not profiles:
        mesg = "名前付きプロファイル未登録（「＋ 新規プロファイルを作成」から追加できます）"
    else:
        mesg = "現在: 一致プロファイルなし"
    return entries, select_idx, mesg


def run_picker(config_path):
    profiles = parse_named_profiles(config_path)
    local_profiles = parse_local_named_profiles(config_path)
    writable = is_writable_config(config_path)
    kanshi_ok, current_profile = get_current_profile()
    entries, select_idx, mesg = build_menu(profiles, local_profiles, writable, current_profile, kanshi_ok)

    idx = run_fuzzel_index(
        [label for _, _, label in entries],
        "ディスプレイ > ",
        mesg,
        select_idx=select_idx,
    )
    if idx is None:
        return 0

    action, target, _ = entries[idx]
    if action == "switch":
        return switch_profile(target)
    if action == "create":
        return create_profile_flow(config_path)
    if action == "set_default":
        return set_default_profile_flow(config_path)
    if action == "edit":
        return edit_profile_flow(config_path)
    if action == "delete":
        return delete_profile_flow(config_path)
    if action == "reload":
        return reload_kanshi()
    if action == "wdisplays_temp":
        spawn_detached(["wdisplays", "--no-kanshi"])
        return 0
    return 0


def main(argv):
    args = list(argv[1:])
    explicit_config = None
    if len(args) >= 2 and args[0] == "--config":
        explicit_config = args[1]
        args = args[2:]

    config_path = resolve_config_path(explicit_config)

    if not args:
        return run_picker(config_path)
    if args == ["--list"]:
        for name in parse_named_profiles(config_path):
            print(name)
        return 0
    if args == ["--status-json"]:
        kanshi_ok, current_profile = get_current_profile()
        local_profiles = parse_local_named_profiles(config_path)
        payload = {
            "profiles": parse_named_profiles(config_path),
            "current": current_profile or "",
            "default": local_profiles[0] if local_profiles else "",
            "kanshi_ok": kanshi_ok,
        }
        print(json.dumps(payload, ensure_ascii=False))
        return 0
    if args[0] == "--create" and len(args) <= 2:
        return create_profile_flow(config_path, args[1] if len(args) == 2 else None)
    if args[0] == "--set-default" and len(args) <= 2:
        return set_default_profile_flow(config_path, args[1] if len(args) == 2 else None)
    if args[0] == "--edit" and len(args) <= 2:
        return edit_profile_flow(config_path, args[1] if len(args) == 2 else None)
    if args[0] == "--delete" and len(args) <= 2:
        return delete_profile_flow(config_path, args[1] if len(args) == 2 else None)
    if len(args) == 1 and not args[0].startswith("-"):
        return switch_profile(args[0])

    print(
        "usage: kanshi-switch [--config <path>] [--list | --status-json | --create [name] | --set-default [name] | --edit [name] | --delete [name] | <profile>]",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
