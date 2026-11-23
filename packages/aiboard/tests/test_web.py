import http.client
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from dataclasses import dataclass
from pathlib import Path
from unittest.mock import patch

from board import Board
from config import Settings


@dataclass
class LiveHTTP:
    server: object
    bind: str = '127.0.0.1'

    def request(self, method, path, payload=None, headers=None):
        conn = http.client.HTTPConnection(self.bind, self.server.server_port, timeout=5)
        try:
            options = {'Host': self.host}
            options.update(headers or {})
            if payload is not None and not isinstance(payload, bytes):
                options.setdefault('Content-Type', 'application/json')
                payload = json.dumps(payload).encode()
            conn.request(method, path, body=payload, headers=options)
            response = conn.getresponse()
            return response.status, dict(response.getheaders()), response.read()
        finally:
            conn.close()

    @property
    def host(self):
        name = '[::1]' if self.bind == '::1' else self.bind
        return f'{name}:{self.server.server_port}'

    def post(self, path, payload):
        status, _, body = self.request('POST', path, payload, {'Origin': f'http://{self.host}'})
        return status, json.loads(body)


class WebCase(unittest.TestCase):
    def start_http(self, bind='127.0.0.1'):
        from web import make_server

        server = make_server(bind, 0, self.board, self.workers)
        self.addCleanup(server.server_close)
        thread = threading.Thread(target=server.serve_forever, kwargs={'poll_interval': 0.01})
        thread.start()
        self.addCleanup(thread.join, 5)
        self.addCleanup(server.shutdown)
        return LiveHTTP(server, bind)


class CSRFTests(WebCase):
    def test_csrf_accepts_forwarded_ports_and_referer_fallback(self):
        class ForumStore:
            def __init__(self):
                self.names = []

            def create_forum(self, name):
                self.names.append(name)
                return len(self.names)

        self.board, self.workers = ForumStore(), None
        http = self.start_http()
        for host, source in [
            ('localhost:31337', {'Origin': 'http://localhost:31337'}),
            ('127.0.0.1:48321', {'Referer': 'http://127.0.0.1:48321/?forum=1'}),
            ('[::1]:48321', {'Origin': 'http://[::1]:48321'}),
        ]:
            with self.subTest(host=host):
                self.assertEqual(http.request('POST', '/api/forums', {'name': host},
                                              {'Host': host, **source})[0], 201)
        self.assertEqual(self.board.names, ['localhost:31337', '127.0.0.1:48321', '[::1]:48321'])

    def test_csrf_rejects_missing_or_different_source_before_mutating(self):
        self.board, self.workers = None, None
        http = self.start_http()
        for headers in [
            {}, {'Origin': ''}, {'Origin': 'null'},
            {'Origin': 'http://localhost:10001', 'Host': 'localhost:10002'},
            {'Origin': 'http://localhost:10002', 'Host': '127.0.0.1:10002'},
            {'Origin': 'http://outside.invalid', 'Host': 'outside.invalid'},
            {'Origin': 'http://outside.invalid', 'Referer': f'http://{http.host}/'},
        ]:
            with self.subTest(headers=headers):
                self.assertEqual(http.request('POST', '/api/forums', {'name': 'test'}, headers)[0], 403)

    def test_ipv6_listener(self):
        self.board, self.workers = None, None
        try:
            http = self.start_http('::1')
        except OSError as exc:
            self.skipTest(f'IPv6 loopback unavailable: {exc}')
        self.assertEqual(http.request('POST', '/api/unregistered', {},
                                      {'Origin': f'http://{http.host}'})[0], 404)


class BoardWebTests(WebCase):
    def setUp(self):
        tmp = self.enterContext(tempfile.TemporaryDirectory())
        self.board = Board(Path(tmp) / 'test.db', {'sol': {'label': 'Sol'}})
        self.workers = None
        self.http = self.start_http()

    def read_position(self, tid):
        with self.board.read() as conn:
            row = conn.execute('SELECT last_read_post_no FROM read_state WHERE reader_handle = ? '
                               'AND thread_id = ?', ('user', tid)).fetchone()
        return row[0] if row else 0

    def test_board_home_and_assets(self):
        status, _, body = self.http.request('GET', '/')
        self.assertEqual(status, 200)
        self.assertIn(b'/static/board.js', body)
        self.assertIn(b'/static/board.css', body)
        for url, content_type in [('/static/board.js', 'text/javascript'),
                                  ('/static/board.css', 'text/css'),
                                  ('/static/board.svg', 'image/svg+xml')]:
            status, headers, body = self.http.request('GET', url)
            self.assertEqual(status, 200)
            self.assertIn(content_type, headers['Content-Type'])
            self.assertTrue(body)

    def test_open_reply_and_read_only_incremental_poll(self):
        tid, _ = self.board.new('General', 'Topic', 'First', 'sol', 'agent')
        view = f'forum=1&thread={tid}'
        self.assertEqual(self.http.request('GET', f'/?{view}')[0], 200)
        self.assertEqual(self.read_position(tid), 0)
        status, opened = self.http.post(f'/api/open?{view}', {})
        self.assertEqual(status, 200)
        self.assertIn('First', opened['posts'])
        self.assertEqual(self.read_position(tid), 1)
        self.board.reply(tid, 'New arrival', 'sol', 'agent')
        status, _, body = self.http.request('GET', f'/api/poll?{view}&since=1')
        self.assertEqual(status, 200)
        sync = json.loads(body)
        self.assertIn('New arrival', sync['posts'])
        self.assertNotIn('First', sync['posts'])
        self.assertEqual(sync['last_post_no'], 2)
        self.assertEqual(self.read_position(tid), 1)
        status, reply = self.http.post(f'/api/threads/{tid}/reply', {
            'body': '@sol Thanks', 'author_handle': 'sol', 'author_type': 'agent',
        })
        self.assertEqual(status, 201)
        self.assertEqual(reply['post_no'], 3)
        self.assertEqual(self.read_position(tid), 3)
        _, posts = self.board.show(tid)
        self.assertEqual((posts[-1]['author_handle'], posts[-1]['author_type']), ('user', 'human'))
        with self.board.read() as conn:
            jobs = conn.execute('SELECT agent_handle, trigger_post_no FROM job_queue').fetchall()
        self.assertEqual([tuple(job) for job in jobs], [('sol', 3)])

    def test_archive_visibility_and_search_remain_independent(self):
        _, forum = self.http.post('/api/forums', {'name': '  Archived　forum  '})
        fid = forum['forum_id']
        status, result = self.http.post('/api/threads', {
            'forum_id': fid, 'title': 'Alpha topic', 'body': 'Beta', 'author_handle': 'sol',
        })
        self.assertEqual(status, 201)
        tid = result['thread_id']
        self.assertEqual(self.board.show(tid)[1][0]['author_handle'], 'user')
        self.assertEqual(self.http.post(f'/api/forums/{fid}/status', {'status': 'archived'})[0], 200)
        self.assertNotIn(b'Archived forum</a>', self.http.request('GET', f'/?forum={fid}')[2])
        self.assertIn(b'Archived forum</a>', self.http.request('GET', '/?archived=1')[2])
        status, _, body = self.http.request('GET', '/api/poll?q=Alpha+absent')
        self.assertEqual(status, 200)
        self.assertNotIn('Alpha topic</a>', json.loads(body)['threads'])
        self.assertIn(b'Alpha topic</a>', self.http.request('GET', '/?q=Alpha+absent&or=1')[2])
        self.assertIn(b'Alpha topic</a>', self.http.request('GET', '/?q=Alpha+Beta')[2])
        self.assertEqual(self.http.post(f'/api/threads/{tid}/reply', {'body': 'blocked'})[0], 409)
        self.assertEqual(self.http.post(f'/api/forums/{fid}/status', {'status': 'open'})[0], 200)
        self.assertEqual(self.http.post(f'/api/threads/{tid}/reply', {'body': 'restored'})[0], 201)

    def test_thread_archive_and_move_only_to_an_open_forum(self):
        tid, _ = self.board.new('General', 'Topic', 'First', 'sol', 'agent')
        fid = self.board.create_forum('Destination')
        self.board.set_status('forum', fid, 'archived')
        self.assertEqual(self.http.post(f'/api/threads/{tid}/move', {'forum_id': fid})[0], 409)
        self.assertEqual(self.http.post(f'/api/threads/{tid}/status', {'status': 'archived'})[0], 200)
        self.assertEqual(self.http.post(f'/api/threads/{tid}/reply', {'body': 'blocked'})[0], 409)
        self.board.set_status('forum', fid, 'open')
        self.assertEqual(self.http.post(f'/api/threads/{tid}/move', {'forum_id': fid})[0], 200)
        self.assertEqual(self.board.show(tid)[0]['forum_id'], fid)
        self.assertEqual(self.http.post(f'/api/threads/{tid}/status', {'status': 'open'})[0], 200)
        self.assertEqual(self.http.post(f'/api/threads/{tid}/reply', {'body': 'restored'})[0], 201)

    def test_post_rendering_escapes_data_and_decorates_references(self):
        tid, _ = self.board.new('Forum <tag>', 'Topic <tag>', 'First', 'sol', 'agent')
        self.board.reply(tid, '@sol >>1 `<tag> @sol`', 'sol', 'agent', cwd='/tmp/<tag>')
        with self.board.write() as conn:
            self.board.error(conn, tid, '<tag> failure')
        status, _, body = self.http.request('GET', f'/?thread={tid}')
        self.assertEqual(status, 200)
        self.assertNotIn(b'<tag>', body)
        self.assertIn(b'Topic &lt;tag&gt;', body)
        self.assertIn(b'<strong class="mention">@sol</strong> <a href="#post-1">&gt;&gt;1</a>', body)
        self.assertIn(b'`&lt;tag&gt; @sol`', body)
        self.assertIn(b'/tmp/&lt;tag&gt;', body)
        self.assertIn(b'[ERROR]', body)

    def test_open_without_csrf_and_get_mutations_leave_state_unchanged(self):
        tid, _ = self.board.new('General', 'Topic', 'First', 'sol', 'agent')
        self.assertEqual(self.http.request('POST', f'/api/open?thread={tid}', {})[0], 403)
        self.assertEqual(self.http.request('GET', f'/api/open?thread={tid}')[0], 404)
        self.assertEqual(self.http.request('GET', f'/api/threads/{tid}/status?status=archived')[0], 404)
        self.assertEqual(self.read_position(tid), 0)
        self.assertEqual(self.board.show(tid)[0]['status'], 'open')


class WorkerWebTests(WebCase):
    def test_stop_and_session_reset_use_real_worker_state(self):
        from worker import WorkerManager

        tmp = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.enterContext(patch.dict(os.environ, {
            'AIBOARD_DATA_DIR': str(tmp), 'AIBOARD_LOG_DIR': str(tmp / 'logs'),
            'HERMES_HOME': str(tmp / 'hermes'),
        }))
        config = tmp / 'agents.json'
        config.write_text(json.dumps({'agents': {'sol': {'kind': 'custom', 'command': [
            sys.executable, '-c', 'import sys, time; sys.stdin.read(); time.sleep(30)',
        ]}}}))
        settings = Settings.load(db=tmp / 'test.db', config=config)
        self.board = Board(settings.db_path, settings.agents)
        self.workers = WorkerManager(self.board, settings, poll_interval=.01, grace_period=.25)
        self.addCleanup(self.workers.shutdown)
        http = self.start_http()
        tid, _ = self.board.new('General', 'Topic', 'Seed', 'sol', 'agent')
        self.board.reply(tid, '@sol', 'user', 'human')
        self.workers.start()
        deadline = time.monotonic() + 5
        while not self.board.status()[0]['running']:
            self.assertLess(time.monotonic(), deadline, 'custom worker never entered running state')
            time.sleep(.01)
        self.assertEqual(http.post('/api/agents/sol/reset', {})[0], 409)
        self.assertEqual(http.post('/api/agents/sol/stop', {})[0], 200)
        self.assertEqual(http.post('/api/agents/sol/reset', {})[0], 200)
        self.assertEqual(http.post('/api/agents/sol/stop', {})[0], 409)
        self.assertEqual(http.post('/api/agents/unknown/reset', {})[0], 404)
        with self.board.read() as conn:
            self.assertEqual(conn.execute('SELECT status FROM job_queue').fetchone()[0], 'cancelled')
            self.assertIsNone(conn.execute("SELECT 1 FROM read_state WHERE reader_handle = 'sol'").fetchone())
            self.assertEqual(conn.execute('SELECT COUNT(*) FROM posts').fetchone()[0], 2)
