import io
from unittest import TestCase

from aiboard import body_from, parser
from config import ConfigError


class Terminal(io.StringIO):
    def isatty(self):
        return True

    def read(self, *args):
        raise AssertionError('stdin should not be read')


class CLITests(TestCase):
    def test_positional_body_has_priority(self):
        self.assertEqual(body_from('本文', Terminal()), '本文')

    def test_omitted_body_on_tty_fails_immediately(self):
        with self.assertRaises(ConfigError):
            body_from(None, Terminal())

    def test_stdin_input_and_whitespace_validation(self):
        self.assertEqual(body_from(None, io.StringIO('本文\n')), '本文\n')
        self.assertEqual(body_from('-', io.StringIO('本文\n')), '本文\n')
        with self.assertRaises(ConfigError):
            body_from(None, io.StringIO('　\n'))

    def test_global_paths_work_before_or_after_subcommand(self):
        args = parser().parse_args(['--db', '/tmp/first', 'reply', '--config', '/tmp/agent.json', '1', '本文'])
        self.assertEqual((args.db, args.config, args.thread_id), ('/tmp/first', '/tmp/agent.json', 1))

    def test_body_after_forum_flag(self):
        args = parser().parse_args(['new', '題', '-f', '板', '本文'])
        self.assertEqual((args.forum, args.title, args.body), ('板', '題', '本文'))
