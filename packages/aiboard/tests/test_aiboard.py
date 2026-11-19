#!/usr/bin/env python3
"""Unit / integration tests for aiboard. Run: python3 tests/test_aiboard.py -v"""
from __future__ import annotations

import datetime
import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import aiboard as ab  # noqa: E402

AIBOARD_PY = str(HERE.parent / "aiboard.py")
FAKE = str(HERE / "fake_agent.py")


def wait_until(pred, timeout=20.0, interval=0.2):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        v = pred()
        if v:
            return v
        time.sleep(interval)
    return pred()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="aiboard-test-")
        self.dir = Path(self.tmp.name)
        self.db = self.dir / "t.db"
        self.cfg_path = self.dir / "agents.json"
        agent = {"kind": "custom", "command": [sys.executable, FAKE]}
        self.cfg = {
            "defaults": {"timeout_sec": 30, "worker_wait_sec": 20, "chain_limit": 30, "hourly_limit": 60,
                         "consult_timeout_sec": 60},
            "groups": {"ab": ["a", "b"]},
            "agents": {h: dict(agent, label=h) for h in ("a", "b", "c", "sol", "opus")},
        }
        self.cfg["agents"]["sol"]["model"] = "gpt-6.2-sol"
        self.cfg["agents"]["opus"]["model"] = "opus"
        self.cfg_path.write_text(json.dumps(self.cfg))
        self.env_backup = dict(os.environ)
        for k in list(os.environ):
            if k.startswith(("AIBOARD_", "FAKE_")):
                del os.environ[k]
        os.environ["AIBOARD_DATA_DIR"] = str(self.dir)
        os.environ["AIBOARD_EMPTY_CWD"] = str(self.dir / "empty_cwd")
        os.environ["AIBOARD_LOG_DIR"] = str(self.dir / "logs")
        os.environ["FAKE_PROMPT_DIR"] = str(self.dir)
        ab.DATA_DIR = self.dir
        ab.EMPTY_CWD = self.dir / "empty_cwd"
        ab.LOG_DIR = self.dir / "logs"
        ab.init_db(self.db)

    def tearDown(self):
        for pid in self.pending():
            ab.kill_tree(pid)
        for w in ab.get_active_workers(self.db):
            ab.kill_tree(int(w["pid"]))
        os.environ.clear()
        os.environ.update(self.env_backup)
        self.tmp.cleanup()

    def cli(self, *args, env_extra=None, timeout=60):
        env = dict(os.environ)
        env.update(env_extra or {})
        return subprocess.run([sys.executable, AIBOARD_PY, "--db", str(self.db), "--config", str(self.cfg_path), *args],
                              capture_output=True, text=True, env=env, timeout=timeout)

    def posts(self, tid):
        d = ab.get_thread(self.db, tid)
        return d["posts"] if d else []

    def pending(self, tid=None):
        return ab.pending_worker_pids(tid, self.db)

    def idle(self, timeout=30):
        return wait_until(lambda: not self.pending() and not [
            w for w in ab.get_active_workers(self.db) if w["mode"] == "worker"], timeout)


class TestSchema(Base):
    def test_legacy_migration(self):
        legacy = self.dir / "legacy.db"
        c = sqlite3.connect(legacy)
        c.executescript("""
        CREATE TABLE threads (id INTEGER PRIMARY KEY AUTOINCREMENT, category TEXT NOT NULL DEFAULT 'general',
          title TEXT NOT NULL, cwd TEXT NOT NULL DEFAULT '', anon_mode INTEGER NOT NULL DEFAULT 1,
          max_rounds INTEGER NOT NULL DEFAULT 2, salt TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
        CREATE TABLE posts (id INTEGER PRIMARY KEY AUTOINCREMENT,
          thread_id INTEGER NOT NULL REFERENCES threads(id) ON DELETE CASCADE, post_no INTEGER NOT NULL,
          author_handle TEXT NOT NULL, anon_id TEXT NOT NULL, is_human INTEGER NOT NULL DEFAULT 0, body TEXT NOT NULL,
          cwd TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'ok', duration_ms INTEGER,
          created_at TEXT NOT NULL, UNIQUE(thread_id, post_no));
        INSERT INTO threads VALUES (1,'arch','old thread','',1,2,'salt','2026-01-01T00:00:00+09:00','2026-01-01T00:00:00+09:00');
        INSERT INTO posts VALUES (1,1,1,'user','HUMAN',1,'@sol hi','', 'ok',NULL,'2026-01-01T00:00:00+09:00');
        INSERT INTO posts VALUES (2,1,2,'sol','abc123',0,'hello','/tmp','ok',1200,'2026-01-01T00:00:01+09:00');
        """)
        c.commit()
        c.close()
        ab.init_db(legacy)
        ab.init_db(legacy)  # idempotent
        c = sqlite3.connect(legacy)
        t_cols = [r[1] for r in c.execute("PRAGMA table_info(threads)")]
        p_cols = [r[1] for r in c.execute("PRAGMA table_info(posts)")]
        tables = {r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        c.close()
        self.assertEqual(t_cols, ["id", "category", "title", "status", "created_at", "updated_at"])
        self.assertNotIn("anon_id", p_cols)
        self.assertIn("is_side", p_cols)
        self.assertTrue({"read_state", "notes", "active_workers", "board_meta"} <= tables)
        d = ab.get_thread(legacy, 1)
        self.assertEqual(d["thread"]["status"], "open")
        self.assertEqual([p["author_handle"] for p in d["posts"]], ["user", "sol"])
        self.assertEqual(d["posts"][1]["cwd"], "/tmp")
        self.assertEqual(ab.add_post(legacy, 1, "opus", "new post"), 3)
        ab.delete_thread(legacy, 1)  # FK cascade still works
        self.assertIsNone(ab.get_thread(legacy, 1))
        self.assertFalse(ab.is_paused(legacy))


class TestReadStateAndNotes(Base):
    def test_unread_and_show_marks_read(self):
        t1 = ab.create_thread(self.db, "t1")
        ab.add_post(self.db, t1, "user", "q", is_human=True)
        ab.add_post(self.db, t1, "b", "ans")
        t2 = ab.create_thread(self.db, "t2")
        ab.add_post(self.db, t2, "a", "a's own thread")  # own thread -> read
        um = ab.unread_map(self.db, "a")
        self.assertIsNone(um[t1])
        self.assertEqual(um[t2], 0)
        out = self.cli("list", "--as", "a").stdout
        self.assertIn("[未閲覧]", out)
        self.assertIn("[既読]", out)
        r = self.cli("show", str(t1), "--as", "a")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("2 : b", r.stdout)
        self.assertEqual(ab.unread_map(self.db, "a")[t1], 0)
        ab.add_post(self.db, t1, "c", "more")
        ab.add_post(self.db, t1, "a", "mine")  # own post not counted, pointer not advanced (was behind)
        self.assertEqual(ab.unread_map(self.db, "a")[t1], 1)
        self.assertIn("[未読 1件]", self.cli("list", "--as", "a").stdout)
        plain = self.cli("list").stdout
        for label in ("未読", "既読", "未閲覧"):
            self.assertNotIn(label, plain)  # no unread labels without --as

    def test_notes(self):
        self.assertIn("メモは空", self.cli("note", "--as", "a").stdout)
        self.cli("note", "--as", "a", "--set", "first")
        self.cli("note", "--as", "a", "--append", "second")
        self.assertEqual(ab.get_note(self.db, "a"), "first\nsecond")
        self.assertEqual(self.cli("note", "--as", "a").stdout.strip(), "first\nsecond")
        self.assertEqual(ab.get_note(self.db, "b"), "")
        r = self.cli("note", "--as", "b", "--set", "x", env_extra={"AIBOARD_AGENT": "a"})
        self.assertNotEqual(r.returncode, 0)  # cannot edit someone else's note from inside a board process
        self.assertNotEqual(self.cli("note").returncode, 0)  # --as required


class TestBrakes(Base):
    def test_chain_hourly_closed_paused(self):
        tid = ab.create_thread(self.db, "x")
        ab.add_post(self.db, tid, "user", "start", is_human=True)
        self.assertIsNone(ab.spawn_block_reason(self.db, tid, self.cfg))
        for i in range(30):
            ab.add_post(self.db, tid, "a" if i % 2 else "b", f"r{i}")
        self.assertIn("連続AIレス", ab.spawn_block_reason(self.db, tid, self.cfg))
        self.assertEqual(ab.spawn_mentions(self.db, self.cfg_path, self.cfg, tid, 31, "@a", "b", verbose=False), [])
        # Staying session worker cannot bypass chain_limit via direct `reply` either
        blocked = self.cli("reply", str(tid), "still arguing @a", "--as", "b",
                           env_extra={"AIBOARD_AGENT": "b", "AIBOARD_WORKER": "1", "AIBOARD_FOCUS_THREAD": str(tid)})
        self.assertNotEqual(blocked.returncode, 0)
        self.assertIn("連続AIレス", blocked.stderr)
        ab.add_post(self.db, tid, "user", "reset", is_human=True)
        cfg2 = json.loads(json.dumps(self.cfg))
        cfg2["defaults"]["hourly_limit"] = 30
        self.assertIn("直近1時間", ab.spawn_block_reason(self.db, tid, cfg2))
        self.assertIsNone(ab.spawn_block_reason(self.db, tid, self.cfg))
        ab.set_thread_status(self.db, tid, "closed")
        self.assertIn("dat落ち", ab.spawn_block_reason(self.db, tid, self.cfg))
        ab.set_thread_status(self.db, tid, "open")
        ab.set_paused(self.db, True)
        self.assertIn("緊急停止", ab.spawn_block_reason(self.db, tid, self.cfg))
        ab.set_paused(self.db, False)

    def test_hourly_ignores_old_posts(self):
        tid = ab.create_thread(self.db, "x")
        old = (datetime.datetime.now().astimezone() - datetime.timedelta(hours=2)).isoformat(timespec="seconds")
        with ab.db(self.db, write=True) as c:
            for i in range(70):
                c.execute("INSERT INTO posts(thread_id, post_no, author_handle, is_human, body, created_at) "
                          "VALUES(?, ?, 'a', 0, 'x', ?)", (tid, i + 1, old))
            c.execute("INSERT INTO posts(thread_id, post_no, author_handle, is_human, body, created_at) "
                      "VALUES(?, 71, 'user', 1, 'x', ?)", (tid, ab.now_iso()))
        self.assertIsNone(ab.spawn_block_reason(self.db, tid, self.cfg))

    def test_side_post_never_spawns(self):
        tid = ab.create_thread(self.db, "x")
        ab.add_post(self.db, tid, "user", "q", is_human=True)
        r = self.cli("reply", str(tid), "@a @b 寄り道", "--as", "c", "--side")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("寄り道レスなのでメンション起動はしない", r.stdout)
        p = self.posts(tid)[-1]
        self.assertEqual((p["author_handle"], p["is_side"], p["is_human"]), ("c", 1, 0))
        time.sleep(1.0)
        self.assertEqual(self.pending(), [])
        self.assertEqual(len(self.posts(tid)), 2)
        r = self.cli("new", "side thread", "@a hey", "--as", "c", "--side", "-c", "misc")
        self.assertIn("[寄り道]", r.stdout)
        time.sleep(0.5)
        self.assertEqual(self.pending(), [])


class TestAsyncWorkers(Base):
    def test_new_returns_immediately_and_chain(self):
        os.environ["FAKE_SLEEP"] = "2"
        os.environ["FAKE_MENTION_A"] = ">>1 @b どう思う？"
        t0 = time.monotonic()
        r = self.cli("new", "議題", "@a 意見ちょうだい", "-c", "arch")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertLess(time.monotonic() - t0, 1.8, "new must not block on workers")
        self.assertIn("worker spawned", r.stdout)
        tid = int(r.stdout.split("#")[1].split()[0])
        w = self.cli("wait", str(tid), "--since", "1", "--timeout", "20")
        self.assertIn("2 : a", w.stdout)
        self.assertIn("a の意見です", w.stdout)
        self.assertTrue(wait_until(lambda: len(self.posts(tid)) >= 3, 20))
        self.assertTrue(self.idle())
        ps = self.posts(tid)
        self.assertEqual([p["author_handle"] for p in ps[:3]], ["user", "a", "b"])
        self.assertEqual(len(ps), 3, "b must not re-wake a (b's reply has no mention)")
        self.assertEqual(ab.get_active_workers(self.db), [])
        prompt = next(self.dir.glob(f"a-{tid}-*.txt")).read_text()
        self.assertIn("本題スレッド全文", prompt)
        self.assertIn("自由メモ", prompt)
        self.assertNotIn("(pass)", prompt)
        # a read up to >>1 when woken, then posted >>2 itself; only b's >>3 is unread for a
        self.assertEqual(ab.unread_map(self.db, "a")[tid], 1)
        # residents that never call `aiboard reply` still get their stdout posted (fallback)
        self.assertIn("(stdout fallback)", (self.dir / "logs" / f"worker-t{tid}-a.log").read_text())
        self.assertIn("(stdout fallback)", (self.dir / "logs" / f"worker-t{tid}-b.log").read_text())

    def test_wait_idle_and_timeout(self):
        tid = ab.create_thread(self.db, "quiet")
        ab.add_post(self.db, tid, "user", "no mentions", is_human=True)
        t0 = time.monotonic()
        r = self.cli("wait", str(tid), "--timeout", "10")
        self.assertIn("新着なし", r.stdout)
        self.assertLess(time.monotonic() - t0, 8)

    def test_worker_guards_and_side_trip(self):
        other = ab.create_thread(self.db, "別スレ", category="misc")
        ab.add_post(self.db, other, "user", "誰か助けて", is_human=True)
        os.environ["FAKE_TRY_FOCUS"] = "1"
        os.environ["FAKE_SIDE_TID_A"] = str(other)
        r = self.cli("new", "本題", "@a 調べて")
        tid = int(r.stdout.split("#")[1].split()[0])
        self.assertTrue(wait_until(lambda: len(self.posts(tid)) >= 2, 20))
        self.assertTrue(self.idle())
        ps = self.posts(tid)
        self.assertEqual(len(ps), 2, "stdout must not be posted again after a focus `reply`")
        p2 = ps[1]
        # session worker may now `aiboard reply` to its focus thread: a normal (non-side) post
        self.assertEqual((p2["author_handle"], p2["is_side"], p2["status"]), ("a", 0, "ok"))
        self.assertTrue(p2["body"].startswith("本題へ直接 reply"))
        rc_out = (self.dir / f"focusrc-a-{tid}.out").read_text()
        self.assertEqual(rc_out.splitlines()[0], "0")
        self.assertIn("他AIへのメンションなし", rc_out)
        body = p2["body"]
        self.assertIn("impersonate_rc=1", body)
        self.assertIn("stop_rc=1", body)
        self.assertIn("side_rc=0", body)
        self.assertIn("session done", (self.dir / "logs" / f"worker-t{tid}-a.log").read_text())
        side = self.posts(other)[-1]
        self.assertEqual((side["author_handle"], side["is_side"]), ("a", 1))  # forced to --side inside worker
        time.sleep(0.5)
        self.assertEqual(len(self.posts(other)), 2, "@c in a side post must not spawn")
        self.assertEqual(ab.get_note(self.db, "a"), f"a visited {other}")
        prompt = next(self.dir.glob(f"a-{tid}-*.txt")).read_text()
        self.assertIn(f"[{other}] [misc] 別スレ [未閲覧]", prompt)
        self.assertFalse(ab.is_paused(self.db))

    def test_duplicate_spawn_same_handle(self):
        os.environ["FAKE_SLEEP"] = "1.5"
        tid = ab.create_thread(self.db, "dup")
        no = ab.add_post(self.db, tid, "user", "@a", is_human=True)
        ab.spawn_worker(self.db, self.cfg_path, tid, "a", no)
        ab.spawn_worker(self.db, self.cfg_path, tid, "a", no)  # queued -> skips after first replies
        self.assertTrue(wait_until(lambda: len(self.posts(tid)) >= 2, 20))
        self.assertTrue(self.idle())
        self.assertEqual([p["author_handle"] for p in self.posts(tid)], ["user", "a"])
        log = (self.dir / "logs" / f"worker-t{tid}-a.log").read_text()
        self.assertIn("already replied", log)

    def test_new_mention_while_worker_running_is_not_skipped(self):
        os.environ["FAKE_SLEEP"] = "2.0"
        tid = ab.create_thread(self.db, "midflight")
        no1 = ab.add_post(self.db, tid, "user", "@a first question", is_human=True)
        ab.spawn_worker(self.db, self.cfg_path, tid, "a", no1)
        # Wait until worker 1 has snapshotted >>1 (last_read == 1) and is mid-sleep
        self.assertTrue(wait_until(lambda: ab.get_last_read(self.db, "a", tid) == 1, 10))
        no2 = ab.add_post(self.db, tid, "user", "@a follow-up while thinking", is_human=True)
        ab.spawn_worker(self.db, self.cfg_path, tid, "a", no2)
        # Worker 1 posts >>3 (reply to >>1), then queued Worker 2 must NOT skip >>2 and posts >>4
        self.assertTrue(wait_until(lambda: len(self.posts(tid)) >= 4, 25))
        self.assertTrue(self.idle())
        self.assertEqual([p["author_handle"] for p in self.posts(tid)], ["user", "user", "a", "a"])

    def test_consult_online_handle_not_spawned(self):
        tid = ab.create_thread(self.db, "x")
        no = ab.add_post(self.db, tid, "user", "@a", is_human=True)
        sleeper = subprocess.Popen(["sleep", "30"], env={**os.environ, "AIBOARD_AGENT": "a"})
        try:
            ab.force_register(self.db, "a", sleeper.pid, 999, "consult")
            self.assertEqual(ab.spawn_mentions(self.db, self.cfg_path, self.cfg, tid, no, "@a @b", "user", verbose=False), ["b"])
        finally:
            sleeper.kill()
            sleeper.wait()
        self.assertTrue(self.idle())
        self.assertEqual(ab.get_active_workers(self.db), [])  # dead consult row cleaned up

    def test_dead_and_reused_pid_cleanup(self):
        ab.force_register(self.db, "b", 999999, 1, "worker")
        ab.force_register(self.db, "c", os.getpid(), 1, "worker")  # alive but not carrying AIBOARD_AGENT=c
        self.assertEqual(ab.get_active_workers(self.db), [])


class TestSessionWorker(Base):
    def transcript(self, handle, tid):
        out = []
        for f in sorted(self.dir.glob(f"{handle}-{tid}-*.log")):
            out.append([json.loads(line) for line in f.read_text().splitlines() if line.strip()])
        return out

    def test_multi_round_trip_without_double_spawn(self):
        os.environ["FAKE_SCRIPT_A"] = json.dumps([
            {"reply": "@b どう思う？"}, {"wait": 30}, {"reply": "なるほど合意"}, {"print": "完了"}])
        os.environ["FAKE_SCRIPT_B"] = json.dumps([{"reply": "@a こう思う"}, {"wait": 30}, {"print": "完了"}])
        r = self.cli("new", "往復", "@a 決めて")
        self.assertEqual(r.returncode, 0, r.stderr)
        tid = int(r.stdout.split("#")[1].split()[0])
        self.assertTrue(wait_until(lambda: len(self.posts(tid)) >= 4, 40))
        self.assertTrue(self.idle(40))
        ps = self.posts(tid)
        self.assertEqual([(p["post_no"], p["author_handle"], p["body"]) for p in ps], [
            (1, "user", "@a 決めて"), (2, "a", "@b どう思う？"), (3, "b", "@a こう思う"), (4, "a", "なるほど合意")])
        self.assertTrue(all(p["is_side"] == 0 and p["status"] == "ok" for p in ps))
        self.assertNotIn("完了", [p["body"] for p in ps], "stdout must not be double-posted")
        # a handled >>3 inside the same process: exactly one prompt (= one agent run) for a, and for b
        self.assertEqual(len(list(self.dir.glob(f"a-{tid}-*.txt"))), 1)
        self.assertEqual(len(list(self.dir.glob(f"b-{tid}-*.txt"))), 1)
        (ta,) = self.transcript("a", tid)
        self.assertEqual([e["op"] for e in ta], ["reply", "wait", "reply"])
        self.assertIn("worker spawned", ta[0]["out"])
        self.assertIn(f"(返事を待つなら aiboard wait {tid} --since 2 --as a)", ta[0]["out"])
        self.assertIn("3 : b", ta[1]["out"])
        self.assertIn("@a こう思う", ta[1]["out"])
        self.assertIn("他AIへのメンションなし", ta[2]["out"])
        self.assertNotIn("注意", ta[2]["out"])  # a had read >>3 via wait
        (tb,) = self.transcript("b", tid)
        self.assertIn("@a: このスレに滞在中 (worker) なので起こさない", tb[0]["out"])
        self.assertNotIn("worker spawned", tb[0]["out"])
        self.assertIn(f"(返事を待つなら aiboard wait {tid} --since 3 --as b)", tb[0]["out"])
        self.assertIn("4 : a", tb[1]["out"])
        log_a = (self.dir / "logs" / f"worker-t{tid}-a.log").read_text()
        self.assertEqual(log_a.count("=== "), 1, "a must be spawned exactly once")
        self.assertIn("session done", log_a)
        self.assertEqual(ab.get_active_workers(self.db), [])
        self.assertEqual(self.pending(), [])

    def test_wait_excludes_self(self):
        os.environ["FAKE_SCRIPT_A"] = json.dumps([{"wait": 15, "since": False}, {"print": "a は待ったが誰もいない"}])
        r = self.cli("new", "ひとり", "@a 待ってみて")
        tid = int(r.stdout.split("#")[1].split()[0])
        self.assertTrue(wait_until(lambda: len(self.posts(tid)) >= 2, 30))
        self.assertTrue(self.idle())
        (ta,) = self.transcript("a", tid)
        self.assertEqual(ta[0]["op"], "wait")
        self.assertLess(ta[0]["elapsed"], 6.0, "a's own worker/row must not keep its wait busy")
        self.assertIn("応答中のワーカーはいない", ta[0]["out"])
        self.assertNotIn("まだ応答中", ta[0]["out"])
        # nothing posted via reply -> stdout fallback
        self.assertEqual(self.posts(tid)[-1]["body"], "a は待ったが誰もいない")
        # unit level: exclude_agent filters by --agent
        # a process whose cmdline looks like a queued `_worker` for @zz on thread 999
        sleeper = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)", AIBOARD_PY,
                                    "--db", str(self.db.resolve()), "_worker", "--thread", "999", "--agent", "zz"])
        try:
            self.assertTrue(wait_until(lambda: sleeper.pid in ab.pending_worker_pids(999, self.db), 5))
            self.assertNotIn(sleeper.pid, ab.pending_worker_pids(999, self.db, exclude_agent="zz"))
            self.assertIn(sleeper.pid, ab.pending_worker_pids(999, self.db, exclude_agent="a"))
        finally:
            sleeper.kill()
            sleeper.wait()

    def test_missed_mention_while_leaving_is_swept(self):
        os.environ["FAKE_SCRIPT_A"] = json.dumps([{"reply": "答えた"}, {"sleep": 3}, {"print": "完了"}])
        tid = ab.create_thread(self.db, "取りこぼし")
        no1 = ab.add_post(self.db, tid, "user", "@a 質問", is_human=True)
        ab.spawn_worker(self.db, self.cfg_path, tid, "a", no1)
        # a posted >>2 and is about to leave without waiting (still online, last_read < 3)
        self.assertTrue(wait_until(lambda: len(self.posts(tid)) >= 2, 20))
        w = ab.get_worker(self.db, "a")
        self.assertIsNotNone(w)
        self.assertEqual(w["thread_id"], tid)
        self.assertLess(ab.get_last_read(self.db, "a", tid), 3)
        r = self.cli("reply", str(tid), "@a 追加質問")
        self.assertIn("Posted >>3", r.stdout)
        self.assertIn("@a: このスレに滞在中 (worker) なので起こさない", r.stdout)
        self.assertNotIn("worker spawned", r.stdout)
        # a's exit-time sweep re-spawns it for >>3
        self.assertTrue(wait_until(lambda: len(self.posts(tid)) >= 4, 30))
        self.assertTrue(self.idle(30))
        self.assertEqual([p["author_handle"] for p in self.posts(tid)], ["user", "a", "user", "a"])
        self.assertEqual(len(list(self.dir.glob(f"a-{tid}-*.txt"))), 2)
        second = sorted(self.dir.glob(f"a-{tid}-*.txt"), key=lambda f: f.stat().st_mtime)[-1].read_text()
        self.assertIn("@a 追加質問", second)
        log = (self.dir / "logs" / f"worker-t{tid}-a.log").read_text()
        self.assertIn("missed mention >>3 -> re-spawned", log)
        self.assertIn("trigger>>3", log)
        time.sleep(1.0)
        self.assertEqual(len(self.posts(tid)), 4, "no further re-spawn once >>3 is answered")
        self.assertEqual(ab.get_active_workers(self.db), [])

    def test_reply_hints_for_ai(self):
        tid = ab.create_thread(self.db, "hints")
        ab.add_post(self.db, tid, "user", "q", is_human=True)
        ab.mark_read(self.db, "c", tid, 1)
        ab.add_post(self.db, tid, "b", "c が見ていない新着")
        r = self.cli("reply", str(tid), "まとめ", "--as", "c")
        self.assertIn(f"(注意: >>3 の直前に未読の新着レスあり。aiboard show {tid} --since 1 --as c で確認)", r.stdout)
        self.assertIn("他AIへのメンションなし", r.stdout)
        self.assertEqual(ab.get_last_read(self.db, "c", tid), 1, "skipped post stays unread")
        r = self.cli("show", str(tid), "--as", "c")
        r = self.cli("reply", str(tid), "了解", "--as", "c")
        self.assertNotIn("注意", r.stdout)
        self.assertEqual(ab.get_last_read(self.db, "c", tid), 4)
        # human posts and side posts get no hints
        self.assertNotIn("他AIへのメンションなし", self.cli("reply", str(tid), "人間").stdout)
        self.assertNotIn("他AIへのメンションなし", self.cli("reply", str(tid), "x", "--as", "c", "--side").stdout)


class TestModeration(Base):
    def test_close_reopen_move_delete(self):
        tid = ab.create_thread(self.db, "mod")
        ab.add_post(self.db, tid, "user", "x", is_human=True)
        self.assertEqual(self.cli("close", str(tid)).returncode, 0)
        r = self.cli("reply", str(tid), "@a hi")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("closed", r.stderr)
        self.assertIn("[dat落ち]", self.cli("list").stdout)
        self.cli("reopen", str(tid))
        self.assertEqual(self.cli("reply", str(tid), "ok").returncode, 0)
        self.cli("move", str(tid), "nix")
        self.assertEqual(ab.get_thread(self.db, tid)["thread"]["category"], "nix")
        ab.mark_read(self.db, "a", tid)
        self.assertEqual(self.cli("delete", str(tid)).returncode, 0)
        self.assertIsNone(ab.get_thread(self.db, tid))
        with ab.db(self.db) as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM posts").fetchone()[0], 0)
            self.assertEqual(c.execute("SELECT COUNT(*) FROM read_state").fetchone()[0], 0)
        self.assertNotEqual(self.cli("close", "1", env_extra={"AIBOARD_AGENT": "a"}).returncode, 0)

    def test_stop_kills_workers_and_resume(self):
        os.environ["FAKE_HANG"] = "1"
        r = self.cli("new", "hang", "@a @b 待って")
        tid = int(r.stdout.split("#")[1].split()[0])
        self.assertTrue(wait_until(lambda: len(ab.get_active_workers(self.db)) == 2, 10))
        hermes_like = wait_until(lambda: [p for w in ab.get_active_workers(self.db)
                                          for p in ab.descendants(int(w["pid"]))]
                                 if all(ab.descendants(int(w["pid"])) for w in ab.get_active_workers(self.db))
                                 else [], 10)
        self.assertTrue(hermes_like, "fake agent children should be running")
        r = self.cli("stop")
        self.assertIn("Board paused", r.stdout)
        self.assertTrue(ab.is_paused(self.db))
        self.assertTrue(wait_until(lambda: not ab.get_active_workers(self.db) and not self.pending(), 10))
        self.assertTrue(wait_until(lambda: not any(ab.is_pid_alive(p) for p in hermes_like), 10))
        self.assertEqual(len(self.posts(tid)), 1)
        r = self.cli("reply", str(tid), "@a while paused")
        self.assertIn("緊急停止", r.stdout)
        self.cli("resume")
        self.assertFalse(ab.is_paused(self.db))
        self.assertIn("稼働中", self.cli("status").stdout)


class TestConsult(Base):
    def test_detect_default_handle(self):
        y = self.dir / "config.yaml"
        y.write_text("foo: 1\nmodel:\n  default: gpt-6.2-sol\n  provider: x\n")
        self.assertEqual(ab.detect_default_handle(self.cfg, y), "sol")
        y.write_text("model:\n  default: opus\n")
        self.assertEqual(ab.detect_default_handle(self.cfg, y), "opus")
        y.write_text("model:\n  default: claude-opus-5-5\n")
        self.assertEqual(ab.detect_default_handle(self.cfg, y), "opus")
        y.write_text("model:\n  default: something-else\n")
        self.assertEqual(ab.detect_default_handle(self.cfg, y), "sol")
        self.assertEqual(ab.detect_default_handle(self.cfg, self.dir / "missing.yaml"), "sol")

    def test_consult_flow(self):
        other = ab.create_thread(self.db, "寄り道対象")
        ab.add_post(self.db, other, "user", "unrelated secret", is_human=True)
        r = self.cli("consult", "相談", f"@a({self.dir}) これどう思う？", "-c", "arch", "--as", "c",
                     timeout=90)
        self.assertEqual(r.returncode, 0, r.stderr)
        out = r.stdout
        self.assertIn("① 本題スレッド全レスログ", out)
        self.assertIn("② @c による最終まとめ", out)
        self.assertIn("SUMMARY: 結論は c が整理した", out)
        self.assertIn("1 : c", out)
        self.assertNotIn("unrelated secret", out)
        tid = int(out.split("=== [")[1].split("]")[0])
        authors = [p["author_handle"] for p in self.posts(tid)]
        self.assertEqual(authors[0], "c")
        self.assertIn("a", authors)
        self.assertIn("b", authors)  # consult resident's own reply woke b
        self.assertTrue(self.idle())
        self.assertEqual(ab.get_active_workers(self.db), [])
        self.assertEqual(ab.get_note(self.db, "c"), "consult done")
        self.assertEqual(self.posts(tid)[0]["cwd"], str(self.dir))
        r2 = self.cli("consult", "x", "y", env_extra={"AIBOARD_WORKER": "1", "AIBOARD_AGENT": "a"})
        self.assertNotEqual(r2.returncode, 0)


class TestSearch(Base):
    def seed(self):
        t1 = ab.create_thread(self.db, "Nix flake の CI", category="nix")
        ab.add_post(self.db, t1, "user", "@sol nix eval が遅い\n\n  どうする？", is_human=True)
        ab.add_post(self.db, t1, "sol", "EVAL キャッシュを使えば解決した。" + "x" * 300)
        t2 = ab.create_thread(self.db, "ビルド高速化", category="arch")
        ab.add_post(self.db, t2, "user", "cache と キャッシュ と ccache の比較", is_human=True)
        ab.add_post(self.db, t2, "opus", "ccache は C 向け", is_side=True)
        t3 = ab.create_thread(self.db, "雑談", category="misc")
        ab.add_post(self.db, t3, "user", "キャッシュの話だけ", is_human=True)
        return t1, t2, t3

    def tid_order(self, out):
        return [int(line[1:].split("]")[0]) for line in out.splitlines() if line.startswith("[")]

    def test_and_or_category_author(self):
        t1, t2, t3 = self.seed()
        # AND: both forms of query tokenisation; title ("CI") + body ("eval") cross-match; case-insensitive
        for args in (("nix eval",), ("NIX", "Eval")):
            r = self.cli("search", *args)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(self.tid_order(r.stdout), [t1])
        self.assertEqual(self.tid_order(self.cli("search", "ci", "遅い").stdout), [t1])  # title × body AND
        self.assertEqual(self.cli("search", "ci", "ccache").stdout.strip(), "(該当なし)")
        out = self.cli("search", "eval").stdout
        self.assertIn(f"[{t1}] [nix] Nix flake の CI (全2レス)", out)
        self.assertIn("  >>1 user [", out)
        self.assertIn("nix eval が遅い どうする？", out)  # whitespace/newlines collapsed
        line2 = next(line for line in out.splitlines() if line.startswith("  >>2 sol"))
        self.assertTrue(line2.endswith("..."))
        self.assertLess(len(line2.split(": ", 1)[1]), 130)
        # OR: synonyms; thread hitting more distinct tokens comes first
        r = self.cli("search", "キャッシュ", "ccache", "cache", "--or")
        # t2 hits 3 distinct tokens; t1/t3 hit 1 each -> tie broken by updated_at/id desc (t3 newer)
        self.assertEqual(self.tid_order(r.stdout), [t2, t3, t1])
        # make t1 hit 2 tokens -> it overtakes the newer t3
        ab.add_post(self.db, t1, "user", "Cache も？", is_human=True)
        ab.add_post(self.db, t3, "user", "キャッシュ追記", is_human=True)  # t3 is newest again
        self.assertEqual(self.tid_order(self.cli("search", "キャッシュ", "ccache", "cache", "--or").stdout),
                         [t2, t1, t3])
        self.assertIn(f"[{t1}] [nix] Nix flake の CI (全3レス)", self.cli("search", "cache", "--or").stdout)
        self.assertIn(">>2 opus [", r.stdout)
        self.assertIn("[寄り道]: ccache は C 向け", r.stdout)
        # without --or the same tokens need all to match
        self.assertEqual(self.tid_order(self.cli("search", "キャッシュ", "ccache", "cache").stdout), [t2])
        # -c category
        self.assertEqual(self.tid_order(self.cli("search", "キャッシュ", "-c", "misc").stdout), [t3])
        # --author: only that author's posts, title-only matches excluded
        self.assertEqual(self.tid_order(self.cli("search", "キャッシュ", "--author", "sol").stdout), [t1])
        self.assertEqual(self.cli("search", "flake", "--author", "sol").stdout.strip(), "(該当なし)")
        self.assertEqual(self.tid_order(self.cli("search", "flake").stdout), [t1])  # title match w/o --author
        r = self.cli("search", "nix", "--author", "user")
        self.assertIn(">>1 user", r.stdout)
        self.assertNotIn(">>2 sol", r.stdout)
        # --limit
        r = self.cli("search", "キャッシュ", "--or", "--limit", "1")
        self.assertEqual(len(self.tid_order(r.stdout)), 1)
        self.assertIn("ほか 2 スレがヒット", r.stdout)
        self.assertNotEqual(self.cli("search", "  ").returncode, 0)

    def test_closed_excerpt_limit_and_unread(self):
        tid = ab.create_thread(self.db, "解決済み: sqlite ロック")
        ab.add_post(self.db, tid, "user", "database is locked が出る", is_human=True)
        for i in range(5):
            ab.add_post(self.db, tid, "a" if i % 2 else "b", f"locked 対策 {i}: busy_timeout")
        ab.set_thread_status(self.db, tid, "closed")
        r = self.cli("search", "locked", "--as", "c")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn(f"[{tid}] [general] 解決済み: sqlite ロック [dat落ち] (全6レス) [未閲覧]", r.stdout)
        self.assertEqual(r.stdout.count("\n  >>"), 3)
        self.assertIn(f"  ...ほか 3 件のレスがヒット (aiboard show {tid} で全文確認)", r.stdout)
        self.assertEqual(ab.get_last_read(self.db, "c", tid), 0)  # search does not mark read
        self.assertIsNone(ab.unread_map(self.db, "c")[tid])
        self.assertIn("[未閲覧]", self.cli("search", "locked", "--as", "c").stdout)
        self.cli("show", str(tid), "--as", "c")
        self.assertIn("[既読]", self.cli("search", "locked", "--as", "c").stdout)
        self.assertNotIn("既読", self.cli("search", "locked").stdout)  # no label without --as
        with ab.db(self.db) as c:
            self.assertEqual(c.execute("SELECT COUNT(*) FROM read_state WHERE agent_handle='b'").fetchone()[0], 0)
        self.cli("search", "locked", "--as", "b")
        self.assertEqual(ab.get_last_read(self.db, "b", tid), 0)

    def test_prompts_mention_search(self):
        tid = ab.create_thread(self.db, "p")
        ab.add_post(self.db, tid, "user", "@a q", is_human=True)
        for fn in (ab.build_worker_prompt, ab.build_consult_prompt):
            prompt = fn(self.db, self.cfg, "a", tid, effective_cwd="", has_explicit_cwd=False)
            self.assertIn(" search ", prompt)
            self.assertIn("--or", prompt)
            self.assertIn("dat落ち", prompt)

    def test_web_search(self):
        t1, t2, _ = self.seed()
        x = ab.create_thread(self.db, "<b>xss</b>", category="arch")
        ab.add_post(self.db, x, "user", "<script>alert(1)</script> キャッシュ", is_human=True)
        ab.set_thread_status(self.db, t1, "closed")
        server = ab.http.server.ThreadingHTTPServer(("127.0.0.1", 0), ab.make_handler(self.db, self.cfg_path))
        port = server.server_address[1]
        threading.Thread(target=server.serve_forever, daemon=True).start()
        try:
            base = f"http://127.0.0.1:{port}"
            get = lambda qs: urllib.request.urlopen(base + "/?" + qs).read().decode()  # noqa: E731
            page = get(urllib.parse.urlencode({"q": "nix eval"}))
            self.assertIn("検索結果「nix eval」", page)
            self.assertIn(f'href="/t/{t1}#p1">&gt;&gt;1</a>', page)
            self.assertIn("nix eval が遅い", page)
            self.assertIn("dat落ち", page)
            self.assertIn('name="q" value="nix eval"', page)
            self.assertIn(">クリア</a>", page)
            self.assertNotIn(f'href="/t/{t2}"', page)
            page = get(urllib.parse.urlencode({"q": "キャッシュ ccache", "or": "1", "c": "arch"}))
            self.assertIn(f'href="/t/{t2}#p1"', page)
            self.assertNotIn(f'href="/t/{t1}#', page)  # other category filtered out
            self.assertIn('name="c" value="arch"', page)
            self.assertIn('name="or" value="1" checked', page)
            self.assertNotIn("<script>alert(1)</script>", page)
            self.assertNotIn("<b>xss</b>", page)
            self.assertIn("&lt;script&gt;alert(1)&lt;/script&gt;", page)
            page = get(urllib.parse.urlencode({"q": "存在しない語"}))
            self.assertIn("(該当なし)", page)
            plain = get("")
            self.assertIn('name="q"', plain)
            self.assertNotIn("検索結果", plain)
            self.assertNotIn(">クリア</a>", plain)
        finally:
            server.shutdown()
            server.server_close()


class TestHtml(Base):
    def test_render_and_server(self):
        tid = ab.create_thread(self.db, "<script>x</script>", category="arch")
        ab.add_post(self.db, tid, "user", "@sol >>1 hi", is_human=True)
        ab.add_post(self.db, tid, "opus", "side note", is_side=True)
        data = ab.get_thread(self.db, tid)
        page = ab.render_thread(self.cfg, data, workers=[], paused=False)
        self.assertIn('<span class="post-no">1</span> : <span class="post-name human">user</span>', page)
        self.assertIn('<span class="post-name">opus</span>', page)
        self.assertIn("寄り道", page)
        self.assertIn(f'action="/t/{tid}/move"', page)
        self.assertIn(f'action="/t/{tid}/close"', page)
        self.assertIn(f'action="/t/{tid}/delete"', page)
        self.assertNotIn("<script>x</script>", page)
        for gone in ("名無し", "ID:", "正体", "最大ラウンド", "匿名"):
            self.assertNotIn(gone, page)
        idx = ab.render_index(self.cfg, ab.list_categories(self.db), ab.list_threads(self.db),
                              selected_cat=None, paused=False,
                              workers=[{"agent_handle": "sol", "mode": "worker", "thread_id": tid, "pid": 1}])
        self.assertIn("稼働中", idx)
        self.assertIn('action="/stop"', idx)
        self.assertIn("@sol(応答中", idx)
        self.assertNotIn("location.reload()", idx)
        self.assertIn("startLivePoll(['board-status', 'board-tabs', 'thread-list-body'])", idx)
        busy_page = ab.render_thread(self.cfg, data, workers=[{"agent_handle": "sol", "mode": "worker", "thread_id": tid, "pid": 1}], paused=False)
        self.assertNotIn("location.reload()", busy_page)
        self.assertIn("startLivePoll(['live-status', 'posts-card'], true)", busy_page)
        self.assertIn("if (!location.hash) { scrollToBottom();", busy_page)
        self.assertLess(busy_page.index('id="posts-card"'), busy_page.index('id="live-status"'))
        idx2 = ab.render_index(self.cfg, [], [], selected_cat=None, paused=True, workers=[])
        self.assertIn("一時停止中", idx2)
        self.assertIn('action="/resume"', idx2)
        ab.set_thread_status(self.db, tid, "closed")
        page2 = ab.render_thread(self.cfg, ab.get_thread(self.db, tid), workers=[], paused=True)
        self.assertIn("再開(reopen)", page2)
        self.assertNotIn(f'action="/t/{tid}/reply"', page2)

        server = ab.http.server.ThreadingHTTPServer(("127.0.0.1", 0), ab.make_handler(self.db, self.cfg_path))
        port = server.server_address[1]
        th = threading.Thread(target=server.serve_forever, daemon=True)
        th.start()
        try:
            base = f"http://127.0.0.1:{port}"
            self.assertIn("aiboard", urllib.request.urlopen(base + "/").read().decode())
            self.assertIn("side note", urllib.request.urlopen(f"{base}/t/{tid}").read().decode())

            def post(path, data=b""):
                return urllib.request.urlopen(urllib.request.Request(base + path, data=data, method="POST"))

            post(f"/t/{tid}/reopen")
            self.assertEqual(ab.get_thread(self.db, tid)["thread"]["status"], "open")
            post(f"/t/{tid}/move", b"category=nix")
            self.assertEqual(ab.get_thread(self.db, tid)["thread"]["category"], "nix")
            post(f"/t/{tid}/reply", "body=人間です".encode())
            self.assertEqual(self.posts(tid)[-1]["author_handle"], "user")
            post(f"/t/{tid}/close")
            resp = post(f"/t/{tid}/reply", b"body=x")
            self.assertIn("dat", resp.read().decode())
            post("/stop")
            self.assertTrue(ab.is_paused(self.db))
            post("/resume")
            self.assertFalse(ab.is_paused(self.db))
            api = json.loads(urllib.request.urlopen(f"{base}/api/t/{tid}").read())
            self.assertEqual(api["thread"]["id"], tid)
            post(f"/t/{tid}/delete")
            self.assertIsNone(ab.get_thread(self.db, tid))
        finally:
            server.shutdown()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
