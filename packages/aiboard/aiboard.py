#!/usr/bin/env python3
"""Command-line interface and daemon entry point for aiboard."""
import argparse
import os
import signal
import sqlite3
import sys

from config import ConfigError, Settings, identity

AUTONOMOUS = '（自律書き込みのため自動起動は行われません）'


def positive(value):
    if not value.isascii() or not value.isdecimal() or not 0 < int(value) <= 2**63 - 1:
        raise argparse.ArgumentTypeError('正の整数を指定してください')
    return int(value)


def nonnegative(value):
    return 0 if value == '0' else positive(value)


class ArgumentParser(argparse.ArgumentParser):
    def parse_args(self, args=None, namespace=None):
        parsed, tail = self.parse_known_args(args, namespace)
        # argparse otherwise leaves the optional body unconsumed after a flag between title and body.
        if len(tail) == 1 and getattr(parsed, 'command', '') in ('new', 'reply') and parsed.body is None:
            if tail[0] == '-' or not tail[0].startswith('-'):
                parsed.body = tail.pop()
        if tail:
            self.error('認識できない引数: ' + ' '.join(tail))
        return parsed


def parser():
    common = argparse.ArgumentParser(add_help=False, argument_default=argparse.SUPPRESS)
    common.add_argument('--db', metavar='PATH', help='SQLite DB')
    common.add_argument('--config', metavar='PATH', help='住人設定 JSON')
    root = ArgumentParser(prog='aiboard', description='ローカル AI 協業掲示板', parents=[common])
    commands = root.add_subparsers(dest='command', required=True)

    def add(name, help):
        return commands.add_parser(name, help=help, parents=[common])

    add('agents', '住人一覧')
    add('status', '住人ごとの稼働状況')
    forums = add('forums', 'フォーラム一覧')
    forums.add_argument('--archived', action='store_true')
    listing = add('list', 'スレッド一覧')
    listing.add_argument('--archived', action='store_true')
    listing.add_argument('-f', '--forum')
    show = add('show', 'スレッドのレスを表示')
    show.add_argument('thread_id', type=positive)
    show.add_argument('--since', type=nonnegative, default=0)
    search = add('search', 'アーカイブを含む過去ログ検索')
    search.add_argument('query', nargs='+')
    search.add_argument('--or', dest='any_word', action='store_true')
    search.add_argument('-f', '--forum')
    search.add_argument('--author')
    search.add_argument('--limit', type=positive, default=20)
    new = add('new', 'スレッドを作成')
    new.add_argument('title')
    new.add_argument('body', nargs='?')
    new.add_argument('-f', '--forum', required=True)
    reply = add('reply', 'スレッドに返信')
    reply.add_argument('thread_id', type=positive)
    reply.add_argument('body', nargs='?')
    server = add('serve', 'Web UI とキュー監視を起動')
    server.add_argument('--host', default='127.0.0.1')
    server.add_argument('--port', type=positive, default=15280)
    return root


def body_from(argument, stream):
    if argument is None or argument == '-':
        if argument is None and stream.isatty():
            raise ConfigError('本文を引数または標準入力で指定してください')
        argument = stream.read()
    if not argument.strip():
        raise ConfigError('本文は空にできません')
    return argument


def thread_line(row):
    label = (' ' + row['read_label']) if row.get('read_label') else ''
    archived = ' [archived]' if 'archived' in (row['status'], row.get('forum_status')) else ''
    print(f"[{row['id']}] [{row['forum_name']}] ({row['post_count']}) {row['title']}{label}{archived}  [{row['updated_at']}]")


def run_server(args, board, settings):
    from web import make_server
    from worker import WorkerManager

    if args.port > 65535:
        raise ConfigError('ポートは 1～65535 の範囲で指定してください')
    workers = WorkerManager(board, settings)
    with make_server(args.host, args.port, board, workers) as server:
        def stop(signum, frame):
            # The first signal jumps to cleanup. Do not interrupt process collection on a repeat.
            signal.signal(signal.SIGINT, signal.SIG_IGN)
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
            raise KeyboardInterrupt

        previous = {s: signal.signal(s, stop) for s in (signal.SIGINT, signal.SIGTERM)}
        try:
            workers.start()
            print(f'aiboard serve: {args.host}:{args.port}', flush=True)
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            try:
                workers.shutdown()
            finally:
                for signo, handler in previous.items():
                    signal.signal(signo, handler)


def run(args, board, settings, handle, author):
    reader = handle if author == 'agent' else None
    match args.command:
        case 'serve':
            run_server(args, board, settings)
        case 'forums':
            for row in board.forums(archived=args.archived):
                print(f"{row['name']}  ({row['status']})  {row['thread_count']} threads  last={row['updated_at']}")
        case 'list':
            for row in board.threads(forum=args.forum, archived=args.archived, reader=reader):
                thread_line(row)
        case 'search':
            for row in board.search(args.query, any_word=args.any_word, forum=args.forum, author=args.author, limit=args.limit):
                thread_line(row)
                for post in row.get('matches', []):
                    excerpt = ' '.join(post['body'].split())
                    excerpt = excerpt[:160] + ('…' if len(excerpt) > 160 else '')
                    print(f"  >>{post['post_no']} {post['author_handle']}: {excerpt}")
        case 'show':
            thread, posts = board.show(args.thread_id, since=args.since, reader=reader, mark=bool(reader))
            print(f"=== [{thread['id']}] [{thread['forum_name']}] {thread['title']} ===")
            for post in posts:
                you = ' ←あなた' if post['author_handle'] == handle else ''
                cwd = f" [cwd: {post['cwd']}]" if post['cwd'] else ''
                print(f"\n{post['post_no']} : {post['author_handle']}{you} [{post['created_at']}]{cwd}\n{post['body']}")
        case 'status':
            for row in board.status():
                active = f"running  thread=#{row['thread_id']}  since={row['started_at']}" if row['running'] else 'idle'
                print(f"@{row['handle']}  {active}  queued={row['queued']}")
        case 'new':
            tid, no = board.new(args.forum, args.title, body_from(args.body, sys.stdin), handle, author, os.getcwd())
            print(f'[{tid}] >>{no}\n{AUTONOMOUS}')
        case 'reply':
            no, wake = board.reply(args.thread_id, body_from(args.body, sys.stdin), handle, author, os.getcwd(), report_policy=True)
            print(f'[{args.thread_id}] >>{no}')
            if not wake:
                print(AUTONOMOUS)


def main(argv=None):
    from board import Board, BoardError

    args = parser().parse_args(argv)
    try:
        settings = Settings.load(getattr(args, 'db', None), getattr(args, 'config', None))
        if args.command == 'agents':
            for handle, agent in settings.agents.items():
                print(handle, agent.get('profile', '-'), agent.get('model', '-'), agent['label'], sep='\t')
            return 0
        handle, author = ('main(unknown)', 'main') if args.command == 'serve' else identity(settings)
        board = Board(settings.db_path, settings.agents)
        run(args, board, settings, handle, author)
        return 0
    except (ConfigError, BoardError, OSError, sqlite3.Error) as exc:
        print(f'aiboard: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
