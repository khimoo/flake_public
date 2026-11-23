import asyncio
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import AsyncMock
from unittest.mock import patch

from board import Board, BoardError
from config import Settings


class GatewayTests(unittest.TestCase):
    def test_inspect_projects_only_the_started_admission_for_current_generation(self):
        from gateway_rpc import _project
        client = AsyncMock()
        client.rpc.return_value = {'stored_session_id': 'local-test', 'running': True,
                                   'execution_generation': 7, 'messages': ['secret'], 'pending': [
                                       {'status': 'started', 'execution_generation': 6, 'text': 'previous'},
                                       {'status': 'started', 'execution_generation': 7, 'text': 'expected'},
                                   ]}
        state = asyncio.run(_project(client, 'inspect', 'local-test', None, RuntimeError))
        self.assertEqual(state, dict(running=True, execution_generation=7,
                                     prompt_sha256=hashlib.sha256(b'expected').hexdigest()))
        client.rpc.assert_awaited_once_with('session.resume', session_id='local-test', omit_messages=True)

    def test_interrupt_does_not_act_on_another_generation(self):
        from gateway_rpc import _project
        client = AsyncMock()
        client.rpc.return_value = {'stored_session_id': 'local-test', 'running': True,
                                   'execution_generation': 7}
        state = asyncio.run(_project(client, 'interrupt', 'local-test', 6, RuntimeError))
        self.assertEqual(state, dict(running=True, execution_generation=7))
        client.rpc.assert_awaited_once_with('session.resume', session_id='local-test', omit_messages=True)

    def test_interrupt_race_does_not_retry_against_newer_generation(self):
        from gateway_rpc import _project
        client = AsyncMock()
        client.rpc.side_effect = [{'stored_session_id': 'local-test', 'running': True,
                                   'execution_generation': 7}, RuntimeError('stale_generation')]
        state = asyncio.run(_project(client, 'interrupt', 'local-test', 7, RuntimeError))
        self.assertEqual(state, dict(running=False, execution_generation=7))
        self.assertEqual(client.rpc.await_count, 2)
        client.rpc.assert_awaited_with('session.interrupt', session_id='local-test', execution_generation=7)


class WorkerTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        env = patch.dict(os.environ, {'AIBOARD_DATA_DIR': str(self.root),
                                      'AIBOARD_LOG_DIR': str(self.root / 'logs'),
                                      'AIBOARD_CLI': 'aiboard', 'HERMES_HOME': str(self.root / 'hermes')})
        env.start()
        self.addCleanup(env.stop)

    def setup_board(self, agents, **defaults):
        from worker import WorkerManager
        config = self.root / 'agents.json'
        config.write_text(json.dumps({'agents': agents, 'defaults': defaults}))
        self.settings = Settings.load(db=self.root / 'test.db', config=config)
        self.board = Board(self.settings.db_path, self.settings.agents)
        self.manager = WorkerManager(self.board, self.settings, poll_interval=.02, grace_period=.25)
        self.addCleanup(self.manager.shutdown)

    @staticmethod
    def custom(code, *args):
        return dict(kind='custom', command=[sys.executable, '-c', code, *args])

    def mention(self, body, title='topic'):
        return self.board.new('general', title, body, 'user', 'human')[0]

    def rows(self):
        with self.board.read() as conn:
            return [dict(r) for r in conn.execute('SELECT * FROM job_queue ORDER BY id')]

    def await_(self, predicate):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            if result := predicate():
                return result
            time.sleep(.02)
        self.fail(f'timed out; jobs: {self.rows()}')

    def statuses(self, *statuses):
        return self.await_(lambda: [row['status'] for row in self.rows()] == list(statuses))

    def test_parallel_residents_and_fifo(self):
        self.setup_board({'one': self.custom('''
import os, pathlib, sys, time
prompt = sys.stdin.read()
if 'first' in prompt:
    pathlib.Path('started').touch()
    while not pathlib.Path('release').exists():
        time.sleep(.02)
    print(os.environ['AIBOARD_AGENT'], sys.argv[1])
else:
    print('second')
''', '{cwd}'), 'two': self.custom('print("parallel")')})
        self.mention('@one first')
        path = self.settings.data_dir / 'work' / 'one'
        self.mention('@one second', 'next')
        self.mention('@two', 'parallel')
        self.manager.start()
        self.await_(lambda: (path / 'started').exists())
        self.statuses('running', 'queued', 'done')
        (path / 'release').touch()
        self.statuses('done', 'done', 'done')
        self.assertIn(f'one {path}', next(self.settings.log_dir.glob('*-j1.log')).read_text())
        with self.board.read() as conn:
            self.assertEqual(conn.execute('SELECT COUNT(*) FROM posts').fetchone()[0], 3)
            self.assertEqual(conn.execute('SELECT COUNT(*) FROM read_state WHERE reader_handle != ?', ('user',)).fetchone()[0], 0)

    def test_stop_kills_group_and_continues_next_job(self):
        self.setup_board({'one': self.custom('''
import pathlib, signal, subprocess, sys, time
if 'first' in sys.stdin.read():
    signal.signal(signal.SIGTERM, lambda *args: sys.exit(7))
    child = subprocess.Popen([sys.executable, '-c',
        "import pathlib, signal, time; signal.signal(signal.SIGTERM, signal.SIG_IGN); "
        "pathlib.Path('ready').touch(); time.sleep(30)"])
    pathlib.Path('child').write_text(str(child.pid))
    time.sleep(30)
''')})
        self.mention('@one first')
        self.mention('@one second', 'next')
        self.manager.start()
        workspace = self.root / 'work' / 'one'
        self.await_(lambda: (workspace / 'ready').exists() and (workspace / 'child').exists())
        child = int((workspace / 'child').read_text())
        def child_stopped():
            try:
                return Path(f'/proc/{child}/stat').read_text().rsplit(')', 1)[1].split()[0] == 'Z'
            except FileNotFoundError:
                return True
        self.manager.stop('one')
        self.statuses('cancelled', 'done')
        self.await_(child_stopped)
        self.assertEqual(self.rows()[0]['detail'], 'stopped by user')
        self.assertIn('exit_code: 7, reason: cancelled', next(self.settings.log_dir.glob('*-j1.log')).read_text())
        with self.board.read() as conn:
            self.assertEqual(conn.execute('SELECT COUNT(*) FROM posts').fetchone()[0], 2)

    def test_nonzero_reports_only_ansi_stripped_tail(self):
        self.setup_board({'one': self.custom('''
import sys
print('older-line', flush=True)
for i in range(29): print(f'middle-{i}', flush=True)
print('\\x1b[31m' + 'あ' * 2050 + '@one\\x1b[0m', file=sys.stderr)
raise SystemExit(17)
''')})
        tid = self.mention('@one')
        self.manager.start()
        self.statuses('error')
        with self.board.read() as conn:
            post = conn.execute('SELECT * FROM posts WHERE thread_id=? AND post_no=2', (tid,)).fetchone()
        self.assertEqual((post['author_handle'], post['author_type'], post['status']), ('system', 'system', 'error'))
        self.assertIn('exit_code: 17', post['body'])
        self.assertNotIn('older-line', post['body'])
        self.assertNotIn('\x1b', post['body'])
        self.assertEqual(post['body'].splitlines()[-1], 'あ' * 1996 + '@one')
        self.assertEqual(len(self.rows()), 1)
        self.assertIn('exit_code: 17, reason: error', next(self.settings.log_dir.glob('*.log')).read_text())

    def test_archive_and_hourly_brake_count_archived_ai_not_system(self):
        self.setup_board({'one': self.custom('pass')}, chain_limit=5, hourly_limit=1)
        archived = self.mention('@one', 'archived')
        with self.board.write() as conn:
            self.board.error(conn, archived, 'not a model response')
        self.board.set_status('thread', archived, 'archived')
        self.mention('@one', 'allowed')
        self.manager.start()
        self.statuses('skipped', 'done')
        self.manager.shutdown()
        old = self.board.new('other', 'Old model reply', 'AI', 'main(test)', 'main')[0]
        self.board.set_status('thread', old, 'archived')
        self.mention('@one', 'rate limited')
        self.manager.start()
        self.statuses('skipped', 'done', 'skipped')
        self.assertIn('hourly', self.rows()[-1]['detail'])

    def test_chain_brake_counts_ai_from_start_without_human(self):
        self.setup_board({'one': self.custom('pass')}, chain_limit=2)
        tid = self.board.new('general', 'topic', 'first', 'main(test)', 'main')[0]
        self.board.reply(tid, 'second', 'main(test)', 'main')
        with self.board.write() as conn:
            conn.execute("INSERT INTO job_queue(agent_handle, thread_id, trigger_post_no, created_at) "
                         "VALUES ('one', ?, 2, 'unused')", (tid,))
        self.manager.start()
        self.statuses('skipped')
        self.assertIn('chain', self.rows()[0]['detail'])

    @unittest.skipUnless(sys.platform == 'linux', 'recovery uses /proc')
    def test_recovery_leaves_unrelated_pid_alive_and_cleans_owned_group(self):
        self.setup_board({'one': self.custom('pass')})
        self.mention('@one')
        self.mention('@one', 'another')
        env = os.environ | dict(AIBOARD_AGENT='one', AIBOARD_JOB_ID='1',
                                AIBOARD_DB=str(self.settings.db_path))
        owned = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'],
                                 env=env, start_new_session=True)
        other = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'],
                                 env=env, start_new_session=True)
        def cleanup(process):
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        self.addCleanup(cleanup, owned)
        self.addCleanup(cleanup, other)
        with self.board.write() as conn:
            conn.execute("UPDATE job_queue SET status='running', pid=? WHERE id=1", (owned.pid,))
        self.manager.start()
        self.statuses('interrupted', 'done')
        self.assertEqual(owned.wait(timeout=1), -signal.SIGTERM)
        self.manager.shutdown()
        with self.board.write() as conn:
            conn.execute("UPDATE job_queue SET status='running', pid=? WHERE id=2", (other.pid,))
        self.manager.start()
        self.statuses('interrupted', 'interrupted')
        self.assertIsNone(other.poll())

    def test_hermes_persists_own_generation_before_interrupt(self):
        self.setup_board({'one': {'profile': 'aiboard-one', 'model': 'test-model'}})
        script = self.root / 'hermes'
        script.write_text(f'#!{sys.executable}\n' + '''
import json, os, pathlib, sys, time
root = pathlib.Path(os.environ['AIBOARD_DATA_DIR'])
prompt = sys.stdin.read()
(root / 'launch').write_text(json.dumps([sys.argv, os.getcwd(), prompt]))
print('Session: local-not-the-real-id', flush=True)
print('Session: local-test', file=sys.stderr, flush=True)
while not (root / 'interrupt').exists(): time.sleep(.02)
print('interrupted by gateway', file=sys.stderr)
raise SystemExit(3)
''')
        rpc = self.root / 'rpc'
        rpc.write_text(f'#!{sys.executable}\n' + '''
import hashlib, json, os, pathlib, sys
root = pathlib.Path(os.environ['AIBOARD_DATA_DIR'])
profile, operation, sid, *rest = sys.argv[1:]
assert profile == 'aiboard-one' and sid == 'local-test'
if operation == 'inspect':
    prompt = json.loads((root / 'launch').read_text())[2]
    own = (root / 'run-own').exists()
    running = not (root / 'interrupt').exists()
    print(json.dumps(dict(running=running, execution_generation=9 if own else 8,
                          prompt_sha256=hashlib.sha256((prompt if own else 'old turn').strip().encode()).hexdigest())))
else:
    assert rest == ['9']
    (root / 'interrupt').touch()
    print(json.dumps(dict(running=True, execution_generation=9)))
''')
        script.chmod(0o700)
        rpc.chmod(0o700)
        with patch.dict(os.environ, PATH=f'{self.root}:{os.environ["PATH"]}', AIBOARD_HERMES_RPC=str(rpc)):
            work = self.root / 'work' / 'one'
            target = self.root / 'project'
            target.mkdir()
            self.mention(f'@one({target}) first')
            self.manager.start()
            self.await_(lambda: (self.rows()[0]['session_id'] or '') == 'local-test')
            self.assertIsNone(self.rows()[0]['execution_generation'])
            (self.root / 'run-own').touch()
            self.await_(lambda: self.rows()[0]['execution_generation'] == 9)
            args, cwd, prompt = json.loads((self.root / 'launch').read_text())
            self.assertEqual(cwd, str(work))
            self.assertEqual(args[args.index('--in') + 1], str(work))
            self.assertIn(f'対象ディレクトリ: {target}', prompt)
            self.assertIn(f'aiboard --db {self.settings.db_path} --config {self.settings.config_path}', prompt)
            self.manager.stop('one')
            self.statuses('cancelled')
            self.assertTrue((self.root / 'interrupt').exists())
            with self.board.read() as conn:
                self.assertEqual(conn.execute('SELECT session_id FROM agent_sessions').fetchone()[0], 'local-test')
                self.assertEqual(conn.execute('SELECT COUNT(*) FROM posts').fetchone()[0], 1)

    def test_startup_interrupts_only_complete_hermes_job_identity(self):
        self.setup_board({'one': {'profile': 'aiboard-one', 'model': 'test'},
                          'two': {'profile': 'aiboard-two', 'model': 'test'}})
        self.mention('@one @two')
        with self.board.write() as conn:
            conn.execute("UPDATE job_queue SET status='running', session_id='local-test'")
            conn.execute("UPDATE job_queue SET execution_generation=7 WHERE agent_handle='one'")
        with patch('gateway_rpc.call', return_value={'running': False, 'execution_generation': 7}) as call:
            self.manager.start()
            self.statuses('interrupted', 'interrupted')
        call.assert_called_once_with('aiboard-one', 'interrupt', 'local-test', 7)

    def test_exclusive_owner_and_shutdown_do_not_consume_queued_work(self):
        from worker import WorkerManager
        self.setup_board({'one': self.custom('import time; time.sleep(30)')})
        self.mention('@one')
        self.mention('@one', 'next')
        self.manager.start()
        self.await_(lambda: self.rows()[0]['pid'])
        second = WorkerManager(self.board, self.settings)
        self.addCleanup(second.shutdown)
        with self.assertRaises(BoardError) as ctx:
            second.start()
        self.assertEqual(ctx.exception.status, 409)
        self.manager.shutdown()
        self.statuses('interrupted', 'queued')
        with self.board.read() as conn:
            self.assertEqual(conn.execute('SELECT COUNT(*) FROM posts').fetchone()[0], 2)
