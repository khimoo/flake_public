"""SQLite storage and application rules shared by aiboard's front ends."""

import os
import re
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from fcntl import LOCK_EX, flock
from pathlib import Path


class BoardError(Exception):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def now():
    return datetime.now(timezone.utc).isoformat(timespec='microseconds')


_FENCE = re.compile(r'^ {0,3}(`{3,}|~{3,})([^\n\r]*)\r?$', re.MULTILINE)
_BACKTICKS = re.compile(r'`+')
_PARAGRAPH_BREAK = re.compile(r'\r?\n[ \t]*\r?\n')
_MENTION = re.compile(r'(?:(?<![A-Za-z0-9._@-])@(?P<handle>[A-Za-z0-9][A-Za-z0-9._-]*)'
                      r'|(?<![A-Za-z0-9>])>>(?P<anchor>\d+))'
                      r'(?:\((?P<cwd>(?:~/|/)[^)\s]+)\))?')


def _outside_fences(body):
    start = 0
    opening = None
    for match in _FENCE.finditer(body):
        marker, tail = match.groups()
        if opening is None:
            if marker[0] == '`' and '`' in tail:
                continue
            yield start, match.start()
            opening = marker
        elif marker.startswith(opening) and not tail.strip():
            start = match.end()
            opening = None
    if opening is None:
        yield start, len(body)


def _outside_inline_code(body, start, end):
    runs = list(_BACKTICKS.finditer(body, start, end))
    # Find matching delimiters in linear time, including when many are unpaired.
    next_by_length = {}
    closes = {}
    for run in reversed(runs):
        length = run.end() - run.start()
        if length in next_by_length:
            closes[run.start()] = next_by_length[length]
        next_by_length[length] = run.end()
    for run in runs:
        if run.start() >= start and run.start() in closes:
            backslash = run.start()
            while backslash > start and body[backslash - 1] == '\\':
                backslash -= 1
            if (run.start() - backslash) % 2 == 0:
                yield start, run.start()
                start = closes[run.start()]
    yield start, end


def _paragraphs(body, start, end):
    for gap in _PARAGRAPH_BREAK.finditer(body, start, end):
        yield start, gap.start()
        start = gap.end()
    yield start, end


def mentions(body):
    """Yield (start, end, kind, value, raw cwd) outside Markdown code."""
    for start, end in _outside_fences(body):
        for first, last in _paragraphs(body, start, end):
            for a, b in _outside_inline_code(body, first, last):
                for match in _MENTION.finditer(body, a, b):
                    if match['handle'] is not None:
                        kind, value = 'handle', match['handle']
                    else:
                        try:
                            kind, value = 'anchor', int(match['anchor'])
                        except ValueError:  # a decimal string too large to be a post number
                            continue
                    yield match.start(), match.end(), kind, value, match['cwd'] or ''


_SCHEMA = """
BEGIN IMMEDIATE;
CREATE TABLE forums (
    id INTEGER PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'archived')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE TABLE threads (
    id INTEGER PRIMARY KEY,
    forum_id INTEGER NOT NULL REFERENCES forums(id),
    title TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'archived')),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);
CREATE INDEX threads_by_forum ON threads(forum_id);
CREATE TABLE posts (
    id INTEGER PRIMARY KEY,
    thread_id INTEGER NOT NULL REFERENCES threads(id),
    post_no INTEGER NOT NULL CHECK (post_no >= 1),
    author_handle TEXT NOT NULL,
    author_type TEXT NOT NULL CHECK (author_type IN ('human', 'agent', 'main', 'system')),
    body TEXT NOT NULL,
    cwd TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'ok' CHECK (status IN ('ok', 'error')),
    duration_ms INTEGER,
    created_at TEXT NOT NULL,
    UNIQUE(thread_id, post_no)
);
CREATE TABLE agent_sessions (
    agent_handle TEXT NOT NULL PRIMARY KEY,
    session_id TEXT,
    updated_at TEXT NOT NULL
);
CREATE TABLE job_queue (
    id INTEGER PRIMARY KEY,
    agent_handle TEXT NOT NULL,
    thread_id INTEGER NOT NULL REFERENCES threads(id),
    trigger_post_no INTEGER NOT NULL CHECK (trigger_post_no >= 1),
    requested_cwd TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued', 'running', 'done', 'error', 'cancelled', 'skipped', 'interrupted')),
    pid INTEGER,
    session_id TEXT,
    execution_generation INTEGER,
    detail TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL,
    started_at TEXT,
    finished_at TEXT
);
CREATE UNIQUE INDEX job_one_running ON job_queue(agent_handle) WHERE status = 'running';
CREATE INDEX job_fifo ON job_queue(agent_handle, status, id);
CREATE INDEX job_thread_status ON job_queue(thread_id, status);
CREATE TABLE read_state (
    reader_handle TEXT NOT NULL,
    thread_id INTEGER NOT NULL REFERENCES threads(id),
    last_read_post_no INTEGER NOT NULL CHECK (last_read_post_no >= 0),
    updated_at TEXT NOT NULL,
    PRIMARY KEY(reader_handle, thread_id)
);
PRAGMA user_version = 1;
COMMIT;
"""

_THREADS = """
SELECT t.*, f.name AS forum_name, f.status AS forum_status,
       (SELECT COUNT(*) FROM posts p WHERE p.thread_id=t.id) AS post_count,
       (SELECT COUNT(*) FROM job_queue j WHERE j.thread_id=t.id AND j.status='running') AS running,
       CASE WHEN :reader IS NOT NULL AND t.status='open' AND f.status='open' THEN (
           SELECT COUNT(*) FROM posts p WHERE p.thread_id=t.id AND p.author_handle<>:reader
             AND p.post_no>COALESCE(r.last_read_post_no,0)
       ) ELSE 0 END AS unread,
       :reader IS NOT NULL AND r.last_read_post_no IS NULL AND NOT EXISTS (
           SELECT 1 FROM posts p WHERE p.thread_id=t.id AND p.author_handle=:reader
       ) AS unvisited
FROM threads t JOIN forums f ON f.id=t.forum_id
LEFT JOIN read_state r ON r.thread_id=t.id AND r.reader_handle=:reader
"""
_THREAD_ORDER = ' ORDER BY t.updated_at DESC, t.id DESC'


class Board:
    def __init__(self, db_path, agents):
        self.db_path = Path(db_path).expanduser().absolute()
        self.agents = agents
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        # Serialize existence checking and schema creation across CLI/daemon
        # processes without leaving a sidecar lock file or opening an old DB
        # for writes before checking its version.
        directory = os.open(self.db_path.parent, os.O_RDONLY)
        try:
            flock(directory, LOCK_EX)
            self._initialize()
        finally:
            os.close(directory)

    @contextmanager
    def _connection(self, options='mode=rw'):
        conn = sqlite3.connect(f'{self.db_path.as_uri()}?{options}', uri=True,
                               timeout=30, isolation_level=None)
        conn.row_factory = sqlite3.Row
        try:
            yield conn
        finally:
            conn.close()

    def _initialize(self):
        try:
            fd = os.open(self.db_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            # Even an existing empty file is a version-0 DB, not a fresh DB.
            try:
                options = 'mode=ro'
                # A read-only probe of a clean WAL DB can otherwise create
                # new WAL/SHM sidecars. Do not ignore an existing WAL, though:
                # it may hold the latest committed schema version.
                if not self.db_path.with_name(self.db_path.name + '-wal').exists():
                    options += '&immutable=1'
                with self._connection(options) as conn:
                    version = conn.execute('PRAGMA user_version').fetchone()[0]
            except sqlite3.DatabaseError as exc:
                raise BoardError(f'Cannot read database: {exc}; back it up and move it aside manually') from exc
            if version != 1:
                raise BoardError(f'Unsupported database user_version {version} (expected 1); '
                                 'back it up and move it aside manually')
            with self._connection() as conn:
                self._configure(conn)
            return
        os.close(fd)
        try:
            with self._connection() as conn:
                conn.executescript(_SCHEMA)
                self._configure(conn)
        except BaseException:
            self.db_path.unlink()
            raise

    @staticmethod
    def _configure(conn):
        conn.execute('PRAGMA busy_timeout=30000')
        conn.execute('PRAGMA foreign_keys=ON')
        if conn.execute('PRAGMA journal_mode=WAL').fetchone()[0] != 'wal':
            raise BoardError('Could not enable WAL journal mode')

    @contextmanager
    def _transaction(self, begin):
        with self._connection() as conn:
            self._configure(conn)
            conn.execute(begin)
            with conn:
                yield conn

    def read(self):
        """Open a consistent read snapshot on a private connection."""
        return self._transaction('BEGIN')

    def write(self):
        """Acquire SQLite's writer lock before reading state for an update."""
        return self._transaction('BEGIN IMMEDIATE')

    @staticmethod
    def _name(value, field, limit):
        normalized = ' '.join(value.split())
        if not normalized or len(normalized) > limit:
            raise BoardError(f'{field} must contain between 1 and {limit} characters after normalization')
        return normalized

    def _forum(self, conn, name, stamp):
        conn.execute('INSERT INTO forums(name,created_at,updated_at) VALUES (?,?,?) '
                     'ON CONFLICT(name) DO NOTHING', (name, stamp, stamp))
        return conn.execute('SELECT * FROM forums WHERE name=?', (name,)).fetchone()

    def create_forum(self, name):
        name = self._name(name, 'Forum name', 40)
        with self.write() as conn:
            stamp = now()
            cursor = conn.execute('INSERT INTO forums(name,created_at,updated_at) VALUES (?,?,?) '
                                  'ON CONFLICT(name) DO NOTHING', (name, stamp, stamp))
            if not cursor.rowcount:
                raise BoardError(f'Forum already exists: {name}', 409)
            return cursor.lastrowid

    @staticmethod
    def _require_open(status, kind):
        if status == 'archived':
            raise BoardError(f'{kind} is archived; restore it first', 409)

    @staticmethod
    def _thread(conn, tid):
        row = conn.execute('''
            SELECT t.*, f.name AS forum_name, f.status AS forum_status
            FROM threads t JOIN forums f ON f.id=t.forum_id WHERE t.id=?
        ''', (tid,)).fetchone()
        if row is None:
            raise BoardError(f'Thread not found: {tid}', 404)
        return row

    def set_status(self, kind, id, status):
        table = {'forum': 'forums', 'thread': 'threads'}.get(kind)
        if table is None or status not in ('open', 'archived'):
            raise BoardError('Invalid archive operation')
        with self.write() as conn:
            cursor = conn.execute(f'UPDATE {table} SET status=?, updated_at=? WHERE id=?',
                                  (status, now(), id))
            if not cursor.rowcount:
                raise BoardError(f'{kind.capitalize()} not found: {id}', 404)

    def move(self, tid, forum_id):
        with self.write() as conn:
            thread = self._thread(conn, tid)
            forum = conn.execute('SELECT status FROM forums WHERE id=?', (forum_id,)).fetchone()
            if forum is None:
                raise BoardError(f'Forum not found: {forum_id}', 404)
            self._require_open(forum['status'], 'Destination forum')
            stamp = now()
            conn.execute('UPDATE threads SET forum_id=?, updated_at=? WHERE id=?', (forum_id, stamp, tid))
            conn.execute('UPDATE forums SET updated_at=? WHERE id IN (?,?)', (stamp, thread['forum_id'], forum_id))

    def _validate_post(self, body, author_handle, author_type):
        if not body.strip():
            raise BoardError('Post body must not be empty')
        if not ((author_type == 'human' and author_handle == 'user')
                or (author_type == 'agent' and author_handle in self.agents)
                or (author_type == 'main' and author_handle.startswith('main(')
                    and author_handle.endswith(')'))):
            raise BoardError('Invalid post author')

    @staticmethod
    def _mark(conn, handle, tid, post_no, stamp):
        conn.execute('''
            INSERT INTO read_state(reader_handle,thread_id,last_read_post_no,updated_at) VALUES (?,?,?,?)
            ON CONFLICT(reader_handle,thread_id) DO UPDATE SET
              last_read_post_no=excluded.last_read_post_no, updated_at=excluded.updated_at
            WHERE excluded.last_read_post_no > read_state.last_read_post_no
        ''', (handle, tid, post_no, stamp))

    def _insert_post(self, conn, thread, body, handle, author_type, cwd, stamp,
                     status='ok', duration_ms=None):
        tid = thread['id']
        post_no = conn.execute('SELECT COALESCE(MAX(post_no),0)+1 FROM posts WHERE thread_id=?',
                               (tid,)).fetchone()[0]
        conn.execute('''
            INSERT INTO posts(thread_id,post_no,author_handle,author_type,body,cwd,status,duration_ms,created_at)
            VALUES (?,?,?,?,?,?,?,?,?)
        ''', (tid, post_no, handle, author_type, body, cwd, status, duration_ms, stamp))
        conn.execute('UPDATE threads SET updated_at=? WHERE id=?', (stamp, tid))
        conn.execute('UPDATE forums SET updated_at=? WHERE id=?', (stamp, thread['forum_id']))
        if author_type in ('human', 'agent'):
            self._mark(conn, handle, tid, post_no, stamp)
        return post_no

    def new(self, forum, title, body, author_handle, author_type, cwd=''):
        self._validate_post(body, author_handle, author_type)
        forum = self._name(forum, 'Forum name', 40)
        title = self._name(title, 'Thread title', 100)
        with self.write() as conn:
            stamp = now()
            group = self._forum(conn, forum, stamp)
            self._require_open(group['status'], 'Forum')
            tid = conn.execute('INSERT INTO threads(forum_id,title,created_at,updated_at) VALUES (?,?,?,?)',
                               (group['id'], title, stamp, stamp)).lastrowid
            post_no = self._insert_post(conn, self._thread(conn, tid), body, author_handle, author_type, cwd, stamp)
            if author_type == 'human':
                self._enqueue(conn, tid, post_no, body, author_handle, stamp)
            return tid, post_no

    def _enqueue(self, conn, tid, post_no, body, author_handle, stamp):
        recipients = {}
        for _, _, kind, value, cwd in mentions(body):
            if kind == 'anchor':
                if not 1 <= value < post_no:
                    continue
                post = conn.execute("SELECT author_handle FROM posts WHERE thread_id=? AND post_no=? "
                                    "AND author_type='agent'", (tid, value)).fetchone()
                if post is None:
                    continue
                value = post['author_handle']
            if value == author_handle or value not in self.agents:
                continue
            if not recipients.get(value):
                recipients[value] = os.path.abspath(os.path.expanduser(cwd)) if cwd else ''
        conn.executemany('''
            INSERT INTO job_queue(agent_handle,thread_id,trigger_post_no,requested_cwd,created_at)
            VALUES (?,?,?,?,?)
        ''', ((handle, tid, post_no, cwd, stamp) for handle, cwd in recipients.items()))

    def reply(self, tid, body, author_handle, author_type, cwd='', *, report_policy=False):
        """Optionally return (post number, wake eligibility), regardless of actual mentions."""
        self._validate_post(body, author_handle, author_type)
        with self.write() as conn:
            thread = self._thread(conn, tid)
            self._require_open(thread['forum_status'], 'Forum')
            self._require_open(thread['status'], 'Thread')
            wake_eligible = author_type == 'human' or (
                author_type == 'agent' and conn.execute(
                    "SELECT 1 FROM job_queue WHERE agent_handle=? AND thread_id=? AND status='running'",
                    (author_handle, tid),
                ).fetchone() is not None
            )
            stamp = now()
            post_no = self._insert_post(conn, thread, body, author_handle, author_type, cwd, stamp)
            if wake_eligible:
                self._enqueue(conn, tid, post_no, body, author_handle, stamp)
            return (post_no, wake_eligible) if report_policy else post_no

    def error(self, c, tid, body, cwd='', duration_ms=None):
        """Record a worker failure in its completion transaction, even if archived."""
        return self._insert_post(c, self._thread(c, tid), body, 'system', 'system', cwd,
                                 now(), status='error', duration_ms=duration_ms)

    def _reader(self, handle):
        return handle if handle == 'user' or handle in self.agents else None

    @staticmethod
    def last_read(c, handle, tid):
        row = c.execute('SELECT last_read_post_no FROM read_state WHERE reader_handle=? AND thread_id=?',
                        (handle, tid)).fetchone()
        return row[0] if row is not None else 0

    def forums(self, archived=False, reader=None):
        with self.read() as conn:
            return [dict(row) for row in conn.execute('''
                SELECT f.*,
                       (SELECT COUNT(*) FROM threads t WHERE t.forum_id=f.id
                          AND (:archived OR t.status='open')) AS thread_count,
                       CASE WHEN :reader IS NOT NULL AND f.status='open' THEN (
                           SELECT COUNT(*) FROM threads t JOIN posts p ON p.thread_id=t.id
                           LEFT JOIN read_state r ON r.thread_id=t.id AND r.reader_handle=:reader
                           WHERE t.forum_id=f.id AND t.status='open' AND p.author_handle<>:reader
                             AND p.post_no>COALESCE(r.last_read_post_no,0)
                       ) ELSE 0 END AS unread
                FROM forums f WHERE (:archived OR f.status='open')
                ORDER BY f.updated_at DESC, f.id DESC
            ''', {'archived': archived, 'reader': self._reader(reader)})]

    @staticmethod
    def _thread_view(row, reader):
        thread = dict(row)
        unvisited = thread.pop('unvisited')
        if reader is None:
            label = ''
        elif unvisited:
            label = '[未閲覧]'
        elif thread['unread']:
            label = f"[未読 {thread['unread']}件]"
        else:
            label = '[既読]'
        thread['read_label'] = label
        return thread

    def threads(self, forum=None, archived=False, reader=None):
        if forum is not None:
            forum = self._name(forum, 'Forum name', 40)
        reader = self._reader(reader)
        where = " WHERE (:forum IS NULL OR f.name=:forum) AND (:archived OR (f.status='open' AND t.status='open'))"
        with self.read() as conn:
            rows = conn.execute(_THREADS + where + _THREAD_ORDER,
                                {'forum': forum, 'archived': archived, 'reader': reader})
            return [self._thread_view(row, reader) for row in rows]

    def show(self, tid, since=0, reader=None, mark=False):
        reader = self._reader(reader)
        mark = mark and reader is not None
        with (self.write() if mark else self.read()) as conn:
            posts = [dict(row) for row in conn.execute(
                'SELECT * FROM posts WHERE thread_id=? AND post_no>? ORDER BY post_no', (tid, since)
            )]
            if mark and posts:
                self._mark(conn, reader, tid, posts[-1]['post_no'], now())
            thread = conn.execute(_THREADS + ' WHERE t.id=:tid', {'reader': reader, 'tid': tid}).fetchone()
            if thread is None:
                raise BoardError(f'Thread not found: {tid}', 404)
            return self._thread_view(thread, reader), posts

    def search(self, terms, any_word=False, forum=None, author=None, limit=20):
        if isinstance(terms, str):
            terms = [terms]
        words = list(dict.fromkeys(word.casefold() for term in terms for word in term.split()))
        if not words:
            raise BoardError('Search needs at least one keyword')
        if limit < 1:
            raise BoardError('Search limit must be positive')
        if forum is not None:
            forum = self._name(forum, 'Forum name', 40)

        # Match each keyword anywhere in the thread. With an author filter,
        # only that author's bodies can supply a match, not even the title.
        params = {'reader': None, 'forum': forum, 'author': author, 'limit': limit}
        params.update({f'word{i}': word for i, word in enumerate(words)})
        keywords = 'WITH keywords(word) AS (VALUES ' + ','.join(f'(:word{i})' for i in range(len(words))) + ') '
        body_hit = '(:author IS NULL OR p.author_handle=:author) AND instr(fold(p.body), k.word)>0'
        hit = f'''((:author IS NULL AND instr(fold(t.title), k.word)>0) OR EXISTS (
            SELECT 1 FROM posts p WHERE p.thread_id=t.id AND {body_hit}
        ))'''
        keyword_filter = (f'EXISTS (SELECT 1 FROM keywords k WHERE {hit})' if any_word else
                          f'NOT EXISTS (SELECT 1 FROM keywords k WHERE NOT {hit})')
        with self.read() as conn:
            conn.create_function('fold', 1, str.casefold, deterministic=True)
            rows = conn.execute(keywords + _THREADS + ' WHERE (:forum IS NULL OR f.name=:forum) AND ' +
                                keyword_filter + _THREAD_ORDER + ' LIMIT :limit', params)
            threads = [self._thread_view(row, None) for row in rows]
            for thread in threads:
                threads_params = {**params, 'tid': thread['id']}
                thread['matches'] = [dict(row) for row in conn.execute(keywords + f'''
                    SELECT p.* FROM posts p WHERE p.thread_id=:tid
                      AND EXISTS (SELECT 1 FROM keywords k WHERE {body_hit}) ORDER BY p.post_no
                ''', threads_params)]
            return threads

    def status(self):
        with self.read() as conn:
            counts = dict(conn.execute("SELECT agent_handle, COUNT(*) FROM job_queue WHERE status='queued' "
                                       'GROUP BY agent_handle').fetchall())
            running = {row['agent_handle']: row for row in conn.execute(
                "SELECT agent_handle,thread_id,started_at FROM job_queue WHERE status='running'"
            )}
            return [dict(handle=handle, running=handle in running, queued=counts.get(handle, 0),
                         thread_id=running[handle]['thread_id'] if handle in running else None,
                         started_at=running[handle]['started_at'] if handle in running else None)
                    for handle in self.agents]

    def reset(self, handle):
        if handle not in self.agents:
            raise BoardError(f'Agent not found: {handle}', 404)
        with self.write() as conn:
            if conn.execute("SELECT 1 FROM job_queue WHERE agent_handle=? AND status='running'", (handle,)).fetchone():
                raise BoardError(f'{handle} is running; stop the agent before resetting its session', 409)
            conn.execute('DELETE FROM agent_sessions WHERE agent_handle=?', (handle,))
            conn.execute('DELETE FROM read_state WHERE reader_handle=?', (handle,))
