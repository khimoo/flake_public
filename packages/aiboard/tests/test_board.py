import sqlite3
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from board import Board, BoardError, mentions, now


class SchemaTests(unittest.TestCase):
    def test_concurrent_initialization_and_connection_pragmas(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'data' / 'aiboard.db'
            with ThreadPoolExecutor(max_workers=6) as pool:
                boards = list(pool.map(lambda _: Board(path, {}), range(12)))
            for method in (boards[0].read, boards[-1].write):
                with method() as conn:
                    self.assertEqual(conn.execute('PRAGMA user_version').fetchone()[0], 1)
                    self.assertEqual(conn.execute('PRAGMA journal_mode').fetchone()[0], 'wal')
                    self.assertEqual(conn.execute('PRAGMA foreign_keys').fetchone()[0], 1)
                    self.assertEqual(conn.execute('PRAGMA busy_timeout').fetchone()[0], 30000)
                    self.assertIsInstance(conn.execute('SELECT 1').fetchone(), sqlite3.Row)
                    columns = {r['name'] for r in conn.execute('PRAGMA table_info(job_queue)')}
                    self.assertTrue({'session_id', 'execution_generation'} <= columns)
            with boards[0].write() as conn:
                self.assertTrue(conn.in_transaction)
                with self.assertRaises(sqlite3.IntegrityError):
                    conn.execute("INSERT INTO threads(forum_id,title,created_at,updated_at) VALUES(99,'x',?,?)", (now(), now()))

    def test_preexisting_incompatible_database_is_not_modified(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'aiboard.db'
            path.touch()
            with self.assertRaisesRegex(BoardError, 'user_version'):
                Board(path, {})
            self.assertEqual(path.read_bytes(), b'')
            with sqlite3.connect(path) as conn:
                conn.executescript('CREATE TABLE keep (data); INSERT INTO keep VALUES (42); PRAGMA user_version=7;')
            conn.close()
            original = path.read_bytes()
            with self.assertRaisesRegex(BoardError, 'user_version'):
                Board(path, {})
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(list(Path(root).iterdir()), [path])

    def test_incompatible_wal_database_without_sidecars_stays_untouched(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'wal.db'
            conn = sqlite3.connect(path)
            conn.execute('PRAGMA journal_mode=WAL').fetchone()
            conn.execute('PRAGMA user_version=2')
            conn.close()
            original = path.read_bytes()
            with self.assertRaisesRegex(BoardError, 'user_version 2'):
                Board(path, {})
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(list(path.parent.iterdir()), [path])

    def test_version_check_reads_uncheckpointed_wal_version(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'wal.db'
            Board(path, {})
            conn = sqlite3.connect(path)
            try:
                conn.execute('PRAGMA wal_autocheckpoint=0')
                conn.execute('PRAGMA user_version=3')
                with self.assertRaisesRegex(BoardError, 'user_version 3'):
                    Board(path, {})
            finally:
                conn.close()


class BoardTests(unittest.TestCase):
    def setUp(self):
        root = tempfile.TemporaryDirectory()
        self.addCleanup(root.cleanup)
        self.root = Path(root.name)
        self.board = Board(self.root / 'aiboard.db', {'sol': {}, 'opus': {}, 'other': {}})

    def rows(self, statement, *params):
        with self.board.read() as conn:
            return [dict(row) for row in conn.execute(statement, params)]

    def test_names_normalize_before_validation_and_auto_create(self):
        forum_id = self.board.create_forum(' 　設計\t 議論\n')
        tid, first = self.board.new('設計　議論', '  a\n\t b  ', '  body\n', 'user', 'human')
        self.assertEqual(first, 1)
        thread = self.rows('SELECT forum_id,title FROM threads WHERE id=?', tid)[0]
        self.assertEqual(thread, {'forum_id': forum_id, 'title': 'a b'})
        self.assertEqual(self.rows('SELECT name FROM forums'), [{'name': '設計 議論'}])
        self.assertEqual(self.rows('SELECT body FROM posts'), [{'body': '  body\n'}])
        self.assertEqual(self.board.new('新' * 40, '題' * 100, 'text', 'user', 'human')[1], 1)
        for forum, title, body in [('　\t', 'ok', 'body'), ('a' * 41, 'ok', 'body'),
                                   ('general', '　', 'body'), ('general', 'a' * 101, 'body'),
                                   ('general', 'ok', '　\n')]:
            with self.subTest(forum=forum, title=title, body=body), self.assertRaises(BoardError):
                self.board.new(forum, title, body, 'user', 'human')
        self.assertEqual(len(self.rows('SELECT id FROM forums')), 2)

    def test_archive_rejects_user_posts_and_moves_but_allows_system_errors(self):
        src = self.board.create_forum('src')
        dest = self.board.create_forum('destination')
        tid, _ = self.board.new('src', 'topic', 'body', 'user', 'human')
        self.board.set_status('forum', dest, 'archived')
        with self.assertRaisesRegex(BoardError, 'archived'):
            self.board.new('destination', 'topic', 'body', 'user', 'human')
        with self.assertRaisesRegex(BoardError, 'archived'):
            self.board.move(tid, dest)
        self.board.set_status('forum', src, 'archived')
        with self.assertRaisesRegex(BoardError, 'archived'):
            self.board.reply(tid, 'no', 'user', 'human')
        self.board.set_status('forum', dest, 'open')
        self.board.move(tid, dest)
        self.board.set_status('thread', tid, 'archived')
        with self.assertRaisesRegex(BoardError, 'archived'):
            self.board.reply(tid, 'still no', 'user', 'human')
        self.board.set_status('forum', dest, 'archived')
        with self.board.write() as conn:
            self.assertEqual(self.board.error(conn, tid, '[ERROR] @sol', '/tmp', 123), 2)
        self.assertEqual(self.rows('SELECT author_handle,author_type,status,cwd,duration_ms FROM posts WHERE post_no=2'),
                         [{'author_handle': 'system', 'author_type': 'system', 'status': 'error',
                           'cwd': '/tmp', 'duration_ms': 123}])
        self.assertEqual(self.rows('SELECT id FROM job_queue'), [])

    def test_concurrent_replies_allocate_contiguous_post_numbers(self):
        tid, _ = self.board.new('general', 'topic', 'first', 'main(x)', 'main')
        with ThreadPoolExecutor(max_workers=8) as pool:
            numbers = list(pool.map(lambda i: self.board.reply(tid, str(i), 'main(x)', 'main'), range(24)))
        self.assertEqual(sorted(numbers), list(range(2, 26)))

    def test_errors_inside_a_write_roll_back(self):
        with self.assertRaises(RuntimeError), self.board.write() as conn:
            conn.execute("INSERT INTO forums(name,created_at,updated_at) VALUES ('test',?,?)", (now(), now()))
            raise RuntimeError('abort')
        self.assertEqual(self.rows('SELECT name FROM forums'), [])

    def test_mention_tokens_keep_positions_and_ignore_markdown_code(self):
        text = ('user@sol @@sol @opus(/tmp/a) x>>2 >>>2 >>3(~/src)\n'
                '`` @sol ` >>1 `` @other\n'
                '```python\n@sol >>4\n```\n~~~\n@sol\n~~~\n>>12')
        self.assertEqual([(text[a:b], kind, value, cwd) for a, b, kind, value, cwd in mentions(text)],
                         [('@opus(/tmp/a)', 'handle', 'opus', '/tmp/a'),
                          ('>>3(~/src)', 'anchor', 3, '~/src'),
                          ('@other', 'handle', 'other', ''),
                          ('>>12', 'anchor', 12, '')])

    def test_mentions_enqueue_once_per_recipient_per_post_in_first_reference_order(self):
        tid, _ = self.board.new('general', 'topic', 'hi', 'user', 'human')
        self.board.reply(tid, 'from opus', 'opus', 'agent')
        self.board.reply(tid, 'from main', 'main(sol)', 'main')
        with self.board.write() as conn:
            self.board.error(conn, tid, '@sol')
        first = self.board.reply(tid, '>>2 @sol @opus(~/missing) @sol(/first/../chosen) '
                                      '>>2(/ignored) @sol(/ignored) >>1 >>3 >>4 >>999 @unknown', 'user', 'human')
        second = self.board.reply(tid, '@opus', 'user', 'human')
        self.assertEqual(self.rows('SELECT agent_handle,trigger_post_no,requested_cwd,status FROM job_queue ORDER BY id'),
                         [{'agent_handle': 'opus', 'trigger_post_no': first,
                           'requested_cwd': str(Path.home() / 'missing'), 'status': 'queued'},
                          {'agent_handle': 'sol', 'trigger_post_no': first,
                           'requested_cwd': '/chosen', 'status': 'queued'},
                          {'agent_handle': 'opus', 'trigger_post_no': second,
                           'requested_cwd': '', 'status': 'queued'}])

    def test_reply_reports_wake_eligibility_from_running_job_not_presence_of_mentions(self):
        focus, _ = self.board.new('general', 'focus', '@sol', 'user', 'human')
        off, _ = self.board.new('general', 'off', '@opus', 'main(x)', 'main')
        self.assertEqual(self.board.reply(focus, '@opus', 'sol', 'agent', report_policy=True), (2, False))
        with self.board.write() as conn:
            conn.execute("UPDATE job_queue SET status='running' WHERE agent_handle='sol'")
        self.assertEqual(self.board.reply(focus, 'plain text', 'sol', 'agent', report_policy=True), (3, True))
        self.assertEqual(self.board.reply(off, '@opus', 'sol', 'agent', report_policy=True), (2, False))
        self.assertEqual(self.board.reply(focus, '@opus', 'main(x)', 'main', report_policy=True), (4, False))
        self.board.new('general', 'side topic', '@opus', 'sol', 'agent')
        self.assertEqual(self.board.reply(focus, '@sol >>3 @opus', 'sol', 'agent'), 5)
        self.assertEqual(self.rows('SELECT agent_handle,thread_id,trigger_post_no FROM job_queue ORDER BY id'),
                         [{'agent_handle': 'sol', 'thread_id': focus, 'trigger_post_no': 1},
                          {'agent_handle': 'opus', 'thread_id': focus, 'trigger_post_no': 5}])

    def test_failed_queue_insert_rolls_back_post_read_state_and_other_jobs(self):
        tid, _ = self.board.new('general', 'topic', 'first', 'user', 'human')
        with self.board.write() as conn:
            conn.execute('''
                CREATE TRIGGER reject_opus BEFORE INSERT ON job_queue WHEN NEW.agent_handle='opus'
                BEGIN SELECT RAISE(ABORT, 'test queue failure'); END
            ''')
        with self.assertRaisesRegex(sqlite3.IntegrityError, 'test queue failure'):
            self.board.reply(tid, '@sol @opus', 'user', 'human')
        self.assertEqual(self.rows('SELECT post_no FROM posts'), [{'post_no': 1}])
        self.assertEqual(self.rows('SELECT last_read_post_no FROM read_state'), [{'last_read_post_no': 1}])
        self.assertEqual(self.rows('SELECT id FROM job_queue'), [])

    def test_show_only_marks_for_explicit_valid_reader_with_posts(self):
        tid, _ = self.board.new('general', 'topic', 'hi', 'main(x)', 'main')
        self.assertEqual(self.board.threads(reader='user')[0]['read_label'], '[未閲覧]')
        self.assertEqual(self.board.forums(reader='user')[0]['unread'], 1)
        self.assertEqual(self.board.show(tid, reader='user')[1][0]['post_no'], 1)
        self.assertEqual(self.board.show(tid, since=1, reader='user', mark=True)[1], [])
        self.board.show(tid, reader='main(x)', mark=True)
        self.assertEqual(self.rows('SELECT reader_handle FROM read_state'), [])
        self.assertEqual(self.board.show(tid, reader='user', mark=True)[0]['unread'], 0)
        self.assertEqual(self.board.threads(reader='user')[0]['read_label'], '[既読]')
        self.board.reply(tid, 'new content', 'sol', 'agent')
        self.assertEqual(self.board.threads(reader='user')[0]['read_label'], '[未読 1件]')
        self.assertEqual(self.board.threads(reader='sol')[0]['unread'], 0)
        with self.board.read() as conn:
            self.assertEqual(self.board.last_read(conn, 'user', tid), 1)
            self.assertEqual(self.board.last_read(conn, 'sol', tid), 2)
        self.board.reply(tid, 'read it', 'user', 'human')
        self.assertEqual(self.board.threads(reader='user')[0]['unread'], 0)

    def test_archived_threads_and_forums_do_not_count_as_unread(self):
        group = self.board.create_forum('general')
        tid, _ = self.board.new('general', 'archived thread', 'text', 'sol', 'agent')
        second, _ = self.board.new('general', 'open thread', 'text', 'sol', 'agent')
        self.board.set_status('thread', tid, 'archived')
        self.assertEqual([row['id'] for row in self.board.threads('　general　', reader='user')], [second])
        self.assertEqual(self.board.forums(archived=True, reader='user')[0]['unread'], 1)
        self.board.set_status('forum', group, 'archived')
        self.assertEqual(self.board.forums(), [])
        self.assertEqual(self.board.threads(), [])
        self.assertEqual(self.board.forums(archived=True, reader='user')[0]['unread'], 0)
        self.assertEqual({row['id']: row['unread'] for row in self.board.threads(archived=True, reader='user')},
                         {tid: 0, second: 0})

    def test_search_supports_unicode_and_literal_substrings_without_marking(self):
        tid, _ = self.board.new('general', 'Straße only-title', 'one 100%', 'user', 'human')
        self.board.reply(tid, 'two with _x', 'sol', 'agent')
        other, _ = self.board.new('separate', 'different', 'two 100x', 'user', 'human')
        self.board.set_status('thread', tid, 'archived')

        def ids(*args, **kwargs):
            return [row['id'] for row in self.board.search(*args, **kwargs)]

        self.assertEqual(ids('STRASSE 100% _x'), [tid])
        self.assertEqual(set(ids(['only-title', '100x'], any_word=True)), {tid, other})
        self.assertEqual(ids(['two'], forum=' general '), [tid])
        self.assertEqual(ids('only-title', author='sol'), [])
        self.assertEqual(ids('100%', author='sol'), [])
        self.assertEqual(ids('two', author='sol'), [tid])
        self.assertEqual(self.board.search('only-title')[0]['matches'], [])
        hit = self.board.search('two', author='sol')[0]['matches']
        self.assertEqual([(p['post_no'], p['author_handle']) for p in hit], [(2, 'sol')])
        self.assertEqual(len(ids('two', limit=1)), 1)
        self.assertEqual(self.rows('SELECT reader_handle FROM read_state ORDER BY reader_handle'),
                         [{'reader_handle': 'sol'}, {'reader_handle': 'user'}, {'reader_handle': 'user'}])

    def test_reset_rejects_running_then_clears_only_session_and_read_state(self):
        tid, _ = self.board.new('general', 'topic', '@sol @opus', 'user', 'human')
        self.board.reply(tid, '@sol', 'user', 'human')
        self.board.show(tid, reader='sol', mark=True)
        stamp = now()
        with self.board.write() as conn:
            conn.execute('INSERT INTO agent_sessions VALUES (?,?,?)', ('sol', 'session', stamp))
            conn.execute("UPDATE job_queue SET status='running', started_at=? WHERE id=1", (stamp,))
        work = self.root / 'work' / 'sol'
        work.mkdir(parents=True)
        with self.assertRaises(BoardError) as error:
            self.board.reset('sol')
        self.assertEqual(error.exception.status, 409)
        self.assertEqual(self.board.status()[0], {'handle': 'sol', 'thread_id': tid,
                                                 'started_at': stamp, 'queued': 1, 'running': True})
        self.assertEqual(self.board.threads()[0]['running'], 1)
        with self.board.write() as conn:
            conn.execute("UPDATE job_queue SET status='interrupted' WHERE id=1")
        self.board.reset('sol')
        self.assertTrue(work.is_dir())
        self.assertEqual(self.rows('SELECT * FROM agent_sessions'), [])
        self.assertEqual(self.rows('SELECT reader_handle FROM read_state'), [{'reader_handle': 'user'}])
        self.assertEqual(self.board.status()[0], {'handle': 'sol', 'thread_id': None,
                                                 'started_at': None, 'queued': 1, 'running': False})
