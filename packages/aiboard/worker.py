"""The daemon's sole owner of the resident queue and child processes."""

from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
import errno
from fcntl import LOCK_EX, LOCK_NB, flock
import logging
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import tempfile
import threading
import time

from board import BoardError, now
import gateway_rpc


LOG = logging.getLogger(__name__)
ANSI = re.compile(r'\x1b(?:\][^\x07\x1b]*(?:\x07|\x1b\\)|\[[0-?]*[ -/]*[@-~]|[ -/]*[@-Z\\-_])')


class _SessionOutput:
    """Copy stderr into the execution log, retaining only its control line."""

    def __init__(self, pipe, log):
        self.fd = pipe.fileno()
        os.set_blocking(self.fd, False)
        self.log = log
        self.partial = b''
        self.sid = None

    def drain(self):
        # Stay responsive even when the client writes stderr continuously.
        for _ in range(16):
            try:
                data = os.read(self.fd, 65536)
            except BlockingIOError:
                break
            if not data:
                break
            self.log.write(data)
            if self.sid is not None:
                continue
            *lines, self.partial = (self.partial + data).split(b'\n')
            for line in lines:
                if line.startswith(b'Session: '):
                    sid = line[9:].rstrip(b'\r').decode('ascii', errors='replace')
                    if gateway_rpc.SESSION.fullmatch(sid):
                        self.sid = sid
                        break
            if len(self.partial) > 512:
                # Keep the sentinel so a truncated line cannot look like a
                # Session record on the next read.
                self.partial = b'!'


@dataclass
class _Job:
    row: dict
    finished: threading.Event = field(default_factory=threading.Event)
    wake: threading.Event = field(default_factory=threading.Event)
    # Set under WorkerManager._lock, before any interrupt is sent.
    stop_reason: str | None = None
    stop_error: str | None = None


class WorkerManager:
    def __init__(self, board, settings, *, poll_interval=.2, grace_period=5):
        self.board = board
        self.settings = settings
        self.poll_interval = poll_interval
        self.grace_period = grace_period
        self._lock = threading.Lock()
        self._lifecycle = threading.Lock()
        self._closing = threading.Event()
        self._active = {}
        self._threads = []
        self._lock_fd = None

    def start(self):
        """Take exclusive ownership before looking for abandoned jobs."""
        with self._lifecycle:
            if self._lock_fd is not None:
                return
            db = self.board.db_path.resolve()
            fd = os.open(db.with_name(db.name + '.serve.lock'), os.O_CREAT | os.O_RDWR, 0o600)
            try:
                flock(fd, LOCK_EX | LOCK_NB)
            except OSError as exc:
                os.close(fd)
                if exc.errno in (errno.EACCES, errno.EAGAIN):
                    raise BoardError('another aiboard daemon owns this database', 409) from exc
                raise
            self._lock_fd = fd
            try:
                self._closing.clear()
                self._recover()
                for handle in self.settings.agents:
                    thread = threading.Thread(target=self._serve, args=(handle,), name=f'aiboard-{handle}')
                    thread.start()
                    self._threads.append(thread)
            except BaseException:
                self._shutdown()
                raise

    def shutdown(self):
        with self._lifecycle:
            self._shutdown()

    def _shutdown(self):
        with self._lock:
            self._closing.set()
            for job in self._active.values():
                if job.stop_reason is None:
                    job.stop_reason = 'interrupted'
                job.wake.set()
        for thread in self._threads:
            thread.join()
        self._threads.clear()
        if self._lock_fd is not None:
            os.close(self._lock_fd)
            self._lock_fd = None

    def stop(self, handle):
        """Stop the selected job, never a successor in the same resident's FIFO."""
        with self._lock:
            job = self._active.get(handle)
            if job is None:
                raise BoardError(f'{handle} is not running', 409)
            if job.stop_reason is None:
                job.stop_reason = 'cancelled'
            job.wake.set()
        job.finished.wait()
        if job.stop_error:
            raise BoardError(job.stop_error, 409)
        return True

    def _claim(self, handle):
        with self.board.write() as conn:
            row = conn.execute('''SELECT j.*, t.status AS thread_status, f.status AS forum_status,
                                         s.session_id AS resume_id
                                  FROM job_queue j JOIN threads t ON t.id=j.thread_id
                                  JOIN forums f ON f.id=t.forum_id
                                  LEFT JOIN agent_sessions s ON s.agent_handle=j.agent_handle
                                  WHERE j.agent_handle=? AND j.status='queued'
                                    AND NOT EXISTS (SELECT 1 FROM job_queue active
                                        WHERE active.agent_handle=j.agent_handle AND active.status='running')
                                  ORDER BY j.id LIMIT 1''',
                               (handle,)).fetchone()
            if row is None:
                return None
            detail = self._brake(conn, row)
            if detail:
                conn.execute("UPDATE job_queue SET status='skipped', detail=?, finished_at=? WHERE id=?",
                             (detail, now(), row['id']))
                LOG.info('skipped job %s: %s', row['id'], detail)
                return None
            conn.execute("UPDATE job_queue SET status='running', started_at=? WHERE id=?", (now(), row['id']))
            return _Job(dict(row))

    def _brake(self, conn, row):
        for key in ('thread', 'forum'):
            if row[key + '_status'] == 'archived':
                return f'{key} archived'
        tid = row['thread_id']
        chain = conn.execute('''SELECT count(*) FROM posts WHERE thread_id=?
            AND author_type IN ('agent','main') AND post_no > COALESCE(
                (SELECT max(post_no) FROM posts WHERE thread_id=? AND author_type='human'), 0)''',
                             (tid, tid)).fetchone()[0]
        if chain >= self.settings.defaults['chain_limit']:
            return 'chain limit reached'
        cutoff = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat(timespec='microseconds')
        hourly = conn.execute("SELECT count(*) FROM posts WHERE author_type IN ('agent','main') AND created_at>=?",
                              (cutoff,)).fetchone()[0]
        if hourly >= self.settings.defaults['hourly_limit']:
            return 'hourly limit reached'
        return ''

    def _serve(self, handle):
        while not self._closing.is_set():
            try:
                with self._lock:
                    if self._closing.is_set():
                        break
                    job = self._claim(handle)
                    if job is not None:
                        self._active[handle] = job
                if job is not None:
                    self._run(job, self.settings.agents[handle])
                    continue
            except Exception:
                LOG.exception('worker %s failed', handle)
            self._closing.wait(self.poll_interval)

    def _launch_paths(self, row):
        work = self.settings.data_dir / 'work' / row['agent_handle']
        work.mkdir(parents=True, exist_ok=True)
        requested = Path(row['requested_cwd']) if row['requested_cwd'] else None
        return work, requested if requested is not None and requested.is_dir() else work

    def _prompt(self, row, work, cwd, target):
        handle, tid, trigger = (row[key] for key in ('agent_handle', 'thread_id', 'trigger_post_no'))
        cli = [self.settings.cli]
        if self.settings.nondefault_paths:
            cli += ['--db', str(self.settings.db_path), '--config', str(self.settings.config_path)]
        cli = shlex.join(cli)
        with self.board.read() as conn:
            post = conn.execute('SELECT body FROM posts WHERE thread_id=? AND post_no=?', (tid, trigger)).fetchone()
            last_read = conn.execute('SELECT last_read_post_no FROM read_state WHERE reader_handle=? AND thread_id=?',
                                     (handle, tid)).fetchone()
            last_read = last_read[0] if last_read else 0
            earlier = conn.execute('''SELECT count(*) FROM posts WHERE thread_id=? AND author_handle<>?
                                      AND post_no>? AND post_no<?''', (tid, handle, last_read, trigger)).fetchone()[0]
            unread = conn.execute('''SELECT t.id, f.name, t.title, count(*) FROM threads t
                JOIN forums f ON f.id=t.forum_id JOIN posts p ON t.id=p.thread_id
                LEFT JOIN read_state r ON r.thread_id=t.id AND r.reader_handle=?
                WHERE t.id<>? AND t.status='open' AND f.status='open' AND p.author_handle<>?
                AND p.post_no>COALESCE(r.last_read_post_no, 0) GROUP BY t.id ORDER BY t.id''', (handle, tid, handle)).fetchall()
        if post is None:
            raise ValueError(f'missing trigger post #{tid} >>{trigger}')
        lines = [f'住人: @{handle}', f'作業ディレクトリ: {cwd}', f'一時ディレクトリ: {work}',
                 f'共有 Wiki: {Path.home() / "sagyo/llm-wiki"}']
        if target != cwd:
            lines.append(f'対象ディレクトリ: {target}')
        lines += [f'本題スレッド: #{tid}', f'閲覧: {cli} show {tid}',
                  f"返信: {cli} reply {tid} '本文'", f"検索: {cli} search 'キーワード'",
                  f'\nメンションされたレス >>{trigger}:\n{post[0]}']
        if earlier:
            lines.append(f'\n本題のメンションより前の未読: {earlier} 件 ({cli} show {tid} --since {last_read})')
        if unread:
            lines.append('\n他の未読スレッド:')
            lines.extend(f'[{i}] [{forum}] {title} — 未読 {count} 件' for i, forum, title, count in unread)
        return '\n'.join(lines) + '\n'

    def _child_env(self, row):
        env = os.environ.copy()
        env.pop('AIBOARD_FOCUS_THREAD', None)
        env.update(AIBOARD_DATA_DIR=str(self.settings.data_dir), AIBOARD_DB=str(self.settings.db_path),
                   AIBOARD_CONFIG=str(self.settings.config_path), AIBOARD_LOG_DIR=str(self.settings.log_dir),
                   AIBOARD_CLI=self.settings.cli, NO_COLOR='1', AIBOARD_AGENT=row['agent_handle'],
                   AIBOARD_JOB_ID=str(row['id']))
        return env

    def _run(self, job, agent):
        row = job.row
        handle, tid, jid = (row[k] for k in ('agent_handle', 'thread_id', 'id'))
        path = self.settings.log_dir / f'{datetime.now():%Y%m%d-%H%M%S}-{handle}-t{tid}-j{jid}.log'
        started = time.monotonic()
        code, detail, cwd, process = 1, '', '', None
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open('ab', buffering=0) as log:
                try:
                    work, target = self._launch_paths(row)
                    hermes = agent.get('kind', 'hermes') == 'hermes'
                    cwd = work if hermes else target
                    prompt = self._prompt(row, work, cwd, target)
                    args = self._command(agent, row, cwd)
                    if hermes and row['resume_id'] and not job.stop_reason:
                        state = gateway_rpc.call(agent['profile'], 'inspect', row['resume_id'])
                        if state['running']:
                            raise gateway_rpc.GatewayError('Hermes session is already running another turn')
                    if not job.stop_reason:
                        env = self._child_env(row)
                        if hermes:
                            env.pop('HERMES_TUI_GATEWAY_URL', None)
                            env['PYTHONIOENCODING'] = 'utf-8'
                        with tempfile.TemporaryFile() as stdin:
                            stdin.write(prompt.encode('utf-8'))
                            stdin.seek(0)
                            process = subprocess.Popen(args, cwd=cwd, env=env, stdin=stdin,
                                                       stdout=log, stderr=subprocess.PIPE if hermes else log,
                                                       start_new_session=True)
                        with self.board.write() as conn:
                            conn.execute('UPDATE job_queue SET pid=? WHERE id=?', (process.pid, jid))
                        if hermes:
                            code = self._monitor_hermes(job, agent['profile'], process, log, prompt)
                        else:
                            code = self._monitor_custom(job, process)
                except Exception as exc:
                    detail = str(exc)
                    log.write((detail + '\n').encode('utf-8', 'replace'))
        except OSError as exc:
            detail = str(exc)
        finally:
            try:
                if process is not None:
                    try:
                        self._terminate_group(process.pid, process)
                    finally:
                        if process.stderr is not None:
                            process.stderr.close()
            finally:
                with self._lock:
                    try:
                        self._finish(job, code, detail, path, cwd, started)
                    except Exception:
                        job.stop_error = f'could not finalize job {jid}'
                        raise
                    finally:
                        self._active.pop(handle, None)
                        job.finished.set()

    def _command(self, agent, row, cwd):
        if agent.get('kind') == 'custom':
            return [arg.replace('{cwd}', str(cwd)) for arg in agent['command']]
        options = self.settings.defaults | agent
        args = ['hermes', '-p', agent['profile'], 'chat', '--query-file', '-', '--oneshot', '-Q',
                '--format', 'stream-json', '--in', str(cwd), '--max-turns', str(options['max_turns']),
                '--model', agent['model']]
        if options.get('toolsets') is not None:
            tools = options['toolsets']
            args += ['--toolsets', tools if isinstance(tools, str) else ','.join(tools)]
        if options.get('reasoning') is not None:
            args += ['--reasoning', options['reasoning']]
        if row['resume_id']:
            args += ['--resume', row['resume_id']]
        return args

    def _monitor_custom(self, job, process):
        while process.poll() is None:
            if job.stop_reason:
                self._terminate_group(process.pid, process)
                break
            job.wake.wait(self.poll_interval)
        return process.wait()

    def _save_session(self, job, sid):
        with self.board.write() as conn:
            conn.execute('UPDATE job_queue SET session_id=? WHERE id=?', (sid, job.row['id']))
            conn.execute('''INSERT INTO agent_sessions(agent_handle, session_id, updated_at) VALUES (?, ?, ?)
                            ON CONFLICT(agent_handle) DO UPDATE SET
                            session_id=excluded.session_id, updated_at=excluded.updated_at''',
                         (job.row['agent_handle'], sid, now()))

    def _monitor_hermes(self, job, profile, process, log, prompt):
        output = _SessionOutput(process.stderr, log)
        own_prompt = gateway_rpc.prompt_digest(prompt)
        sid, generation = None, None
        next_probe, stop_deadline = 0., None
        while True:
            code = process.poll()
            output.drain()
            if output.sid and sid is None:
                sid = output.sid
                self._save_session(job, sid)

            if job.stop_reason and stop_deadline is None:
                stop_deadline = time.monotonic() + self.grace_period
                next_probe = 0.
            if (sid and generation is None and time.monotonic() >= next_probe
                    and (code != 0 or stop_deadline is not None)):
                try:
                    state = gateway_rpc.call(profile, 'inspect', sid)
                    if state['running'] and state.get('prompt_sha256') == own_prompt:
                        generation = state['execution_generation']
                        with self.board.write() as conn:
                            conn.execute('UPDATE job_queue SET execution_generation=? WHERE id=?',
                                         (generation, job.row['id']))
                except gateway_rpc.GatewayError:
                    # The CLI may have emitted the ID before its admission
                    # started. Retry while watching this client, not another.
                    pass
                next_probe = time.monotonic() + max(self.poll_interval, .4)

            if stop_deadline is not None and generation is not None:
                deadline, warning = self._interrupt(profile, sid, generation, pump=output.drain)
                if warning:
                    self._stop_warning(job, log, warning)
                self._wait_for_group(process.pid, process=process, pump=output.drain, deadline=deadline)
                self._terminate_group(process.pid, process, pump=output.drain)
                output.drain()
                return process.wait()
            if code is not None:
                if code != 0 and generation is not None:
                    # Losing the CLI doesn't prove its turn stopped. This is
                    # also safe after ordinary turn failures (no running turn).
                    _, warning = self._interrupt(profile, sid, generation, pump=output.drain)
                    if warning:
                        self._stop_warning(job, log, warning)
                elif code != 0 and stop_deadline is not None:
                    self._stop_warning(job, log, 'could not confirm the Hermes execution generation')
                return code
            if stop_deadline is not None and time.monotonic() >= stop_deadline:
                self._stop_warning(job, log, 'could not confirm the Hermes execution generation')
                self._terminate_group(process.pid, process, pump=output.drain)
                output.drain()
                return process.wait()
            if stop_deadline is None:
                job.wake.wait(self.poll_interval)
            else:
                time.sleep(self.poll_interval)

    @staticmethod
    def _stop_warning(job, log, detail):
        job.stop_error = detail
        log.write((detail + '\n').encode())

    def _interrupt(self, profile, sid, generation, *, pump=None):
        """Attempt and confirm a targeted stop, sharing the client's grace period."""
        deadline = time.monotonic() + self.grace_period
        try:
            state = gateway_rpc.call(profile, 'interrupt', sid, generation)
            deadline = time.monotonic() + self.grace_period
            # An acknowledged request is not yet a settled turn. Check the
            # same generation while the CLI has a chance to exit on its own.
            while state['running'] and state['execution_generation'] == generation:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return deadline, 'Hermes did not confirm that the interrupted turn ended'
                if pump is not None:
                    pump()
                state = gateway_rpc.call(profile, 'inspect', sid, timeout=remaining)
                if state['running'] and state['execution_generation'] == generation:
                    time.sleep(min(self.poll_interval, max(0, deadline - time.monotonic())))
        except gateway_rpc.GatewayError as exc:
            return deadline, str(exc)
        return deadline, None

    def _wait_for_group(self, pid, process=None, *, marker=None, pump=None, deadline=None):
        if deadline is None:
            deadline = time.monotonic() + self.grace_period
        while True:
            if pump is not None:
                pump()
            if not _group_alive(pid, process, marker):
                return True
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            time.sleep(min(self.poll_interval, remaining))

    def _terminate_group(self, pid, process=None, *, marker=None, pump=None):
        if not _group_alive(pid, process, marker):
            return
        try:
            os.killpg(pid, signal.SIGTERM)
            if not self._wait_for_group(pid, process, marker=marker, pump=pump):
                if _group_alive(pid, process, marker):
                    os.killpg(pid, signal.SIGKILL)
                self._wait_for_group(pid, process, marker=marker, pump=pump)
        except ProcessLookupError:
            pass

    def _finish(self, job, code, detail, path, cwd, started):
        status = job.stop_reason or ('done' if code == 0 else 'error')
        if status == 'cancelled':
            detail = 'stopped by user'
        elif status == 'interrupted':
            detail = 'daemon shutdown'
        if status == 'error':
            detail = detail or f'process exited with code {code}'
            try:
                text = ANSI.sub('', path.read_text(encoding='utf-8', errors='replace'))
                excerpt = '\n'.join(text.splitlines()[-30:])[-2000:]
            except OSError:
                excerpt = detail
        try:
            with path.open('ab') as log:
                log.write(f'\n--- exit_code: {code}, reason: {status} ---\n'.encode())
        except OSError:
            LOG.exception('could not write job log %s', path)
        with self.board.write() as conn:
            conn.execute('UPDATE job_queue SET status=?, detail=?, pid=NULL, finished_at=? WHERE id=?',
                         (status, detail, now(), job.row['id']))
            if status == 'error':
                self.board.error(conn, job.row['thread_id'], f'[ERROR] exit_code: {code}\nlog: {path}\n{excerpt or detail}',
                                 str(cwd), int((time.monotonic() - started) * 1000))

    def _recover(self):
        with self.board.read() as conn:
            rows = conn.execute("SELECT * FROM job_queue WHERE status='running' ORDER BY id").fetchall()
        for row in rows:
            handle, tid, jid, pid = (row[k] for k in ('agent_handle', 'thread_id', 'id', 'pid'))
            detail = 'recovered after daemon restart'
            agent = self.settings.agents.get(handle)
            sid, generation = row['session_id'], row['execution_generation']
            deadline = None
            if sid and generation is not None:
                if agent is None or agent.get('kind', 'hermes') != 'hermes':
                    detail += '; Hermes profile unavailable'
                else:
                    deadline, warning = self._interrupt(agent['profile'], sid, generation)
                    if warning:
                        detail += f'; {warning}'
            if pid:
                marker = {f'{key}={value}'.encode() for key, value in
                          {'AIBOARD_AGENT': handle, 'AIBOARD_JOB_ID': jid,
                           'AIBOARD_DB': self.settings.db_path}.items()}
                try:
                    if deadline is not None:
                        self._wait_for_group(pid, marker=marker, deadline=deadline)
                    self._terminate_group(pid, marker=marker)
                except OSError as exc:
                    detail += f'; could not stop process group: {exc}'
            # The orphan was not our child; no portable exit status exists.
            for path in self.settings.log_dir.glob(f'*-{handle}-t{tid}-j{jid}.log'):
                try:
                    with path.open('ab') as log:
                        log.write(f'\n{detail}\n--- exit_code: , reason: interrupted ---\n'.encode())
                except OSError:
                    LOG.exception('could not append recovery to %s', path)
            with self.board.write() as conn:
                conn.execute("UPDATE job_queue SET status='interrupted', pid=NULL, detail=?, finished_at=? WHERE id=?",
                             (detail, now(), jid))


def _group_alive(pid, process, marker):
    if pid <= 1:
        return False
    if process is not None and process.poll() is None:
        return True
    try:
        os.killpg(pid, 0)
    except (ProcessLookupError, PermissionError):
        return False
    # killpg(..., 0) counts zombies. On Linux, look for a live member of
    # this exact session and process group. For recovery the stored PID by
    # itself proves nothing; verify the agent, job and DB in its environment.
    proc = Path('/proc')
    if not (proc / 'self/stat').exists():
        return marker is None
    for member in proc.iterdir():
        if not member.name.isdigit():
            continue
        try:
            state, _, group, session, *_ = (member / 'stat').read_text().rsplit(')', 1)[1].split()
            if state in ('Z', 'X') or (int(group), int(session)) != (pid, pid):
                continue
            if marker is None or marker.issubset((member / 'environ').read_bytes().split(b'\0')):
                return True
        except (OSError, ValueError, IndexError, UnicodeError):
            continue
    return False
