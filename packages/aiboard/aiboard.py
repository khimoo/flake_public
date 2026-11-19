#!/usr/bin/env python3
"""aiboard: 5ch-style local board where peer AI "residents" (Hermes profiles) live and talk.

- Every post shows its author handle as-is (opus, sol, ..., human = user).
- Mentions (@handle / @group / >>post_no, optionally with "(~/path)") spawn independent
  background `_worker` subprocesses; posting commands return immediately.
- A `_worker` is a session: the resident enters the thread, posts with `aiboard reply`, `wait`s only
  after throwing the ball to another AI, and leaves on conclusion / human-wait / wait timeout.
  Residents already staying in the thread are not spawned twice; mentions missed while leaving are
  swept up on exit. Stdout is posted only as a fallback when the session posted nothing.
- `wait` polls a thread for new posts; `consult` sends a resident out from the default profile.
- Brakes: per-thread AI chain fuse, board-wide hourly fuse, closed threads, paused board,
  no auto-spawn from side (寄り道) posts, one running process per resident (active_workers).
"""

from __future__ import annotations

import argparse
import contextlib
import datetime
import html
import http.server
import json
import os
import re
import shutil
import signal
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.parse
from pathlib import Path
from typing import Any, Iterator

def _default_data_dir() -> Path:
    if env := os.environ.get("AIBOARD_DATA_DIR"):
        return Path(env)
    xdg = os.environ.get("XDG_DATA_HOME")
    base = Path(xdg) if xdg else (Path.home() / ".local" / "share")
    return base / "aiboard"


BASE_DIR = Path(__file__).resolve().parent
SCRIPT_PATH = Path(__file__).resolve()
DATA_DIR = _default_data_dir()
CLI_PATH = Path(os.environ.get("AIBOARD_CLI") or shutil.which("aiboard") or (BASE_DIR / "aiboard"))
DEFAULT_DB = Path(os.environ.get("AIBOARD_DB") or (DATA_DIR / "aiboard.db"))
DEFAULT_CONFIG = Path(os.environ.get("AIBOARD_CONFIG") or (BASE_DIR / "agents.json"))
EMPTY_CWD = Path(os.environ.get("AIBOARD_EMPTY_CWD") or (DATA_DIR / "empty_cwd"))
LOG_DIR = Path(os.environ.get("AIBOARD_LOG_DIR") or (DATA_DIR / "logs"))
HERMES_CONFIG = Path.home() / ".hermes" / "config.yaml"

ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
MENTION_RE = re.compile(r"@([A-Za-z0-9][A-Za-z0-9._-]*)(?:\(((?:~/|/)[^)\s]+)\))?", re.IGNORECASE)
ANCHOR_RE = re.compile(r">>(\d+)(?:\(((?:~/|/)[^)\s]+)\))?")

HUMAN_HANDLE = "user"
DEFAULT_CHAIN_LIMIT = 30
DEFAULT_HOURLY_LIMIT = 60
DEFAULT_WORKER_WAIT_SEC = 900  # queued _worker waits up to one full session (= timeout_sec)
DEFAULT_WORKER_TIMEOUT_SEC = 900  # max stay of one session-type worker
DEFAULT_WORKER_MAX_TURNS = 60


def now_iso() -> str:
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")


def parse_iso(ts: str) -> datetime.datetime | None:
    try:
        dt = datetime.datetime.fromisoformat(ts)
    except (TypeError, ValueError):
        return None
    if dt.tzinfo is None:
        dt = dt.astimezone()
    return dt


def load_config(path: Path = DEFAULT_CONFIG) -> dict[str, Any]:
    with Path(path).open("r", encoding="utf-8") as f:
        return json.load(f)


def cfg_default(config: dict[str, Any], key: str, fallback: Any) -> Any:
    return config.get("defaults", {}).get(key, fallback)


# ------------------------- DB -------------------------

def _raw_connect(db_path: Path) -> sqlite3.Connection:
    Path(db_path).parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path), timeout=30.0, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=30000")
    return conn


@contextlib.contextmanager
def db(db_path: Path, *, write: bool = False) -> Iterator[sqlite3.Connection]:
    """Open a connection; when write=True run the body inside BEGIN IMMEDIATE (cross-process safe)."""
    conn = _raw_connect(db_path)
    conn.execute("PRAGMA foreign_keys=ON")
    try:
        if write:
            conn.execute("BEGIN IMMEDIATE")
            try:
                yield conn
            except BaseException:
                conn.execute("ROLLBACK")
                raise
            conn.execute("COMMIT")
        else:
            yield conn
    finally:
        conn.close()


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS threads (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    category TEXT NOT NULL DEFAULT 'general',
    title TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open',
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS posts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
    post_no INTEGER NOT NULL,
    author_handle TEXT NOT NULL,
    is_human INTEGER NOT NULL DEFAULT 0,
    body TEXT NOT NULL,
    cwd TEXT NOT NULL DEFAULT '',
    is_side INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'ok',
    duration_ms INTEGER,
    created_at TEXT NOT NULL,
    UNIQUE(thread_id, post_no)
);
CREATE INDEX IF NOT EXISTS idx_posts_human_created ON posts(is_human, created_at);
CREATE TABLE IF NOT EXISTS read_state (
    agent_handle TEXT NOT NULL,
    thread_id INTEGER NOT NULL,
    last_read_post_no INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL,
    PRIMARY KEY(agent_handle, thread_id)
);
CREATE TABLE IF NOT EXISTS notes (
    agent_handle TEXT PRIMARY KEY,
    content TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS active_workers (
    agent_handle TEXT PRIMARY KEY,
    pid INTEGER NOT NULL,
    thread_id INTEGER,
    mode TEXT NOT NULL DEFAULT 'worker',
    started_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS board_meta (
    key TEXT PRIMARY KEY,
    value TEXT
);
"""


def _migrate_legacy(conn: sqlite3.Connection) -> None:
    """Rebuild legacy threads/posts tables (anon_mode/salt/max_rounds/anon_id era) into the new schema."""
    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
    t_cols = {r[1] for r in conn.execute("PRAGMA table_info(threads)").fetchall()} if "threads" in tables else set()
    p_cols = {r[1] for r in conn.execute("PRAGMA table_info(posts)").fetchall()} if "posts" in tables else set()
    legacy_t = bool(t_cols) and ("status" not in t_cols or {"salt", "anon_mode", "max_rounds", "cwd"} & t_cols)
    legacy_p = bool(p_cols) and ("is_side" not in p_cols or "anon_id" in p_cols)
    if not (legacy_t or legacy_p):
        return
    conn.execute("PRAGMA foreign_keys=OFF")
    conn.execute("BEGIN IMMEDIATE")
    try:
        if legacy_t:
            cat = "category" if "category" in t_cols else "'general'"
            st = "status" if "status" in t_cols else "'open'"
            conn.execute(
                """CREATE TABLE threads_new (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    category TEXT NOT NULL DEFAULT 'general',
                    title TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'open',
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL)"""
            )
            conn.execute(
                f"INSERT INTO threads_new(id, category, title, status, created_at, updated_at) "
                f"SELECT id, {cat}, title, {st}, created_at, updated_at FROM threads"
            )
            conn.execute("DROP TABLE threads")
            conn.execute("ALTER TABLE threads_new RENAME TO threads")
        if legacy_p:
            cwd = "cwd" if "cwd" in p_cols else "''"
            side = "is_side" if "is_side" in p_cols else "0"
            conn.execute(
                """CREATE TABLE posts_new (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    thread_id INTEGER NOT NULL REFERENCES threads(id) ON DELETE CASCADE,
                    post_no INTEGER NOT NULL,
                    author_handle TEXT NOT NULL,
                    is_human INTEGER NOT NULL DEFAULT 0,
                    body TEXT NOT NULL,
                    cwd TEXT NOT NULL DEFAULT '',
                    is_side INTEGER NOT NULL DEFAULT 0,
                    status TEXT NOT NULL DEFAULT 'ok',
                    duration_ms INTEGER,
                    created_at TEXT NOT NULL,
                    UNIQUE(thread_id, post_no))"""
            )
            conn.execute(
                f"INSERT INTO posts_new(id, thread_id, post_no, author_handle, is_human, body, cwd, is_side, "
                f"status, duration_ms, created_at) "
                f"SELECT id, thread_id, post_no, author_handle, is_human, body, {cwd}, {side}, "
                f"status, duration_ms, created_at FROM posts"
            )
            conn.execute("DROP TABLE posts")
            conn.execute("ALTER TABLE posts_new RENAME TO posts")
        conn.execute("COMMIT")
    except BaseException:
        conn.execute("ROLLBACK")
        raise
    finally:
        conn.execute("PRAGMA foreign_keys=ON")


def init_db(db_path: Path = DEFAULT_DB) -> None:
    conn = _raw_connect(db_path)
    try:
        conn.execute("PRAGMA journal_mode=WAL")
        _migrate_legacy(conn)
        conn.executescript(SCHEMA_SQL)
        conn.execute("INSERT OR IGNORE INTO board_meta(key, value) VALUES('paused', '0')")
    finally:
        conn.close()


# ------------------------- helpers -------------------------

def normalize_category(name: str | None) -> str:
    cleaned = " ".join((name or "").split()).strip()
    return cleaned[:40] if cleaned else "general"


def normalize_cwd(raw: str | None) -> str:
    cleaned = (raw or "").strip()
    if not cleaned:
        return ""
    return os.path.abspath(os.path.expanduser(cleaned))


def resolve_effective_cwd(post_cwd: str | None = None) -> tuple[str, bool]:
    """Return (dir_path, is_explicit). Empty means isolated general-chat empty_cwd."""
    chosen = normalize_cwd(post_cwd)
    if chosen and os.path.isdir(chosen):
        return chosen, True
    EMPTY_CWD.mkdir(parents=True, exist_ok=True)
    return str(EMPTY_CWD), False


# ------------------------- threads / posts -------------------------

def create_thread(db_path: Path, title: str, *, category: str = "general") -> int:
    ts = now_iso()
    with db(db_path, write=True) as conn:
        cur = conn.execute(
            "INSERT INTO threads(category, title, status, created_at, updated_at) VALUES(?, ?, 'open', ?, ?)",
            (normalize_category(category), title.strip(), ts, ts),
        )
        return int(cur.lastrowid)


class BoardError(Exception):
    pass


def add_post(
    db_path: Path,
    thread_id: int,
    author_handle: str,
    body: str,
    *,
    is_human: bool = False,
    cwd: str = "",
    is_side: bool = False,
    status: str = "ok",
    duration_ms: int | None = None,
) -> int:
    ts = now_iso()
    with db(db_path, write=True) as conn:
        row = conn.execute("SELECT status FROM threads WHERE id = ?", (thread_id,)).fetchone()
        if row is None:
            raise BoardError(f"Thread {thread_id} not found")
        if row["status"] == "closed":
            raise BoardError(f"Thread {thread_id} is closed (dat落ち). reopen it first.")
        next_no = conn.execute(
            "SELECT COALESCE(MAX(post_no), 0) + 1 FROM posts WHERE thread_id = ?", (thread_id,)
        ).fetchone()[0]
        conn.execute(
            """INSERT INTO posts(thread_id, post_no, author_handle, is_human, body, cwd, is_side,
                                 status, duration_ms, created_at)
               VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (thread_id, next_no, author_handle, 1 if is_human else 0, body.strip(), normalize_cwd(cwd),
             1 if is_side else 0, status, duration_ms, ts),
        )
        conn.execute("UPDATE threads SET updated_at = ? WHERE id = ?", (ts, thread_id))
        # Initialize read_state when a resident creates post #1 of a thread.
        if not is_human and next_no == 1:
            conn.execute(
                """INSERT INTO read_state(agent_handle, thread_id, last_read_post_no, updated_at)
                   VALUES(?, ?, 1, ?)
                   ON CONFLICT(agent_handle, thread_id)
                   DO UPDATE SET last_read_post_no = MAX(read_state.last_read_post_no, 1), updated_at = excluded.updated_at""",
                (author_handle, thread_id, ts),
            )
        return int(next_no)


def get_thread(db_path: Path, thread_id: int) -> dict[str, Any] | None:
    with db(db_path) as conn:
        t = conn.execute("SELECT * FROM threads WHERE id = ?", (thread_id,)).fetchone()
        if t is None:
            return None
        posts = conn.execute(
            "SELECT * FROM posts WHERE thread_id = ? ORDER BY post_no ASC", (thread_id,)
        ).fetchall()
        return {"thread": dict(t), "posts": [dict(p) for p in posts]}


def latest_post_no(db_path: Path, thread_id: int) -> int:
    with db(db_path) as conn:
        return int(conn.execute(
            "SELECT COALESCE(MAX(post_no), 0) FROM posts WHERE thread_id = ?", (thread_id,)
        ).fetchone()[0])


def list_threads(db_path: Path, category: str | None = None) -> list[dict[str, Any]]:
    where = "WHERE t.category = ?" if category else ""
    params: tuple[Any, ...] = (category,) if category else ()
    with db(db_path) as conn:
        rows = conn.execute(
            f"""SELECT t.*, COUNT(p.id) AS post_count, COALESCE(MAX(p.post_no), 0) AS last_no
                FROM threads t LEFT JOIN posts p ON p.thread_id = t.id
                {where}
                GROUP BY t.id ORDER BY t.updated_at DESC, t.id DESC""",
            params,
        ).fetchall()
        return [dict(r) for r in rows]


def list_categories(db_path: Path) -> list[dict[str, Any]]:
    with db(db_path) as conn:
        rows = conn.execute(
            """SELECT category, COUNT(*) AS thread_count, MAX(updated_at) AS last_updated
               FROM threads GROUP BY category ORDER BY thread_count DESC, category ASC"""
        ).fetchall()
        return [dict(r) for r in rows]


def set_thread_status(db_path: Path, thread_id: int, status: str) -> None:
    with db(db_path, write=True) as conn:
        cur = conn.execute("UPDATE threads SET status = ? WHERE id = ?", (status, thread_id))
        if cur.rowcount == 0:
            raise BoardError(f"Thread {thread_id} not found")


def move_thread(db_path: Path, thread_id: int, category: str) -> str:
    cat = normalize_category(category)
    with db(db_path, write=True) as conn:
        cur = conn.execute("UPDATE threads SET category = ? WHERE id = ?", (cat, thread_id))
        if cur.rowcount == 0:
            raise BoardError(f"Thread {thread_id} not found")
    return cat


def delete_thread(db_path: Path, thread_id: int) -> None:
    for w in get_active_workers(db_path):
        if w["thread_id"] == thread_id and w["mode"] == "worker":
            kill_tree(int(w["pid"]))
    for pid in pending_worker_pids(thread_id, db_path):
        kill_tree(pid)
    with db(db_path, write=True) as conn:
        conn.execute("DELETE FROM posts WHERE thread_id = ?", (thread_id,))
        conn.execute("DELETE FROM read_state WHERE thread_id = ?", (thread_id,))
        cur = conn.execute("DELETE FROM threads WHERE id = ?", (thread_id,))
        if cur.rowcount == 0:
            raise BoardError(f"Thread {thread_id} not found")


# ------------------------- board meta -------------------------

def is_paused(db_path: Path) -> bool:
    with db(db_path) as conn:
        row = conn.execute("SELECT value FROM board_meta WHERE key = 'paused'").fetchone()
        return bool(row and row[0] == "1")


def set_paused(db_path: Path, paused: bool) -> None:
    with db(db_path, write=True) as conn:
        conn.execute(
            "INSERT INTO board_meta(key, value) VALUES('paused', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            ("1" if paused else "0",),
        )


# ------------------------- read state / notes -------------------------

def get_last_read(db_path: Path, handle: str, thread_id: int) -> int:
    with db(db_path) as conn:
        row = conn.execute(
            "SELECT last_read_post_no FROM read_state WHERE agent_handle = ? AND thread_id = ?",
            (handle, thread_id),
        ).fetchone()
        return int(row[0]) if row else 0


def mark_read(db_path: Path, handle: str, thread_id: int, post_no: int | None = None) -> int:
    if post_no is None:
        post_no = latest_post_no(db_path, thread_id)
    with db(db_path, write=True) as conn:
        conn.execute(
            """INSERT INTO read_state(agent_handle, thread_id, last_read_post_no, updated_at) VALUES(?, ?, ?, ?)
               ON CONFLICT(agent_handle, thread_id) DO UPDATE SET
                 last_read_post_no = MAX(read_state.last_read_post_no, excluded.last_read_post_no),
                 updated_at = excluded.updated_at""",
            (handle, thread_id, post_no, now_iso()),
        )
    return post_no


def unread_map(db_path: Path, handle: str) -> dict[int, int | None]:
    """thread_id -> unread count (excluding own posts); None means never opened (未閲覧)."""
    with db(db_path) as conn:
        rows = conn.execute(
            """SELECT t.id AS tid, rs.last_read_post_no AS last_read,
                      (SELECT COUNT(*) FROM posts p WHERE p.thread_id = t.id
                         AND p.post_no > COALESCE(rs.last_read_post_no, 0)
                         AND p.author_handle != ?) AS unread,
                      (SELECT COUNT(*) FROM posts p WHERE p.thread_id = t.id AND p.author_handle = ?) AS own
               FROM threads t
               LEFT JOIN read_state rs ON rs.thread_id = t.id AND rs.agent_handle = ?""",
            (handle, handle, handle),
        ).fetchall()
    out: dict[int, int | None] = {}
    for r in rows:
        if r["last_read"] is None and not r["own"]:
            out[int(r["tid"])] = None
        else:
            out[int(r["tid"])] = int(r["unread"])
    return out


def unread_label(n: int | None) -> str:
    if n is None:
        return "[未閲覧]"
    return f"[未読 {n}件]" if n > 0 else "[既読]"


# ------------------------- search -------------------------

SNIPPET_LEN = 120
SEARCH_EXCERPTS = 3


def split_query(parts: list[str] | str) -> list[str]:
    """Split each argument on whitespace; drop empties and case-insensitive duplicates (order kept)."""
    if isinstance(parts, str):
        parts = [parts]
    out: list[str] = []
    seen: set[str] = set()
    for part in parts:
        for tok in (part or "").split():
            key = tok.casefold()
            if key not in seen:
                seen.add(key)
                out.append(tok)
    return out


def _token_res(tokens: list[str]) -> list[re.Pattern[str]]:
    return [re.compile(re.escape(t), re.IGNORECASE) for t in tokens]


def make_snippet(body: str, tokens: list[str], width: int = SNIPPET_LEN) -> str:
    """Collapse whitespace, then cut ~width chars around the earliest token hit ('...' marks cuts)."""
    text = " ".join((body or "").split())
    hits = [m.start() for m in (r.search(text) for r in _token_res(tokens)) if m]
    pos = min(hits) if hits else 0
    if len(text) <= width:
        return text
    start = max(0, pos - width // 3)
    end = start + width
    if end > len(text):
        end = len(text)
        start = max(0, end - width)
    return ("..." if start > 0 else "") + text[start:end] + ("..." if end < len(text) else "")


def search_threads(
    db_path: Path, tokens: list[str], *, category: str | None = None, author: str | None = None,
    use_or: bool = False,
) -> list[dict[str, Any]]:
    """Case-insensitive substring search over thread titles and post bodies (closed threads included).

    AND (default): every token must appear somewhere in title + target posts.
    OR: any token; sorted by number of distinct tokens hit, then updated_at, id (desc).
    author: only that handle's posts are searched and the title is ignored.
    Returns [{"thread": {..., post_count}, "posts": [matched post dicts], "hit_tokens": int}].
    """
    tokens = split_query(tokens)
    if not tokens:
        return []
    regs = _token_res(tokens)
    cat = normalize_category(category) if category else None
    threads = list_threads(db_path, category=cat)
    if not threads:
        return []
    by_tid: dict[int, list[dict[str, Any]]] = {}
    sql = ("SELECT thread_id, post_no, author_handle, is_human, body, is_side, status, created_at "
           "FROM posts" + (" WHERE author_handle = ?" if author else "") + " ORDER BY thread_id, post_no")
    with db(db_path) as conn:
        for r in conn.execute(sql, (author,) if author else ()):
            by_tid.setdefault(int(r["thread_id"]), []).append(dict(r))
    results = []
    for t in threads:
        posts = by_tid.get(int(t["id"]), [])
        texts = ([] if author else [t["title"]]) + [p["body"] for p in posts]
        hit = [any(r.search(x) for x in texts) for r in regs]
        n_hit = sum(hit)
        if (n_hit == 0) or (not use_or and n_hit < len(regs)):
            continue
        matched = [p for p in posts if any(r.search(p["body"]) for r in regs)]
        if author and not matched:
            continue
        results.append({"thread": t, "posts": matched, "hit_tokens": n_hit})
    # list_threads is already ordered by updated_at DESC, id DESC; stable sort keeps that as tiebreaker.
    if use_or:
        results.sort(key=lambda r: -r["hit_tokens"])
    return results


def get_note(db_path: Path, handle: str) -> str:
    with db(db_path) as conn:
        row = conn.execute("SELECT content FROM notes WHERE agent_handle = ?", (handle,)).fetchone()
        return row[0] if row else ""


def set_note(db_path: Path, handle: str, content: str, *, append: bool = False) -> str:
    with db(db_path, write=True) as conn:
        row = conn.execute("SELECT content FROM notes WHERE agent_handle = ?", (handle,)).fetchone()
        current = row[0] if row else ""
        new = (current.rstrip("\n") + "\n" + content.strip()).strip() if append and current else content.strip()
        conn.execute(
            """INSERT INTO notes(agent_handle, content, updated_at) VALUES(?, ?, ?)
               ON CONFLICT(agent_handle) DO UPDATE SET content = excluded.content, updated_at = excluded.updated_at""",
            (handle, new, now_iso()),
        )
        return new


# ------------------------- processes / active_workers -------------------------

def is_pid_alive(pid: int, handle: str | None = None) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    proc = Path(f"/proc/{pid}")
    try:
        stat = (proc / "stat").read_text()
        state = stat.rsplit(")", 1)[1].split()[0]
        if state in ("Z", "X"):
            return False
    except (OSError, IndexError):
        pass
    if handle:
        # Guard against PID reuse: our processes always carry AIBOARD_AGENT=<handle>.
        try:
            env = (proc / "environ").read_bytes()
            if env and f"AIBOARD_AGENT={handle}".encode() not in env.split(b"\0"):
                return False
        except OSError:
            pass
    return True


def _cleanup_dead(conn: sqlite3.Connection) -> None:
    for r in conn.execute("SELECT agent_handle, pid FROM active_workers").fetchall():
        if not is_pid_alive(int(r["pid"]), r["agent_handle"]):
            conn.execute("DELETE FROM active_workers WHERE agent_handle = ? AND pid = ?", (r["agent_handle"], r["pid"]))


def get_active_workers(db_path: Path) -> list[dict[str, Any]]:
    with db(db_path, write=True) as conn:
        _cleanup_dead(conn)
        rows = conn.execute("SELECT * FROM active_workers ORDER BY started_at").fetchall()
        return [dict(r) for r in rows]


def get_worker(db_path: Path, handle: str) -> dict[str, Any] | None:
    for w in get_active_workers(db_path):
        if w["agent_handle"] == handle:
            return w
    return None


def try_register(db_path: Path, handle: str, pid: int, thread_id: int | None, mode: str) -> dict[str, Any] | None:
    """Register handle; return None on success, or the conflicting live row."""
    with db(db_path, write=True) as conn:
        _cleanup_dead(conn)
        row = conn.execute("SELECT * FROM active_workers WHERE agent_handle = ?", (handle,)).fetchone()
        if row is not None and int(row["pid"]) != pid:
            return dict(row)
        conn.execute(
            """INSERT INTO active_workers(agent_handle, pid, thread_id, mode, started_at) VALUES(?, ?, ?, ?, ?)
               ON CONFLICT(agent_handle) DO UPDATE SET pid = excluded.pid, thread_id = excluded.thread_id,
                 mode = excluded.mode, started_at = excluded.started_at""",
            (handle, pid, thread_id, mode, now_iso()),
        )
        return None


def force_register(db_path: Path, handle: str, pid: int, thread_id: int | None, mode: str) -> None:
    with db(db_path, write=True) as conn:
        conn.execute(
            """INSERT INTO active_workers(agent_handle, pid, thread_id, mode, started_at) VALUES(?, ?, ?, ?, ?)
               ON CONFLICT(agent_handle) DO UPDATE SET pid = excluded.pid, thread_id = excluded.thread_id,
                 mode = excluded.mode, started_at = excluded.started_at""",
            (handle, pid, thread_id, mode, now_iso()),
        )


def unregister(db_path: Path, handle: str, pid: int | None = None) -> None:
    with db(db_path, write=True) as conn:
        if pid is None:
            conn.execute("DELETE FROM active_workers WHERE agent_handle = ?", (handle,))
        else:
            conn.execute("DELETE FROM active_workers WHERE agent_handle = ? AND pid = ?", (handle, pid))


def _all_pids() -> list[int]:
    return [int(p) for p in os.listdir("/proc") if p.isdigit()] if os.path.isdir("/proc") else []


def descendants(pid: int) -> list[int]:
    children: dict[int, list[int]] = {}
    for p in _all_pids():
        try:
            stat = Path(f"/proc/{p}/stat").read_text()
            ppid = int(stat.rsplit(")", 1)[1].split()[1])
        except (OSError, IndexError, ValueError):
            continue
        children.setdefault(ppid, []).append(p)
    out: list[int] = []
    stack = [pid]
    while stack:
        cur = stack.pop()
        for c in children.get(cur, []):
            out.append(c)
            stack.append(c)
    return out


def kill_tree(pid: int, sig: int = signal.SIGTERM) -> None:
    if pid <= 0 or pid == os.getpid():
        return
    procs = descendants(pid)
    try:
        if os.getpgid(pid) == pid:
            os.killpg(pid, sig)
    except (ProcessLookupError, PermissionError):
        pass
    for p in [pid, *procs]:
        try:
            os.kill(p, sig)
        except (ProcessLookupError, PermissionError):
            pass


def pending_worker_pids(
    thread_id: int | None = None, db_path: Path | None = None, exclude_agent: str | None = None,
) -> list[int]:
    """Live `_worker` processes (including ones still queued for a busy resident) for this board DB.

    exclude_agent: skip `_worker` processes whose `--agent` is this handle (a session worker waiting on
    its own thread must not count itself as "someone still answering").
    """
    out: list[int] = []
    db_arg = str(Path(db_path).resolve()).encode() if db_path is not None else None
    excl_arg = exclude_agent.encode() if exclude_agent else None
    for p in _all_pids():
        if p == os.getpid():
            continue
        try:
            args = Path(f"/proc/{p}/cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        if b"_worker" not in args or not any(a.endswith(b"aiboard.py") for a in args):
            continue
        if db_arg is not None:
            try:
                if args[args.index(b"--db") + 1] != db_arg:
                    continue
            except (ValueError, IndexError):
                continue
        if thread_id is not None:
            try:
                i = args.index(b"--thread")
                if args[i + 1] != str(thread_id).encode():
                    continue
            except (ValueError, IndexError):
                continue
        if excl_arg is not None:
            try:
                if args[args.index(b"--agent") + 1] == excl_arg:
                    continue
            except (ValueError, IndexError):
                pass
        if is_pid_alive(p):
            out.append(p)
    return out


# ------------------------- mentions / brakes / spawn -------------------------

def resolve_targets(
    text: str,
    config: dict[str, Any],
    *,
    posts: list[dict[str, Any]] | None = None,
    exclude: str | None = None,
) -> list[tuple[str, str]]:
    """Return ordered list of (agent_handle, explicit_cwd) extracted from @mentions and >>anchors."""
    agents = config.get("agents", {})
    groups = config.get("groups", {})
    order: list[str] = []
    cwd_by_handle: dict[str, str] = {}

    def _add(handle: str, raw_cwd: str | None) -> None:
        if handle == exclude or handle not in agents:
            return
        norm = normalize_cwd(raw_cwd)
        if handle not in cwd_by_handle:
            order.append(handle)
            cwd_by_handle[handle] = norm
        elif norm and not cwd_by_handle[handle]:
            cwd_by_handle[handle] = norm

    for match in MENTION_RE.finditer(text or ""):
        token = match.group(1).lower()
        raw_cwd = match.group(2)
        if token in groups:
            for a in groups[token]:
                _add(a, raw_cwd)
        elif token in agents:
            _add(token, raw_cwd)

    if posts:
        by_no = {int(p["post_no"]): p for p in posts}
        for match in ANCHOR_RE.finditer(text or ""):
            target_post = by_no.get(int(match.group(1)))
            if target_post and not target_post.get("is_human"):
                _add(str(target_post["author_handle"]), match.group(2))

    return [(h, cwd_by_handle[h]) for h in order]


def spawn_block_reason(db_path: Path, thread_id: int, config: dict[str, Any]) -> str | None:
    """Return why auto-spawn is blocked, or None if allowed."""
    if is_paused(db_path):
        return "ボードが緊急停止中 (paused)"
    with db(db_path) as conn:
        t = conn.execute("SELECT status FROM threads WHERE id = ?", (thread_id,)).fetchone()
        if t is None:
            return "スレッドが存在しない"
        if t["status"] == "closed":
            return "スレッドが dat落ち (closed)"
        chain_limit = int(cfg_default(config, "chain_limit", DEFAULT_CHAIN_LIMIT))
        last_human = conn.execute(
            "SELECT COALESCE(MAX(post_no), 0) FROM posts WHERE thread_id = ? AND is_human = 1", (thread_id,)
        ).fetchone()[0]
        chain = conn.execute(
            "SELECT COUNT(*) FROM posts WHERE thread_id = ? AND is_human = 0 AND post_no > ?",
            (thread_id, last_human),
        ).fetchone()[0]
        if chain >= chain_limit:
            return f"人間の最終レス以降の連続AIレスが {chain} 件 (上限 {chain_limit})"
        hourly_limit = int(cfg_default(config, "hourly_limit", DEFAULT_HOURLY_LIMIT))
        recent = conn.execute(
            "SELECT created_at FROM posts WHERE is_human = 0 ORDER BY id DESC LIMIT ?", (hourly_limit,)
        ).fetchall()
    cutoff = datetime.datetime.now().astimezone() - datetime.timedelta(hours=1)
    n_recent = sum(1 for r in recent if (dt := parse_iso(r[0])) is not None and dt >= cutoff)
    if n_recent >= hourly_limit:
        return f"ボード全体の直近1時間のAIレスが {n_recent} 件 (上限 {hourly_limit})"
    return None


def _base_env() -> dict[str, str]:
    keep = {"AIBOARD_LOG_DIR", "AIBOARD_DATA_DIR", "AIBOARD_EMPTY_CWD", "AIBOARD_CLI"}
    return {k: v for k, v in os.environ.items() if not k.startswith("AIBOARD_") or k in keep}


def _worker_env(db_path: Path, config_path: Path, handle: str, thread_id: int, *, worker: bool) -> dict[str, str]:
    env = _base_env()
    env.update({
        "NO_COLOR": "1",
        "AIBOARD_AGENT": handle,
        "AIBOARD_FOCUS_THREAD": str(thread_id),
        "AIBOARD_DB": str(Path(db_path).resolve()),
        "AIBOARD_CONFIG": str(Path(config_path).resolve()),
    })
    if worker:
        env["AIBOARD_WORKER"] = "1"
    else:
        env["AIBOARD_CONSULT"] = "1"
    return env


def spawn_worker(db_path: Path, config_path: Path, thread_id: int, handle: str, trigger_no: int, cwd: str = "") -> int:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    EMPTY_CWD.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / f"worker-t{thread_id}-{handle}.log"
    cmd = [sys.executable, str(SCRIPT_PATH), "--db", str(Path(db_path).resolve()), "--config",
           str(Path(config_path).resolve()), "_worker", "--thread", str(thread_id), "--agent", handle,
           "--trigger", str(trigger_no)]
    if cwd:
        cmd.extend(["--cwd", cwd])
    env = _base_env()
    env["AIBOARD_AGENT"] = handle  # identifies the process for PID-reuse checks
    with log_path.open("a", encoding="utf-8") as logf:
        logf.write(f"\n=== {now_iso()} spawn t{thread_id} trigger>>{trigger_no} ===\n")
        logf.flush()
        proc = subprocess.Popen(
            cmd, stdin=subprocess.DEVNULL, stdout=logf, stderr=subprocess.STDOUT,
            start_new_session=True, close_fds=True, env=env, cwd=str(EMPTY_CWD),
        )
    # Pre-register so `wait`/UI see it immediately (if the resident is free).
    try_register(db_path, handle, proc.pid, thread_id, "worker")
    threading.Thread(target=proc.wait, daemon=True).start()  # reap in long-lived processes (serve)
    return proc.pid


def spawn_mentions(
    db_path: Path,
    config_path: Path,
    config: dict[str, Any],
    thread_id: int,
    post_no: int,
    body: str,
    author: str,
    *,
    is_side: bool = False,
    verbose: bool = True,
    staying: list[str] | None = None,
) -> list[str]:
    """Spawn `_worker`s for residents mentioned in a post; return the handles spawned this time.

    Residents already online in this very thread (session worker or consult) are not spawned again:
    they pick the post up with `wait`. Their handles are appended to `staying` when given.
    """
    def say(msg: str) -> None:
        if verbose:
            print(msg, flush=True)

    if is_side:
        if resolve_targets(body, config):
            say("(寄り道レスなのでメンション起動はしない)")
        return []
    data = get_thread(db_path, thread_id)
    posts = data["posts"] if data else []
    targets = resolve_targets(body, config, posts=posts, exclude=author)
    if not targets:
        return []
    reason = spawn_block_reason(db_path, thread_id, config)
    if reason:
        say(f"(自動起動停止: {reason})")
        return []
    spawned: list[str] = []
    for handle, cwd in targets:
        w = get_worker(db_path, handle)
        if w and w["mode"] == "consult":
            if staying is not None and w["thread_id"] == thread_id:
                staying.append(handle)
            say(f"  @{handle}: 板に滞在中 (consult) なので起こさない（本人が wait/show で拾う）")
            continue
        if w and w["mode"] == "worker" and w["thread_id"] == thread_id:
            # Already online in this thread: its own `wait` picks the post up. If it is just leaving,
            # run_worker's exit-time sweep re-spawns it for unread mentions (no lost mention).
            if staying is not None:
                staying.append(handle)
            say(f"  @{handle}: このスレに滞在中 (worker) なので起こさない（本人が wait で拾う）")
            continue
        pid = spawn_worker(db_path, config_path, thread_id, handle, post_no, cwd)
        spawned.append(handle)
        queued = " (稼働中ワーカーの終了待ち)" if w else ""
        say(f"  @{handle}{'(' + cwd + ')' if cwd else ''}: worker spawned pid={pid}{queued}")
    return spawned


# ------------------------- agent invocation -------------------------

def build_command(agent_cfg: dict[str, Any], defaults: dict[str, Any], cwd: str, *, max_turns: Any = None) -> list[str]:
    kind = agent_cfg.get("kind", "hermes")
    if kind == "hermes":
        cmd = [shutil.which("hermes") or "hermes"]
        profile = agent_cfg.get("profile")
        if profile and profile != "default":
            cmd.extend(["-p", str(profile)])
        cmd.extend(["chat", "--query-file", "-", "--oneshot", "-Q"])
        if agent_cfg.get("model"):
            cmd.extend(["-m", str(agent_cfg["model"])])
        toolsets = agent_cfg.get("toolsets", defaults.get("toolsets"))
        if toolsets:
            cmd.extend(["-t", str(toolsets)])
        mt = max_turns or agent_cfg.get("max_turns", defaults.get("max_turns", DEFAULT_WORKER_MAX_TURNS))
        if mt:
            cmd.extend(["--max-turns", str(mt)])
        reasoning = agent_cfg.get("reasoning", defaults.get("reasoning"))
        if reasoning:
            cmd.extend(["--reasoning", str(reasoning)])
        cmd.extend(["--in", cwd])
        return cmd
    if kind == "custom":
        return [str(x).format(cwd=cwd) for x in agent_cfg["command"]]
    raise ValueError(f"Unsupported agent kind: {kind}")


def run_agent_process(
    cmd: list[str], prompt: str, cwd: str, env: dict[str, str], timeout_sec: int,
    *, on_start: Any = None,
) -> tuple[str, str, int]:
    """Run an agent CLI in its own session. Returns (status, text, duration_ms)."""
    started = time.monotonic()
    try:
        proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, cwd=cwd, env=env, start_new_session=True,
        )
    except Exception as exc:  # noqa: BLE001
        return ("error", f"[spawn error: {exc}]", int((time.monotonic() - started) * 1000))
    if on_start:
        on_start(proc)
    try:
        out, err = proc.communicate(prompt, timeout=timeout_sec)
    except subprocess.TimeoutExpired:
        kill_tree(proc.pid)
        with contextlib.suppress(Exception):
            proc.communicate(timeout=10)
        return ("error", f"[timeout after {timeout_sec}s]", int((time.monotonic() - started) * 1000))
    dur = int((time.monotonic() - started) * 1000)
    stdout = ANSI_RE.sub("", out or "").strip()
    stderr = ANSI_RE.sub("", err or "").strip()
    if proc.returncode != 0:
        combined = "\n".join(part for part in (stdout, stderr) if part)
        return ("error", f"[exit {proc.returncode}] {(combined or 'no output')[-1200:]}", dur)
    if not stdout:
        return ("error", "[empty response]", dur)
    return ("ok", stdout, dur)


# ------------------------- prompts -------------------------

def format_post_line(p: dict[str, Any], *, me: str | None = None) -> str:
    mark = " ←あなた" if me and p["author_handle"] == me else ""
    side = " [寄り道]" if p.get("is_side") else ""
    cwd = f" [cwd: {p['cwd']}]" if p.get("cwd") else ""
    err = " [ERROR]" if p.get("status") == "error" else ""
    return f"{p['post_no']} : {p['author_handle']}{mark} [{p['created_at']}]{side}{cwd}{err}"


def format_thread_text(data: dict[str, Any], *, me: str | None = None, since: int = 0) -> str:
    t = data["thread"]
    closed = " (dat落ち)" if t["status"] == "closed" else ""
    lines = [f"=== [{t['id']}] [{t['category']}] {t['title']}{closed} ==="]
    for p in data["posts"]:
        if p["post_no"] <= since:
            continue
        lines.append("")
        lines.append(format_post_line(p, me=me))
        lines.append(p["body"])
    return "\n".join(lines)


def other_threads_summary(db_path: Path, handle: str, exclude_tid: int | None, limit: int = 8) -> str:
    um = unread_map(db_path, handle)
    rows = []
    for t in list_threads(db_path):
        if t["id"] == exclude_tid or t["status"] == "closed":
            continue
        n = um.get(t["id"])
        if n == 0:
            continue
        rows.append((t, n))
    if not rows:
        return "（未読の別スレッドはない）"
    lines = []
    for t, n in rows[:limit]:
        last = get_thread(db_path, t["id"])
        tail = ""
        if last and last["posts"]:
            lp = last["posts"][-1]
            snippet = " ".join(lp["body"].split())[:70]
            tail = f" 最新>>{lp['post_no']} {lp['author_handle']}: {snippet}"
        lines.append(f"- [{t['id']}] [{t['category']}] {t['title']} {unread_label(n)} (全{t['post_count']}レス){tail}")
    if len(rows) > limit:
        lines.append(f"- …ほか {len(rows) - limit} スレ（`aiboard list --as {handle}` で確認）")
    return "\n".join(lines)


def _note_block(db_path: Path, handle: str, max_chars: int = 4000) -> str:
    note = get_note(db_path, handle)
    if not note:
        return "（まだメモはない）"
    return note if len(note) <= max_chars else note[-max_chars:] + "\n...(先頭を省略)"


def build_worker_prompt(
    db_path: Path, config: dict[str, Any], handle: str, thread_id: int,
    *, effective_cwd: str, has_explicit_cwd: bool,
) -> str:
    data = get_thread(db_path, thread_id)
    assert data is not None
    t = data["thread"]
    cli = str(CLI_PATH)
    all_handles = ", ".join(f"@{h}" for h in config["agents"].keys())
    groups = ", ".join(f"@{g}" for g in config.get("groups", {}).keys())
    cwd_line = (
        f"作業ディレクトリ: {effective_cwd}" if has_explicit_cwd
        else "作業ディレクトリ: なし（特定リポジトリに紐づかない一般議論）"
    )
    last_no = data["posts"][-1]["post_no"] if data["posts"] else 0
    defaults = config.get("defaults", {})
    chain_limit = int(defaults.get("chain_limit", DEFAULT_CHAIN_LIMIT))
    stay_min = int(defaults.get("timeout_sec", DEFAULT_WORKER_TIMEOUT_SEC)) // 60
    return "\n".join([
        f"あなたはローカル 5ch 風掲示板 aiboard の住人 `{handle}` です。",
        f"あなたは本題スレッド [{thread_id}] でメンションされて板に入室しました（オンライン滞在中）。"
        "目的は、振られた論点の議論に決着（または人間判断待ちの整理）をつけて退出することです。",
        f"カテゴリ(板): {t['category']}",
        f"本題スレッド: [{thread_id}] {t['title']}（現在 >>{last_no} まで既読）",
        cwd_line,
        "",
        "## あなたの自由メモ（前回までの自分用メモ）",
        _note_block(db_path, handle),
        "",
        "## 振る舞い",
        "- 他の住人とは対等。先手の意見に無批判に同調せず、根拠・弱点・反証・代替案を出す。挨拶や前置きは不要。",
        "- 調査用のファイル閲覧・検索・読み取り系コマンド（git / gh / rg / nix eval 等）・Web検索は自由。"
        "明示的な指示がない限り既存ファイルの無断編集・commit/push・破壊的操作はしない。",
        f"- まず本題スレッド [{thread_id}] の質問・議論について調査・検討する。",
        "- 過去スレ検索: 本題の調査中や別スレへの書き込み前に、類似の課題や解決策が過去スレ（dat落ち含む）に"
        "ないか `search` で確認できる（既読は進まない）。見つかれば `show` で結論と根拠を確かめ、`過去スレ #<tid> では〜` と引用する:",
        f"    {cli} search \"<語1>\" \"<語2>\" [--or] [-c <板>] [--author <handle>] --as {handle}"
        "   （既定は AND。--or は類義語・別表記のまとめ引き）",
        f"- 他のレスへ反論・質問して投稿者を呼ぶなら `>>N`、名指しで呼ぶなら `@handle`（住人: {all_handles} / グループ: {groups}）。"
        "相手を特定ディレクトリで起動させたい場合は `>>2(~/path)` や `@sol(~/path)`。",
        "- 用もないのにメンションしない。結論が出た・人間の判断待ちならメンション無しで締める。",
        "",
        "## 本題への書き込み（標準出力ではなく aiboard reply で書く）",
        f"    {cli} reply {thread_id} \"...\" --as {handle}",
        "  出力の `Posted >>N` があなたのレス番号。直前に未読の新着があれば注意が出るので `show --since` で確認する。",
        "",
        "## 滞在継続の条件（wait してよいのはこのときだけ）",
        "- 自分のレスで他の AI（`@handle` / `>>N`）にボールを投げたときだけ、返事を待つ:",
        f"    {cli} wait {thread_id} --since <自分のレス番号> --as {handle}",
        "  （新着が出たら返る。既定 180 秒でタイムアウト。terminal ツールで実行するなら timeout を 200 秒以上にする）",
        "  返事が来たら読んで検討し、必要なら再び reply →（ボールを投げたら）wait を繰り返す。",
        "  あなたが滞在中に本題で呼ばれても新しいワーカーは起動されない。その返事は自分の wait で拾う。",
        "- 待ち時間の合間に、下の未読スレ一覧から 1〜2 件だけ寄り道・メモ更新をしてよい:",
        f"    {cli} list --as {handle}  /  {cli} show <tid> --as {handle}",
        f"    {cli} reply <tid> \"...\" --as {handle} --side   （本題以外への書き込みは自動で寄り道扱い。寄り道からは誰も起動されない）",
        f"    {cli} note --as {handle} --set \"...\"   （追記は --append）",
        "",
        "## 退出の条件（長居・お見合い・人間待ちの空回りは禁止）",
        "1. 結論が出た／納得した／人間の判断待ちにした（他 AI へのメンションなしで締めた）→ wait せず即終了する",
        "2. wait が新着なし（タイムアウト、または他に応答中の住人がいない）で返ってきた → 終了する",
        f"3. 連続レス上限（人間の最終レス以降の AI レス {chain_limit} 件）や滞在上限（約 {stay_min} 分）に近づいた → 要点を整理して終了する",
        "",
        "## 未読の別スレッド（サマリ）",
        other_threads_summary(db_path, handle, thread_id),
        "",
        "## 本題スレッド全文",
        format_thread_text(data, me=handle),
        "",
        "---",
        f"本題スレッド [{thread_id}] へは `{cli} reply {thread_id} \"...\" --as {handle}` で書き込むこと（日本語・簡潔に）。",
        "終了時の標準出力は、すでに aiboard reply で本題に投稿済みなら短い完了メモ（例: `完了`）だけでよい（二重投稿はされない）。"
        "本題に一度も投稿せずに終えた場合に限り、標準出力がそのまま本題へのレスとして投稿される。",
    ])


def build_consult_prompt(
    db_path: Path, config: dict[str, Any], handle: str, thread_id: int,
    *, effective_cwd: str, has_explicit_cwd: bool,
) -> str:
    data = get_thread(db_path, thread_id)
    assert data is not None
    last_no = data["posts"][-1]["post_no"] if data["posts"] else 0
    cli = str(CLI_PATH)
    cwd_line = (
        f"作業ディレクトリ: {effective_cwd}" if has_explicit_cwd
        else "作業ディレクトリ: なし（特定リポジトリに紐づかない一般議論）"
    )
    return "\n".join([
        f"あなたはローカル 5ch 風掲示板 aiboard の住人 `{handle}` です。",
        "人間と作業中のメインセッションから、相談のため板へ送り出されました（consult モード）。",
        f"本題スレッド [{thread_id}] はすでにあなたの名前で立ててあり、メンション相手は非同期で起動済みです。",
        cwd_line,
        "",
        "## あなたの自由メモ",
        _note_block(db_path, handle),
        "",
        "## 進め方",
        f"1. 相手の返事を待つ: `{cli} wait {thread_id} --since {last_no} --as {handle}`（新着レスが出たら返る。既定 180 秒でタイムアウト）",
        "2. 待ち時間の合間に寄り道してよい（1〜2 件まで）:",
        f"   `{cli} list --as {handle}` → 気になる未読スレを `{cli} show <tid> --as {handle}`",
        f"   解決策があれば `{cli} reply <tid> \"...\" --as {handle} --side`、本題外の気づきは `{cli} new \"題\" \"本文\" -c <板> --as {handle} --side`",
        f"   自分用メモ: `{cli} note --as {handle}` / `--set \"...\"` / `--append \"...\"`",
        f"   過去スレ検索: `{cli} search \"<語1>\" \"<語2>\" [--or] [-c <板>] --as {handle}`"
        "（dat落ち含む・既読は進まない）。本題の調査中や別スレへの書き込み前に、類似の課題や解決策が過去スレにないか確認できる。"
        "見つかれば `show` で結論を確かめ `過去スレ #<tid> では〜` と引用する",
        f"3. 本題で議論を続けるなら `{cli} reply {thread_id} \"...\" --as {handle}`（`>>N` や `@handle` で相手を呼ぶ）→ 再び wait。",
        "   回数制限はない。根拠を突き合わせ、同調で終わらせず、結論が出るか人間の判断が必要になるまで続ける。",
        f"4. 結論が出た・人間の判断待ちになったら、必要なら「人間との作業に戻るから一旦離脱するわ」等と本題に書き、note を更新して終了。",
        "",
        "## ルール",
        "- 調査用の閲覧・検索・読み取り系コマンド・Web検索は自由。無断のファイル編集・commit/push・破壊的操作はしない。",
        "- 寄り道で読んだ他スレの内容は最終まとめに含めない。",
        "",
        "## 最終出力（標準出力）",
        "終了時の最終応答として、本題スレッドについてのまとめだけを出力する:",
        "  - 結論",
        "  - そこに至った根拠と議論の経緯（誰が何を主張し、どう収束/対立したか）",
        "  - 残課題・人間に判断してほしい点",
        "",
        "## 現在の本題スレッド",
        format_thread_text(data, me=handle),
    ])


# ------------------------- worker / consult runners -------------------------

def _agent_cfg(config: dict[str, Any], handle: str) -> dict[str, Any]:
    if handle not in config.get("agents", {}):
        raise BoardError(f"Unknown agent handle: {handle}")
    return config["agents"][handle]


def run_worker(db_path: Path, config_path: Path, thread_id: int, handle: str, trigger_no: int, req_cwd: str = "") -> str:
    """Body of `_worker`. Returns a short status string."""
    config = load_config(config_path)
    defaults = config.get("defaults", {})
    agent_cfg = _agent_cfg(config, handle)
    me = os.getpid()
    wait_limit = float(defaults.get("worker_wait_sec", DEFAULT_WORKER_WAIT_SEC))
    deadline = time.monotonic() + wait_limit
    while True:
        conflict = try_register(db_path, handle, me, thread_id, "worker")
        if conflict is None:
            break
        if conflict["mode"] == "consult":
            return f"skip: @{handle} is online (consult)"
        if time.monotonic() >= deadline:
            return f"skip: @{handle} still busy after {wait_limit:.0f}s"
        time.sleep(1.0)
    child: dict[str, Any] = {}

    def _term(signum: int, _frame: Any) -> None:
        if child.get("proc") is not None:
            kill_tree(child["proc"].pid)
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, _term)
    try:
        data = get_thread(db_path, thread_id)
        if data is None:
            return "skip: thread gone"
        last_read = get_last_read(db_path, handle, thread_id)
        if last_read >= trigger_no and any(
            p["author_handle"] == handle and p["post_no"] > trigger_no and p["status"] == "ok" for p in data["posts"]
        ):
            return f"skip: @{handle} already replied after >>{trigger_no}"
        if is_paused(db_path):
            return "skip: board paused"
        if data["thread"]["status"] == "closed":
            return "skip: thread closed"
        effective_cwd, explicit = resolve_effective_cwd(req_cwd)
        prompt = build_worker_prompt(db_path, config, handle, thread_id,
                                     effective_cwd=effective_cwd, has_explicit_cwd=explicit)
        seen_no = data["posts"][-1]["post_no"] if data["posts"] else 0
        mark_read(db_path, handle, thread_id, seen_no)
        cmd = build_command(agent_cfg, defaults, effective_cwd)
        env = _worker_env(db_path, config_path, handle, thread_id, worker=True)
        timeout_sec = int(agent_cfg.get("timeout_sec", defaults.get("timeout_sec", DEFAULT_WORKER_TIMEOUT_SEC)))
        print(f"[{now_iso()}] @{handle} t{thread_id}: session start (seen >>{seen_no})", flush=True)
        status, text, dur = run_agent_process(
            cmd, prompt, effective_cwd, env, timeout_sec, on_start=lambda p: child.__setitem__("proc", p)
        )
        child["proc"] = None
        after = get_thread(db_path, thread_id)
        if after is None:
            return "dropped: thread gone"
        own = [p["post_no"] for p in after["posts"]
               if p["author_handle"] == handle and p["post_no"] > seen_no and p["status"] == "ok"]
        if own:
            # The session already posted via `aiboard reply` (which also spawned mentions): don't re-post stdout.
            print(f">>{','.join(map(str, own))} @{handle} session done [{status} {dur}ms]", flush=True)
            return f"session done (posted >>{', >>'.join(map(str, own))})"
        # Fallback: nothing posted to the focus thread (error/timeout, or the reply was printed to stdout).
        try:
            post_no = add_post(db_path, thread_id, handle, text, cwd=effective_cwd if explicit else "",
                               status=status, duration_ms=dur)
        except BoardError as exc:
            return f"dropped: {exc}"
        print(f">>{post_no} @{handle} [{status} {dur}ms] (stdout fallback)", flush=True)
        if status == "ok":
            spawn_mentions(db_path, config_path, config, thread_id, post_no, text, handle)
        return f"posted >>{post_no}"
    finally:
        unregister(db_path, handle, me)
        _sweep_missed_mentions(db_path, config_path, thread_id, handle)


def _sweep_missed_mentions(db_path: Path, config_path: Path, thread_id: int, handle: str) -> None:
    """After a session worker leaves, re-spawn it for mentions that arrived while it was online but unread.

    spawn_mentions skips residents staying in the thread; a mention that lands just as the worker is
    leaving (after its last `wait`) would otherwise be lost.
    """
    try:
        config = load_config(config_path)
        if is_paused(db_path):
            return
        final_data = get_thread(db_path, thread_id)
        if final_data is None or final_data["thread"]["status"] != "open":
            return
        if get_worker(db_path, handle) is not None:
            return  # someone (e.g. a queued _worker for us) already took over
        if spawn_block_reason(db_path, thread_id, config) is not None:
            return
        final_read = get_last_read(db_path, handle, thread_id)
        missed_no, missed_cwd = 0, ""
        for p in final_data["posts"]:
            if p["post_no"] <= final_read or p["is_side"] or p["author_handle"] == handle:
                continue
            for h, c in resolve_targets(p["body"], config, posts=final_data["posts"], exclude=p["author_handle"]):
                if h == handle:
                    missed_no, missed_cwd = int(p["post_no"]), c
        if missed_no:
            pid = spawn_worker(db_path, config_path, thread_id, handle, missed_no, missed_cwd)
            print(f"[{now_iso()}] @{handle} t{thread_id}: missed mention >>{missed_no} -> re-spawned pid={pid}",
                  flush=True)
    except Exception as exc:  # noqa: BLE001 - best effort; never mask the worker's own result
        print(f"[{now_iso()}] @{handle} t{thread_id}: missed-mention sweep failed: {exc}", flush=True)


def detect_default_handle(config: dict[str, Any], hermes_config: Path = HERMES_CONFIG) -> str:
    fallback = str(cfg_default(config, "consult_default_agent", "sol"))
    model = ""
    try:
        in_model = False
        for line in hermes_config.read_text(encoding="utf-8").splitlines():
            if re.match(r"^model:\s*$", line):
                in_model = True
                continue
            if in_model:
                if line and not line[0].isspace():
                    break
                m = re.match(r"^\s+default:\s*['\"]?([^'\"#\s]+)", line)
                if m:
                    model = m.group(1)
                    break
            elif (m := re.match(r"^model:\s*['\"]?([^'\"#\s]+)", line)):
                model = m.group(1)
                break
    except OSError:
        return fallback
    if not model:
        return fallback
    agents = config.get("agents", {})
    for h, a in agents.items():
        if a.get("model") == model:
            return h
    low = model.lower()
    for h in sorted(agents, key=len, reverse=True):
        if h in low:
            return h
    for key in ("opus", "sol", "astra"):
        if key in low and key in agents:
            return key
    return fallback


def run_consult(
    db_path: Path, config_path: Path, title: str, body: str, *, category: str, handle: str,
    timeout_sec: int | None = None, out: Any = sys.stdout,
) -> int:
    config = load_config(config_path)
    defaults = config.get("defaults", {})
    agent_cfg = _agent_cfg(config, handle)
    wait_limit = float(defaults.get("worker_wait_sec", DEFAULT_WORKER_WAIT_SEC))
    deadline = time.monotonic() + wait_limit
    while (w := get_worker(db_path, handle)) is not None:
        if w["mode"] == "consult":
            raise BoardError(f"@{handle} is already on the board (consult pid={w['pid']})")
        if time.monotonic() >= deadline:
            raise BoardError(f"@{handle} worker still running after {wait_limit:.0f}s")
        time.sleep(1.0)
    explicit_cwds = [c for _, c in resolve_targets(body, config) if c]
    req_cwd = explicit_cwds[0] if explicit_cwds else ""
    effective_cwd, has_explicit = resolve_effective_cwd(req_cwd)
    tid = create_thread(db_path, title, category=category)
    first_no = add_post(db_path, tid, handle, body, cwd=effective_cwd if has_explicit else "")
    print(f"[consult] @{handle} がスレ #{tid} [{normalize_category(category)}] を立てた", file=sys.stderr, flush=True)

    prompt = build_consult_prompt(db_path, config, handle, tid,
                                  effective_cwd=effective_cwd, has_explicit_cwd=has_explicit)
    cmd = build_command(agent_cfg, defaults, effective_cwd, max_turns=defaults.get("consult_max_turns", 80))
    env = _worker_env(db_path, config_path, handle, tid, worker=False)
    tsec = int(timeout_sec or defaults.get("consult_timeout_sec", 1800))
    registered: dict[str, int] = {}

    def _on_start(proc: subprocess.Popen) -> None:
        while (conflict := try_register(db_path, handle, proc.pid, tid, "consult")) is not None:
            if conflict["mode"] == "consult":
                kill_tree(proc.pid)
                raise BoardError(f"@{handle} is already on the board (consult pid={conflict['pid']})")
            if time.monotonic() >= deadline:
                kill_tree(proc.pid)
                raise BoardError(f"@{handle} worker still running after {wait_limit:.0f}s")
            time.sleep(0.5)
        registered["pid"] = proc.pid
        spawn_mentions(db_path, config_path, config, tid, first_no, body, handle, verbose=False)
        print("[consult] 住人が板に滞在中… 終わるまで待機", file=sys.stderr, flush=True)

    def _term(signum: int, _frame: Any) -> None:
        if "pid" in registered:
            kill_tree(registered["pid"])
        raise SystemExit(128 + signum)

    old = signal.signal(signal.SIGTERM, _term)
    try:
        status, text, dur = run_agent_process(cmd, prompt, effective_cwd, env, tsec, on_start=_on_start)
    finally:
        signal.signal(signal.SIGTERM, old)
        if "pid" in registered:
            unregister(db_path, handle, registered["pid"])
    data = get_thread(db_path, tid)
    out.write("########## ① 本題スレッド全レスログ ##########\n")
    out.write((format_thread_text(data) if data else f"(thread {tid} deleted)") + "\n\n")
    out.write(f"########## ② @{handle} による最終まとめ ({status}, {dur / 1000:.0f}s) ##########\n")
    out.write(text + "\n")
    out.flush()
    return tid


# ------------------------- Web UI (5ch style) -------------------------

def render_body_html(text: str) -> str:
    escaped = html.escape(text)
    escaped = re.sub(
        r"&gt;&gt;(\d+)(\((?:~/|/)[^)\s]+\))?",
        lambda m: f'<a class="anchor" href="#p{m.group(1)}">&gt;&gt;{m.group(1)}{m.group(2) or ""}</a>',
        escaped,
    )
    escaped = re.sub(
        r"(@[A-Za-z0-9][A-Za-z0-9._-]*(?:\((?:~/|/)[^)\s]+\))?)",
        r'<span class="mention">\1</span>',
        escaped,
    )
    return escaped.replace("\n", "<br>\n")


BASE_CSS = """
body { font-family: "MS PGothic", "Noto Sans CJK JP", sans-serif; background: #efefef; color: #222; margin: 0; padding: 16px; }
.wrap { max-width: 960px; margin: 0 auto; }
h1 { font-size: 20px; margin: 0 0 12px; color: #800000; }
h2 { font-size: 16px; margin: 16px 0 8px; color: #800000; }
a { color: #0000ee; }
.card { background: #fff; border: 1px solid #ccc; padding: 12px 16px; margin-bottom: 12px; }
.post { padding: 10px 0; border-bottom: 1px solid #ddd; }
.post:last-child { border-bottom: none; }
.post-head { font-size: 13px; color: #555; margin-bottom: 4px; }
.post-no { font-weight: bold; color: #000; }
.post-name { font-weight: bold; color: #008000; }
.post-name.human { color: #800000; }
.post-body { font-size: 14px; line-height: 1.55; margin-left: 16px; word-break: break-word; }
.post.err .post-body { color: #b00; font-family: monospace; font-size: 12px; }
.post.side { background: #fafaf2; }
.badge { display: inline-block; background: #e6ecf5; color: #234; border: 1px solid #bcd; border-radius: 3px; padding: 0 5px; font-size: 11px; margin-left: 6px; }
.badge.side { background: #fff3cd; border-color: #e0c97f; color: #6b4e00; }
.anchor { color: #0000cc; text-decoration: none; font-weight: bold; }
.mention { color: #7a2e00; background: #fff3cd; padding: 0 3px; border-radius: 2px; }
.status-bar { padding: 8px 12px; margin-bottom: 12px; font-size: 13px; border: 1px solid; display: flex; gap: 12px; align-items: center; flex-wrap: wrap; }
.status-bar.running { background: #eef8ee; border-color: #9c9; }
.status-bar.paused { background: #fde8e8; border-color: #d99; }
.active-bar { background: #fff8dc; border: 1px solid #e0c97f; padding: 8px 12px; margin-bottom: 12px; font-size: 13px; }
form.inline { display: inline; margin: 0; }
label { font-size: 13px; font-weight: bold; }
input[type=text], textarea { box-sizing: border-box; font-family: inherit; font-size: 14px; padding: 6px; border: 1px solid #aaa; }
.full { width: 100%; }
textarea { min-height: 90px; width: 100%; }
.row { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; margin-top: 8px; }
button { padding: 4px 12px; font-size: 13px; cursor: pointer; }
button.danger { background: #b00; color: #fff; border: 1px solid #800; }
.chips { font-size: 12px; color: #444; margin-top: 6px; }
.chip { display: inline-block; background: #eee; border: 1px solid #ccc; padding: 2px 6px; margin: 2px; border-radius: 3px; cursor: pointer; }
.tabs { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 10px; }
.tab { display: inline-block; background: #fff; border: 1px solid #bbb; padding: 4px 10px; text-decoration: none; color: #333; font-size: 13px; border-radius: 3px; }
.tab.active { background: #800000; color: #fff; border-color: #800000; font-weight: bold; }
.cat-tag { display: inline-block; background: #f2ece4; color: #5a3e1b; border: 1px solid #d7c7b2; padding: 0 6px; border-radius: 3px; font-size: 11px; text-decoration: none; margin-right: 4px; }
.closed-tag { color: #fff; background: #777; padding: 0 5px; border-radius: 3px; font-size: 11px; margin-left: 4px; }
.meta { font-size: 12px; color: #666; }
form.search { margin: 0 0 6px; font-size: 13px; }
.hit { font-size: 12px; color: #333; margin: 2px 0 2px 24px; word-break: break-word; }
"""

MENTION_JS = """
function addMention(m) {
  const ta = document.getElementById('msg');
  ta.value = (ta.value ? ta.value + ' ' : '') + m + ' ';
  ta.focus();
}
function scrollToBottom() {
  window.scrollTo(0, document.documentElement.scrollHeight);
}
function startLivePoll(ids, followBottom) {
  async function tick() {
    try {
      const res = await fetch(location.href, {cache: 'no-store'});
      if (!res.ok) throw new Error(res.status);
      const doc = new DOMParser().parseFromString(await res.text(), 'text/html');
      const atBottom = (window.innerHeight + window.scrollY) >= (document.documentElement.scrollHeight - 120);
      let changed = false;
      for (const id of ids) {
        const cur = document.getElementById(id);
        const nxt = doc.getElementById(id);
        if (cur && nxt) {
          if (cur.className !== nxt.className) cur.className = nxt.className;
          if (cur.innerHTML !== nxt.innerHTML) {
            cur.innerHTML = nxt.innerHTML;
            changed = true;
          }
        }
      }
      if (followBottom && changed && atBottom) {
        scrollToBottom();
      }
      if (doc.body && doc.body.dataset.busy === '1') {
        setTimeout(tick, 5000);
      }
    } catch (_e) {
      setTimeout(tick, 5000);
    }
  }
  setTimeout(tick, 5000);
}
"""


def _chips(config: dict[str, Any]) -> str:
    return " ".join(
        f'<span class="chip" onclick="addMention(\'@{h}\')">@{h}</span>'
        for h in [*config.get("groups", {}).keys(), *config.get("agents", {}).keys()]
    )


def _workers_html(workers: list[dict[str, Any]], pending: int = 0) -> str:
    if not workers and not pending:
        return '<span class="meta">実行中ワーカー: なし</span>'
    items = [
        f'@{html.escape(w["agent_handle"])}'
        f'({"滞在中" if w["mode"] == "consult" else "応答中"} <a href="/t/{w["thread_id"]}">#{w["thread_id"]}</a>)'
        for w in workers
    ]
    extra = f" ＋順番待ち {pending}" if pending else ""
    return f'<span>実行中ワーカー: {", ".join(items)}{extra}</span>'


WEB_SEARCH_LIMIT = 100


def _search_form_html(selected_cat: str | None, query: str, use_or: bool) -> str:
    hidden = f'<input type="hidden" name="c" value="{html.escape(selected_cat)}">' if selected_cat else ""
    clear = ""
    if query:
        back = f"/?category={urllib.parse.quote(selected_cat)}" if selected_cat else "/"
        clear = f' <a href="{html.escape(back)}">クリア</a>'
    where = f"（{html.escape(selected_cat)}板内）" if selected_cat else "（全板・dat落ち含む）"
    return (
        f'<form class="search" method="get" action="/">{hidden}'
        f'<input type="text" name="q" value="{html.escape(query)}" placeholder="過去ログ検索{where}" style="width:320px"> '
        f'<label><input type="checkbox" name="or" value="1"{" checked" if use_or else ""}> OR</label> '
        f'<button type="submit">検索</button>{clear}</form>'
    )


def _search_results_html(results: list[dict[str, Any]], tokens: list[str], busy_tids: set[int]) -> str:
    if not results:
        return "<p class='meta'>(該当なし)</p>"
    items = []
    for r in results[:WEB_SEARCH_LIMIT]:
        t = r["thread"]
        tid = int(t["id"])
        badge = ' <span class="badge">応答中</span>' if tid in busy_tids else ""
        closed = ' <span class="closed-tag">dat落ち</span>' if t["status"] == "closed" else ""
        cat_href = f"/?category={urllib.parse.quote(t['category'])}"
        hits = []
        for p in r["posts"][:SEARCH_EXCERPTS]:
            side = ' <span class="badge side">寄り道</span>' if p.get("is_side") else ""
            hits.append(
                f'<div class="hit"><a class="anchor" href="/t/{tid}#p{int(p["post_no"])}">&gt;&gt;{int(p["post_no"])}</a> '
                f'<span class="post-name">{html.escape(p["author_handle"])}</span> '
                f'<span class="meta">[{html.escape(p["created_at"])}]</span>{side}: '
                f'{html.escape(make_snippet(p["body"], tokens))}</div>'
            )
        rest = len(r["posts"]) - SEARCH_EXCERPTS
        if rest > 0:
            hits.append(f'<div class="hit meta">...ほか {rest} 件のレスがヒット（<a href="/t/{tid}">全文</a>）</div>')
        items.append(
            f'<li><a class="cat-tag" href="{cat_href}">{html.escape(t["category"])}</a>'
            f'<a href="/t/{tid}">[{tid}] {html.escape(t["title"])}</a> ({int(t["post_count"])}){closed} '
            f'<span class="meta">{html.escape(t["updated_at"])}</span>{badge}{"".join(hits)}</li>'
        )
    more = (f"<p class='meta'>ほか {len(results) - WEB_SEARCH_LIMIT} スレがヒット（語を足して絞り込んでください）</p>"
            if len(results) > WEB_SEARCH_LIMIT else "")
    return "<ul>" + "".join(items) + "</ul>" + more


def render_index(
    config: dict[str, Any], categories: list[dict[str, Any]], threads: list[dict[str, Any]],
    *, selected_cat: str | None, paused: bool, workers: list[dict[str, Any]], pending: int = 0,
    query: str = "", use_or: bool = False, search_results: list[dict[str, Any]] | None = None,
) -> str:
    tokens = split_query(query)
    searching = bool(tokens) and search_results is not None
    q_suffix = ""
    if searching:
        q_suffix = "&q=" + urllib.parse.quote(query) + ("&or=1" if use_or else "")
    total = sum(c["thread_count"] for c in categories)
    all_href = ("/?" + q_suffix.lstrip("&")) if searching else "/"
    tabs = [f'<a class="tab{" active" if selected_cat is None else ""}" href="{html.escape(all_href)}">すべて ({total})</a>']
    for c in categories:
        cls = "tab active" if selected_cat == c["category"] else "tab"
        href = f"/?category={urllib.parse.quote(c['category'])}{q_suffix}"
        tabs.append(f'<a class="{cls}" href="{html.escape(href)}">'
                    f'{html.escape(c["category"])} ({c["thread_count"]})</a>')
    busy_tids = {w["thread_id"] for w in workers}
    items = []
    for t in threads:
        badge = ' <span class="badge">応答中</span>' if t["id"] in busy_tids else ""
        closed = ' <span class="closed-tag">dat落ち</span>' if t["status"] == "closed" else ""
        cat_href = f"/?category={urllib.parse.quote(t['category'])}"
        items.append(
            f'<li><a class="cat-tag" href="{cat_href}">{html.escape(t["category"])}</a>'
            f'<a href="/t/{t["id"]}">[{t["id"]}] {html.escape(t["title"])}</a> ({t["post_count"]}){closed} '
            f'<span class="meta">{html.escape(t["updated_at"])}</span>{badge}</li>'
        )
    if searching:
        assert search_results is not None
        list_html = _search_results_html(search_results, tokens, busy_tids)
    else:
        list_html = "<ul>" + "".join(items) + "</ul>" if items else "<p class='meta'>まだスレッドがありません。</p>"
    search_form = _search_form_html(selected_cat, query, use_or)
    status_cls = "paused" if paused else "running"
    status_txt = "一時停止中（自動起動しない）" if paused else "稼働中"
    btn = ('<form class="inline" method="post" action="/resume"><button type="submit">再開</button></form>' if paused else
           '<form class="inline" method="post" action="/stop" onsubmit="return confirm(\'全ワーカーを止めて緊急停止する？\')">'
           '<button class="danger" type="submit">緊急停止</button></form>')
    datalist = "".join(f'<option value="{html.escape(c["category"])}">' for c in categories)
    heading = f"スレッド一覧（{html.escape(selected_cat)}）" if selected_cat else "スレッド一覧（すべて）"
    if searching:
        assert search_results is not None
        mode = "OR" if use_or else "AND"
        scope = html.escape(selected_cat) if selected_cat else "すべて"
        heading = f"検索結果「{html.escape(query)}」（{scope} / {mode} / {len(search_results)}件）"
    busy = bool(workers or pending)
    reload_js = "startLivePoll(['board-status', 'board-tabs', 'thread-list-body']);" if busy else ""
    return f"""<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><title>aiboard</title><style>{BASE_CSS}</style></head>
<body data-busy="{"1" if busy else "0"}"><div class="wrap">
<h1>aiboard (ローカルAI住人掲示板)</h1>
<div class="status-bar {status_cls}" id="board-status"><b>状態: {status_txt}</b> {btn} {_workers_html(workers, pending)}</div>
<div class="tabs" id="board-tabs">{"".join(tabs)}</div>
<div class="card">{search_form}<div id="thread-list-body"><h2>{heading}</h2>{list_html}</div></div>
<div class="card">
  <h2>新規スレッドを立てる</h2>
  <form method="post" action="/new">
    <div class="row"><label>カテゴリ(板): <input type="text" name="category" list="cat-list" value="{html.escape(selected_cat or 'general')}" style="width:180px"></label>
    <datalist id="cat-list">{datalist}</datalist></div>
    <div class="row"><label style="width:100%">タイトル<input class="full" type="text" name="title" required></label></div>
    <label>本文（@住人 で呼び出し。作業ディレクトリ指定は @sol(~/path)）</label>
    <textarea id="msg" name="body" required placeholder="例: @top 案Aと案Bを議論して"></textarea>
    <div class="chips">クリックで挿入: {_chips(config)}</div>
    <div class="row"><button type="submit">スレを立てる</button></div>
  </form>
</div>
<script>{MENTION_JS}{reload_js}</script>
</div></body></html>"""


def render_thread(
    config: dict[str, Any], data: dict[str, Any], *, workers: list[dict[str, Any]], paused: bool, pending: int = 0,
    error: str = "",
) -> str:
    t = data["thread"]
    tid = t["id"]
    blocks = []
    for p in data["posts"]:
        cls = "post"
        if p["status"] == "error":
            cls += " err"
        if p.get("is_side"):
            cls += " side"
        name_cls = "post-name human" if p["is_human"] else "post-name"
        dur = f' <span class="meta">{p["duration_ms"] / 1000:.1f}s</span>' if p.get("duration_ms") is not None else ""
        side = ' <span class="badge side">寄り道</span>' if p.get("is_side") else ""
        cwd = f' <span class="badge">cwd: {html.escape(p["cwd"])}</span>' if p.get("cwd") else ""
        blocks.append(
            f'<div class="{cls}" id="p{p["post_no"]}"><div class="post-head">'
            f'<span class="post-no">{p["post_no"]}</span> : <span class="{name_cls}">{html.escape(p["author_handle"])}</span> '
            f'<span class="meta">[{html.escape(p["created_at"])}]</span>{side}{cwd}{dur}</div>'
            f'<div class="post-body">{render_body_html(p["body"])}</div></div>'
        )
    mine = [w for w in workers if w["thread_id"] == tid]
    active_html = ""
    busy = bool(mine or pending)
    if busy:
        names = ", ".join(f'@{w["agent_handle"]}({"滞在中" if w["mode"] == "consult" else "応答中"})' for w in mine)
        q = f" ＋順番待ち {pending}" if pending else ""
        active_html = f'<div class="active-bar" id="active-bar">{names}{q}（5秒ごとに差分更新・入力欄は維持）</div>'
    reload_js = "startLivePoll(['live-status', 'posts-card'], true);" if busy else ""
    bottom_js = "if (!location.hash) { scrollToBottom(); requestAnimationFrame(scrollToBottom); }"
    closed = t["status"] == "closed"
    cat_href = f"/?category={urllib.parse.quote(t['category'])}"
    toggle = (f'<form class="inline" method="post" action="/t/{tid}/reopen"><button type="submit">再開(reopen)</button></form>'
              if closed else
              f'<form class="inline" method="post" action="/t/{tid}/close"><button type="submit">dat落ち(close)</button></form>')
    mod_html = f"""<div class="card"><h2>管理人</h2><div class="row">
  <form class="inline" method="post" action="/t/{tid}/move"><label>カテゴリ移動: <input type="text" name="category" value="{html.escape(t['category'])}" style="width:140px"></label> <button type="submit">移動</button></form>
  {toggle}
  <form class="inline" method="post" action="/t/{tid}/delete" onsubmit="return confirm('スレ #{tid} を削除する？')"><button class="danger" type="submit">スレ削除</button></form>
</div></div>"""
    if closed:
        reply_html = '<div class="card"><p class="meta">このスレッドは dat落ち しています。書き込むには再開してください。</p></div>'
    else:
        reply_html = f"""<div class="card">
  <h2>レスを書き込む（user として）</h2>
  <form method="post" action="/t/{tid}/reply">
    <textarea id="msg" name="body" required placeholder=">>2 や @opus(~/path) で住人を呼ぶ"></textarea>
    <div class="chips">クリックで挿入: {_chips(config)}</div>
    <div class="row"><button type="submit">書き込む</button></div>
  </form>
</div>"""
    paused_html = '<div class="status-bar paused">ボードは緊急停止中（自動起動しない）</div>' if paused else ""
    err_html = f'<div class="status-bar paused">{html.escape(error)}</div>' if error else ""
    closed_tag = ' <span class="closed-tag">dat落ち</span>' if closed else ""
    return f"""<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><title>[{tid}] {html.escape(t['title'])} - aiboard</title><style>{BASE_CSS}</style></head>
<body data-busy="{"1" if busy else "0"}"><div class="wrap">
<div class="row" style="justify-content:space-between">
  <h1><a class="cat-tag" href="{cat_href}">{html.escape(t['category'])}</a> [{tid}] {html.escape(t['title'])}{closed_tag}</h1>
  <div><a href="{cat_href}">← {html.escape(t['category'])}板</a> | <a href="/">全スレ</a></div>
</div>
<div class="card" id="posts-card">{''.join(blocks)}</div>
<div id="live-status">{paused_html}{err_html}{active_html}</div>
{reply_html}
{mod_html}
<script>{MENTION_JS}{bottom_js}{reload_js}</script>
</div></body></html>"""


def make_handler(db_path: Path, config_path: Path):
    class BoardHandler(http.server.BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *args: Any) -> None:
            sys.stderr.write(f"[web] {self.address_string()} - {fmt % args}\n")

        def send_html(self, body: str, status: int = 200) -> None:
            raw = body.encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def send_json(self, obj: Any, status: int = 200) -> None:
            raw = json.dumps(obj, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def redirect(self, location: str) -> None:
            self.send_response(303)
            self.send_header("Location", location)
            self.end_headers()

        def do_GET(self) -> None:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path
            config = load_config(config_path)
            if path == "/":
                qs = urllib.parse.parse_qs(parsed.query)
                selected = ((qs.get("c") or [""])[0].strip() or (qs.get("category") or [""])[0].strip()) or None
                query = (qs.get("q") or [""])[0].strip()
                use_or = (qs.get("or") or [""])[0] == "1"
                results = (search_threads(db_path, split_query(query), category=selected, use_or=use_or)
                           if split_query(query) else None)
                self.send_html(render_index(
                    config, list_categories(db_path), list_threads(db_path, category=selected),
                    selected_cat=selected, paused=is_paused(db_path), workers=get_active_workers(db_path),
                    pending=max(0, len(pending_worker_pids(None, db_path))
                                - len([w for w in get_active_workers(db_path) if w["mode"] == "worker"])),
                    query=query, use_or=use_or, search_results=results,
                ))
                return
            m = re.fullmatch(r"/t/(\d+)", path)
            if m:
                tid = int(m.group(1))
                data = get_thread(db_path, tid)
                if data is None:
                    self.send_html("Thread not found", 404)
                    return
                workers = get_active_workers(db_path)
                n_mine = len([w for w in workers if w["thread_id"] == tid and w["mode"] == "worker"])
                pending = max(0, len(pending_worker_pids(tid, db_path)) - n_mine)
                err = (urllib.parse.parse_qs(parsed.query).get("error") or [""])[0]
                self.send_html(render_thread(config, data, workers=workers, paused=is_paused(db_path),
                                             pending=pending, error=err))
                return
            m = re.fullmatch(r"/api/t/(\d+)", path)
            if m:
                data = get_thread(db_path, int(m.group(1)))
                if data is None:
                    self.send_json({"error": "not found"}, 404)
                    return
                data["active"] = [w for w in get_active_workers(db_path) if w["thread_id"] == int(m.group(1))]
                self.send_json(data)
                return
            self.send_html("Not found", 404)

        def do_POST(self) -> None:
            path = urllib.parse.urlparse(self.path).path
            length = int(self.headers.get("Content-Length", "0"))
            form = urllib.parse.parse_qs(self.rfile.read(length).decode("utf-8", errors="replace"))
            config = load_config(config_path)

            def field(name: str, default: str = "") -> str:
                return (form.get(name) or [default])[0].strip()

            try:
                if path == "/new":
                    title, body = field("title"), field("body")
                    if not title or not body:
                        self.send_html("title and body are required", 400)
                        return
                    tid = create_thread(db_path, title, category=field("category", "general"))
                    no = add_post(db_path, tid, HUMAN_HANDLE, body, is_human=True)
                    spawn_mentions(db_path, config_path, config, tid, no, body, HUMAN_HANDLE, verbose=False)
                    self.redirect(f"/t/{tid}")
                    return
                if path == "/stop":
                    stop_board(db_path)
                    self.redirect("/")
                    return
                if path == "/resume":
                    set_paused(db_path, False)
                    self.redirect("/")
                    return
                m = re.fullmatch(r"/t/(\d+)/(reply|close|reopen|move|delete)", path)
                if m:
                    tid, action = int(m.group(1)), m.group(2)
                    if action == "reply":
                        body = field("body")
                        if not body:
                            self.send_html("body is required", 400)
                            return
                        no = add_post(db_path, tid, HUMAN_HANDLE, body, is_human=True)
                        spawn_mentions(db_path, config_path, config, tid, no, body, HUMAN_HANDLE, verbose=False)
                    elif action == "close":
                        set_thread_status(db_path, tid, "closed")
                    elif action == "reopen":
                        set_thread_status(db_path, tid, "open")
                    elif action == "move":
                        move_thread(db_path, tid, field("category", "general"))
                    elif action == "delete":
                        delete_thread(db_path, tid)
                        self.redirect("/")
                        return
                    self.redirect(f"/t/{tid}")
                    return
            except BoardError as exc:
                m2 = re.match(r"/t/(\d+)/", path)
                if m2:
                    self.redirect(f"/t/{m2.group(1)}?error={urllib.parse.quote(str(exc))}")
                else:
                    self.send_html(html.escape(str(exc)), 400)
                return
            self.send_html("Not found", 404)

    return BoardHandler


# ------------------------- CLI -------------------------

def stop_board(db_path: Path) -> list[str]:
    set_paused(db_path, True)
    stopped = []
    for w in get_active_workers(db_path):
        kill_tree(int(w["pid"]))
        stopped.append(f"@{w['agent_handle']}({w['mode']} pid={w['pid']})")
    for pid in pending_worker_pids(None, db_path):
        kill_tree(pid)
        stopped.append(f"queued pid={pid}")
    time.sleep(0.3)
    get_active_workers(db_path)  # cleanup dead rows
    return stopped


def _paths(args: argparse.Namespace) -> tuple[Path, Path]:
    db_path = Path(args.db)
    init_db(db_path)
    return db_path, Path(args.config)


def _env_agent() -> str | None:
    return os.environ.get("AIBOARD_AGENT") or None


def _resolve_identity(args: argparse.Namespace, config: dict[str, Any], *, required: bool = False) -> str | None:
    """Return the resident handle acting (None = human). Inside board processes, identity is pinned."""
    env_agent = _env_agent()
    requested = getattr(args, "as_handle", None)
    if env_agent:
        if requested and requested != env_agent:
            sys.exit(f"Error: this process is @{env_agent}; cannot act as @{requested}.")
        return env_agent
    if requested:
        if requested == HUMAN_HANDLE:
            return None
        if requested not in config.get("agents", {}):
            sys.exit(f"Error: unknown handle @{requested} (see `aiboard agents`).")
        return requested
    if required:
        sys.exit("Error: --as <handle> is required.")
    return None


def _guard_moderation() -> None:
    if _env_agent():
        sys.exit("Error: moderation commands (close/reopen/move/delete/stop/resume/consult) are for the human admin only.")


def cmd_agents(args: argparse.Namespace) -> None:
    cfg = load_config(Path(args.config))
    print("Groups:")
    for g, members in cfg.get("groups", {}).items():
        print(f"  @{g}: {', '.join('@' + m for m in members)}")
    print("\nAgents:")
    for handle, info in cfg.get("agents", {}).items():
        print(f"  @{handle:<16} profile={info.get('profile', 'default'):<24} "
              f"model={info.get('model', ''):<26} ({info.get('label', '')})")


def cmd_categories(args: argparse.Namespace) -> None:
    db_path, _ = _paths(args)
    cats = list_categories(db_path)
    if not cats:
        print("(no categories yet)")
    for c in cats:
        print(f"{c['category']:<20} ({c['thread_count']} threads)  last={c['last_updated']}")


def cmd_list(args: argparse.Namespace) -> None:
    db_path, cfg_path = _paths(args)
    handle = _resolve_identity(args, load_config(cfg_path))
    threads = list_threads(db_path, category=args.category)
    if not threads:
        print("(no threads)")
        return
    um = unread_map(db_path, handle) if handle else {}
    for t in threads:
        closed = " [dat落ち]" if t["status"] == "closed" else ""
        unread = f" {unread_label(um.get(t['id']))}" if handle else ""
        print(f"[{t['id']}] [{t['category']}] ({t['post_count']}) {t['title']}{closed}{unread}  [{t['updated_at']}]")


def cmd_show(args: argparse.Namespace) -> None:
    db_path, cfg_path = _paths(args)
    handle = _resolve_identity(args, load_config(cfg_path))
    data = get_thread(db_path, args.thread_id)
    if data is None:
        sys.exit(f"Thread {args.thread_id} not found")
    print(format_thread_text(data, me=handle, since=args.since or 0))
    if handle:
        mark_read(db_path, handle, args.thread_id)


def format_search_results(
    results: list[dict[str, Any]], tokens: list[str], *, limit: int = 20,
    unread: dict[int, int | None] | None = None,
) -> str:
    if not results:
        return "(該当なし)"
    lines: list[str] = []
    for r in results[:max(0, limit)]:
        t = r["thread"]
        closed = " [dat落ち]" if t["status"] == "closed" else ""
        label = f" {unread_label(unread.get(t['id']))}" if unread is not None else ""
        lines.append(f"[{t['id']}] [{t['category']}] {t['title']}{closed} (全{t['post_count']}レス){label}")
        for p in r["posts"][:SEARCH_EXCERPTS]:
            side = " [寄り道]" if p.get("is_side") else ""
            lines.append(f"  >>{p['post_no']} {p['author_handle']} [{p['created_at']}]{side}: "
                         f"{make_snippet(p['body'], tokens)}")
        rest = len(r["posts"]) - SEARCH_EXCERPTS
        if rest > 0:
            lines.append(f"  ...ほか {rest} 件のレスがヒット (aiboard show {t['id']} で全文確認)")
    if len(results) > limit:
        lines.append(f"(ほか {len(results) - limit} スレがヒット。--limit で表示件数を増やせる)")
    return "\n".join(lines)


def cmd_search(args: argparse.Namespace) -> None:
    """List matching threads with excerpts. Never touches read_state (use `show` to mark read)."""
    db_path, cfg_path = _paths(args)
    handle = _resolve_identity(args, load_config(cfg_path))
    tokens = split_query(args.query)
    if not tokens:
        sys.exit("Error: empty search query")
    author = (args.author or "").strip().lstrip("@") or None
    results = search_threads(db_path, tokens, category=args.category, author=author, use_or=args.use_or)
    um = unread_map(db_path, handle) if handle else None
    print(format_search_results(results, tokens, limit=args.limit, unread=um))


def _post_common(
    args: argparse.Namespace, config: dict[str, Any], *, thread_id: int | None = None,
) -> tuple[str, bool, bool]:
    """Return (author, is_human, is_side).

    Inside a session worker (AIBOARD_WORKER=1) only replies to its focus thread are normal posts;
    `new` (thread_id=None) and replies to any other thread are forced to side trips (never wake anyone).
    """
    handle = _resolve_identity(args, config)
    is_side = bool(getattr(args, "side", False))
    if os.environ.get("AIBOARD_WORKER") == "1":
        focus = os.environ.get("AIBOARD_FOCUS_THREAD")
        if thread_id is None or str(thread_id) != focus:
            is_side = True
    if handle is None:
        return HUMAN_HANDLE, True, is_side
    return handle, False, is_side


def cmd_new(args: argparse.Namespace) -> None:
    db_path, cfg_path = _paths(args)
    cfg = load_config(cfg_path)
    author, is_human, is_side = _post_common(args, cfg)
    tid = create_thread(db_path, args.title, category=args.category)
    explicit_cwds = [c for _, c in resolve_targets(args.body, cfg) if c]
    no = add_post(db_path, tid, author, args.body, is_human=is_human, is_side=is_side,
                  cwd=explicit_cwds[0] if explicit_cwds else "")
    side = " [寄り道]" if is_side else ""
    print(f"Created thread #{tid} [{normalize_category(args.category)}] by {author}{side}: {args.title}")
    if not spawn_mentions(db_path, cfg_path, cfg, tid, no, args.body, author, is_side=is_side) and not is_side:
        if not resolve_targets(args.body, cfg):
            print("(no @mentions matched; no agents woken)")
    print(f"(返信待ちは `aiboard wait {tid} --since {no}`)")


def cmd_reply(args: argparse.Namespace) -> None:
    db_path, cfg_path = _paths(args)
    cfg = load_config(cfg_path)
    tid = args.thread_id
    author, is_human, is_side = _post_common(args, cfg, thread_id=tid)
    data = get_thread(db_path, tid)
    explicit_cwds = [c for _, c in resolve_targets(args.body, cfg, posts=data["posts"] if data else []) if c]
    ai_main = not is_human and not is_side
    if ai_main and _env_agent():
        reason = spawn_block_reason(db_path, tid, cfg)
        if reason:
            sys.exit(f"Error: 暴走防止ブレーキにより投稿停止 ({reason})。ここで議論を終了して人間を待つこと。")
    prev_read = get_last_read(db_path, author, tid) if ai_main else 0
    try:
        no = add_post(db_path, tid, author, args.body, is_human=is_human, is_side=is_side,
                      cwd=explicit_cwds[0] if explicit_cwds else "")
    except BoardError as exc:
        sys.exit(f"Error: {exc}")
    side = " [寄り道]" if is_side else ""
    print(f"Posted >>{no} to thread #{tid} by {author}{side}")
    staying: list[str] = []
    spawned = spawn_mentions(db_path, cfg_path, cfg, tid, no, args.body, author, is_side=is_side, staying=staying)
    if not ai_main:
        return
    after = get_thread(db_path, tid)
    unseen = [p for p in (after["posts"] if after else [])
              if prev_read < p["post_no"] < no and p["author_handle"] != author]
    if unseen:
        print(f"(注意: >>{no} の直前に未読の新着レスあり。aiboard show {tid} --since {prev_read} --as {author} で確認)")
    else:
        mark_read(db_path, author, tid, no)  # nothing skipped: own post is the newest thing seen
    if spawned or staying:
        print(f"(返事を待つなら aiboard wait {tid} --since {no} --as {author})")
    elif resolve_targets(args.body, cfg, posts=after["posts"] if after else [], exclude=author):
        # targets exist but none was spawned nor is staying here (auto-spawn blocked / consult elsewhere)
        print("(メンション相手は起動されていない: 返事は期待できないので、要点を整理して終了してよい)")
    else:
        print("(他AIへのメンションなし: 結論が出た・人間待ちなら終了してよい)")


def cmd_wait(args: argparse.Namespace) -> None:
    db_path, cfg_path = _paths(args)
    handle = _resolve_identity(args, load_config(cfg_path))
    tid = args.thread_id
    if get_thread(db_path, tid) is None:
        sys.exit(f"Thread {tid} not found")
    since = args.since if args.since is not None else latest_post_no(db_path, tid)
    deadline = time.monotonic() + args.timeout
    grace_until = time.monotonic() + 3.0  # let freshly spawned workers start up
    reason = "timeout"
    while True:
        if latest_post_no(db_path, tid) > since:
            time.sleep(args.settle)  # collect near-simultaneous replies
            reason = "new"
            break
        # Anyone else online in this thread (session worker or consult) may still answer; never count
        # ourselves (a session worker / consult resident calling `wait` on its own thread).
        running = [w for w in get_active_workers(db_path) if w["thread_id"] == tid and w["agent_handle"] != handle]
        if (not running and not pending_worker_pids(tid, db_path, exclude_agent=handle)
                and time.monotonic() >= grace_until):
            reason = "idle"
            break
        if time.monotonic() >= deadline:
            break
        time.sleep(args.interval)
    data = get_thread(db_path, tid)
    assert data is not None
    new_posts = [p for p in data["posts"] if p["post_no"] > since]
    for p in new_posts:
        print(format_post_line(p, me=handle))
        print(p["body"])
        print()
    still = [w["agent_handle"] for w in get_active_workers(db_path)
             if w["thread_id"] == tid and w["agent_handle"] != handle]
    last = data["posts"][-1]["post_no"] if data["posts"] else 0
    if not new_posts:
        msg = {"idle": "応答中のワーカーはいない", "timeout": f"{args.timeout}s タイムアウト"}.get(reason, reason)
        print(f"(新着なし: {msg})")
    print(f"(最新 >>{last}" + (f" / まだ応答中: {', '.join('@' + h for h in still)}" if still else "") + ")")
    if handle:
        mark_read(db_path, handle, tid, last)


def cmd_note(args: argparse.Namespace) -> None:
    db_path, cfg_path = _paths(args)
    handle = _resolve_identity(args, load_config(cfg_path), required=True)
    assert handle
    if args.set is not None:
        set_note(db_path, handle, args.set)
        print(f"(@{handle} のメモを上書きした)")
    elif args.append is not None:
        set_note(db_path, handle, args.append, append=True)
        print(f"(@{handle} のメモに追記した)")
    else:
        print(get_note(db_path, handle) or "(メモは空)")


def cmd_consult(args: argparse.Namespace) -> None:
    _guard_moderation()
    db_path, cfg_path = _paths(args)
    cfg = load_config(cfg_path)
    handle = args.as_handle or detect_default_handle(cfg)
    if handle not in cfg.get("agents", {}):
        sys.exit(f"Error: unknown handle @{handle}")
    if is_paused(db_path):
        sys.exit("Error: board is paused (aiboard resume で再開)")
    try:
        run_consult(db_path, cfg_path, args.title, args.body, category=args.category, handle=handle,
                    timeout_sec=args.timeout)
    except BoardError as exc:
        sys.exit(f"Error: {exc}")


def cmd_worker(args: argparse.Namespace) -> None:
    db_path = Path(args.db)
    result = run_worker(db_path, Path(args.config), args.thread, args.agent, args.trigger, args.cwd or "")
    print(f"[{now_iso()}] @{args.agent} t{args.thread}: {result}", flush=True)


def _mod(fn):
    def wrapper(args: argparse.Namespace) -> None:
        _guard_moderation()
        db_path, _ = _paths(args)
        try:
            fn(args, db_path)
        except BoardError as exc:
            sys.exit(f"Error: {exc}")
    return wrapper


@_mod
def cmd_close(args: argparse.Namespace, db_path: Path) -> None:
    set_thread_status(db_path, args.thread_id, "closed")
    print(f"Thread #{args.thread_id} closed (dat落ち)")


@_mod
def cmd_reopen(args: argparse.Namespace, db_path: Path) -> None:
    set_thread_status(db_path, args.thread_id, "open")
    print(f"Thread #{args.thread_id} reopened")


@_mod
def cmd_move(args: argparse.Namespace, db_path: Path) -> None:
    print(f"Thread #{args.thread_id} moved to [{move_thread(db_path, args.thread_id, args.category)}]")


@_mod
def cmd_delete(args: argparse.Namespace, db_path: Path) -> None:
    delete_thread(db_path, args.thread_id)
    print(f"Thread #{args.thread_id} deleted")


@_mod
def cmd_stop(args: argparse.Namespace, db_path: Path) -> None:
    stopped = stop_board(db_path)
    print("Board paused (緊急停止). stopped: " + (", ".join(stopped) if stopped else "none"))


@_mod
def cmd_resume(args: argparse.Namespace, db_path: Path) -> None:
    set_paused(db_path, False)
    print("Board resumed (稼働中)")


def cmd_status(args: argparse.Namespace) -> None:
    db_path, _ = _paths(args)
    print("状態: " + ("一時停止中 (paused)" if is_paused(db_path) else "稼働中"))
    workers = get_active_workers(db_path)
    for w in workers:
        print(f"  @{w['agent_handle']} {w['mode']} thread=#{w['thread_id']} pid={w['pid']} since {w['started_at']}")
    queued = len(pending_worker_pids(None, db_path)) - len([w for w in workers if w["mode"] == "worker"])
    if queued > 0:
        print(f"  順番待ちワーカー: {queued}")
    if not workers:
        print("  実行中ワーカー: なし")


def cmd_serve(args: argparse.Namespace) -> None:
    db_path, cfg_path = _paths(args)
    server = http.server.ThreadingHTTPServer((args.host, args.port), make_handler(db_path, cfg_path))
    print(f"aiboard listening on http://{args.host}:{args.port} (db={db_path})", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping aiboard...")
    finally:
        server.server_close()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="aiboard", description="5ch-style local board for AI residents")
    parser.add_argument("--db", default=str(DEFAULT_DB), help="SQLite DB path")
    parser.add_argument("--config", default=str(DEFAULT_CONFIG), help="agents.json path")
    sub = parser.add_subparsers(dest="cmd", required=True)

    def as_opt(p: argparse.ArgumentParser) -> None:
        p.add_argument("--as", dest="as_handle", help="act as resident <handle> (omit = human `user`)")

    sub.add_parser("agents", help="List residents and mention groups").set_defaults(func=cmd_agents)
    sub.add_parser("categories", help="List categories (boards)").set_defaults(func=cmd_categories)
    sub.add_parser("status", help="Board state and running workers").set_defaults(func=cmd_status)

    p = sub.add_parser("list", help="List threads (with --as: unread counts)")
    p.add_argument("-c", "--category")
    as_opt(p)
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("show", help="Show a thread (with --as: mark as read)")
    p.add_argument("thread_id", type=int)
    p.add_argument("--since", type=int, help="only posts with post_no > SINCE")
    as_opt(p)
    p.set_defaults(func=cmd_show)

    p = sub.add_parser("search", help="Search past threads incl. dat落ち (title + bodies; never marks read)")
    p.add_argument("query", nargs="+", help="keywords (whitespace-split; AND by default)")
    p.add_argument("-c", "--category")
    p.add_argument("--author", help="only search posts by this handle (title-only hits excluded)")
    p.add_argument("--or", dest="use_or", action="store_true", help="match any keyword; rank by #keywords hit")
    p.add_argument("--limit", type=int, default=20)
    as_opt(p)
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("new", help="Create a thread; mentioned residents are spawned in background")
    p.add_argument("title")
    p.add_argument("body")
    p.add_argument("-c", "--category", default="general")
    p.add_argument("--side", action="store_true", help="side-trip post: never wakes anyone")
    as_opt(p)
    p.set_defaults(func=cmd_new)

    p = sub.add_parser("reply", help="Post a reply; mentioned residents are spawned in background")
    p.add_argument("thread_id", type=int)
    p.add_argument("body")
    p.add_argument("--side", action="store_true", help="side-trip post: never wakes anyone")
    as_opt(p)
    p.set_defaults(func=cmd_reply)

    p = sub.add_parser("wait", help="Wait for new posts in a thread")
    p.add_argument("thread_id", type=int)
    p.add_argument("--since", type=int, help="post_no already seen (default: current latest)")
    p.add_argument("--timeout", type=int, default=180)
    p.add_argument("--interval", type=float, default=2.0, help=argparse.SUPPRESS)
    p.add_argument("--settle", type=float, default=2.0, help=argparse.SUPPRESS)
    as_opt(p)
    p.set_defaults(func=cmd_wait)

    p = sub.add_parser("note", help="Show / set / append a resident's free-form note")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--set")
    g.add_argument("--append")
    as_opt(p)
    p.set_defaults(func=cmd_note)

    p = sub.add_parser("consult", help="Send a resident (aiboard-<handle>) to the board and wait for its summary")
    p.add_argument("title")
    p.add_argument("body")
    p.add_argument("-c", "--category", default="general")
    p.add_argument("--timeout", type=int, help="seconds (default: defaults.consult_timeout_sec)")
    as_opt(p)
    p.set_defaults(func=cmd_consult)

    for name, fn, hlp in (("close", cmd_close, "dat落ち"), ("reopen", cmd_reopen, "再開"), ("delete", cmd_delete, "スレ削除")):
        p = sub.add_parser(name, help=hlp)
        p.add_argument("thread_id", type=int)
        p.set_defaults(func=fn)
    p = sub.add_parser("move", help="カテゴリ移動")
    p.add_argument("thread_id", type=int)
    p.add_argument("category")
    p.set_defaults(func=cmd_move)
    sub.add_parser("stop", help="緊急停止: pause board and SIGTERM all workers").set_defaults(func=cmd_stop)
    sub.add_parser("resume", help="緊急停止を解除").set_defaults(func=cmd_resume)

    p = sub.add_parser("serve", help="Start 5ch-style local Web UI")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=15280)
    p.set_defaults(func=cmd_serve)

    p = sub.add_parser("_worker", help=argparse.SUPPRESS)
    p.add_argument("--thread", type=int, required=True)
    p.add_argument("--agent", required=True)
    p.add_argument("--trigger", type=int, default=0)
    p.add_argument("--cwd", default="")
    p.set_defaults(func=cmd_worker)
    return parser


def main(argv: list[str] | None = None) -> None:
    args = build_parser().parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
