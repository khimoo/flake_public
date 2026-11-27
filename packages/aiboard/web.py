"""Board HTTP adapter behind the tailnet gate. The caller owns the serve/shutdown lifecycle."""

import json
import logging
import re
import socket
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from string import Template
from urllib.parse import parse_qs, urlencode, urlsplit

from board import BoardError
import board as store


STATIC = Path(__file__).with_name('static')
ASSETS = {
    '/static/board.css': ('board.css', 'text/css; charset=utf-8'),
    '/static/board.js': ('board.js', 'text/javascript; charset=utf-8'),
    '/static/board.svg': ('board.svg', 'image/svg+xml'),
}
HOST = re.compile(r'([A-Za-z0-9.-]+)(?::[0-9]{1,5})?', re.ASCII)
MAX_BODY = 1024 * 1024
HUMAN = ('user', 'human')
ARCHIVED = 'archived'
LOGGER = logging.getLogger(__name__)


class Access:
    """Accept only requests that address the board by one of its names.

    The tailnet gate in front decides which devices may connect; this check keeps a
    rebound DNS name (or a page on this host aiming at 127.0.0.1) from reaching it.
    """

    def __init__(self, names):
        self.names = {name.lower() for name in names}

    def allows(self, headers):
        hosts = headers.get_all('Host', [])
        match = HOST.fullmatch(hosts[0]) if len(hosts) == 1 else None
        return bool(match and match.group(1).lower() in self.names)


def _same_origin(headers):
    hosts = headers.get_all('Host', [])
    origins = headers.get_all('Origin')
    source = origins if origins is not None else headers.get_all('Referer', [])
    if len(source) != 1 or re.search(r'[\x00-\x20\x7f\\]', source[0]):
        return False
    try:
        url = urlsplit(source[0])
        return (url.scheme in ('http', 'https') and url.netloc.lower() == hosts[0].lower()
                and (url.port is None or 0 < url.port <= 65535)
                and (origins is None or not (url.path or url.query or url.fragment)))
    except ValueError:
        return False


def _string(payload, key):
    value = payload.get(key)
    if not isinstance(value, str) or any(0xd800 <= ord(c) <= 0xdfff for c in value):
        raise BoardError(f'{key} に文字列を指定してください。')
    return value


def _integer(value, minimum=1):
    if isinstance(value, str) and re.fullmatch(r'[0-9]{1,19}', value):
        value = int(value)
    if type(value) is not int or not minimum <= value <= 2**63 - 1:
        raise BoardError('ID またはレス番号が正しくありません。')
    return value


def _url(forum=None, thread=None, archived=False, q='', any_word=False):
    params = {k: v for k, v in [('forum', forum), ('thread', thread), ('archived', int(archived)),
                               ('q', q), ('or', int(any_word))] if v}
    return '/?' + urlencode(params) if params else '/'


def _link(*args, **kwargs):
    return escape(_url(*args, **kwargs))


def _time(stamp):
    stamp = escape(stamp)
    return f'<time datetime="{stamp}">{stamp}</time>'


def _badge(text, cls=''):
    return f'<span class="badge {cls}">{escape(text)}</span>'


def _op(path, label, *, name='', value='', disabled=False):
    field = f'<input type="hidden" name="{name}" value="{value}">' if name else ''
    attr = ' disabled' if disabled else ''
    return f'<form method="post" data-api="{path}">{field}<button type="submit"{attr}>{label}</button></form>'


def _archive_form(kind, item):
    status, label = ('open', '復元') if item['status'] == ARCHIVED else (ARCHIVED, 'アーカイブ')
    return _op(f'/api/{kind}/{item["id"]}/status', label, name='status', value=status)


def _forum_list(forums, selected, archived):
    items = []
    for forum in forums:
        fid = forum['id']
        current = ' aria-current="page"' if fid == selected else ''
        badge = (_badge('アーカイブ') if forum['status'] == ARCHIVED else
                 _badge(f'未読 {forum["unread"] or 0}件', 'unread' if forum['unread'] else ''))
        items.append(f'<li><a href="{_link(forum=fid, archived=archived)}"{current}>'
                     f'{escape(forum["name"])}</a>{badge}{_archive_form("forums", forum)}</li>')
    return f'<ul class="stack">{"".join(items)}</ul>' if items else '<p>フォーラムはありません。</p>'


def _thread_list(threads, fid, tid, archived, q, any_word):
    items = []
    for thread in threads:
        id = thread['id']
        link = _link(thread['forum_id'], id, archived, q, any_word)
        current = ' aria-current="page"' if id == tid else ''
        archived_item = ARCHIVED in (thread['status'], thread['forum_status'])
        badge = _badge('アーカイブ') if archived_item else ''
        if thread.get('read_label') and not archived_item:
            badge += _badge(thread['read_label'], 'unread' if thread.get('unread') else '')
        if thread.get('running'):
            badge += _badge('稼働中', 'running')
        where = f'<small>{escape(thread["forum_name"])}</small>' if q else ''
        items.append(f'<li><a href="{link}"{current}>{escape(thread["title"])}</a>{where}{badge}</li>')
    if items:
        return f'<ul class="stack">{"".join(items)}</ul>'
    return ('<p>一致するスレッドはありません。</p>' if q else
            '<p>スレッドはありません。</p>' if fid else '<p>フォーラムを選んでください。</p>')


def _thread_header(thread, forums):
    if thread is None:
        return '<h2>スレッド</h2><p>一覧からスレッドを選んでください。</p>'
    archived = ARCHIVED in (thread['status'], thread['forum_status'])
    tid = thread['id']
    options = ''.join(f'<option value="{f["id"]}">{escape(f["name"])}</option>' for f in forums
                      if f['status'] == 'open' and f['id'] != thread['forum_id'])
    move = (f'<form method="post" data-api="/api/threads/{tid}/move"><label>移動先 '
            f'<select name="forum_id">{options}</select></label> <button>移動</button></form>') if options else ''
    return (f'<small>{escape(thread["forum_name"])}</small><h2>#{tid} {escape(thread["title"])}</h2>'
            + ('<p class="notice">アーカイブ済みのため返信できません。</p>' if archived else '')
            + f'<div class="actions">{_archive_form("threads", thread)}{move}</div>')


def _post_body(body, agents):
    output = []
    previous = 0
    for start, end, kind, value, _ in store.mentions(body):
        output.append(escape(body[previous:start]))
        token = escape(body[start:end])
        if kind == 'anchor':
            token = f'<a href="#post-{value}">{token}</a>'
        elif kind == 'handle' and value in agents:
            token = f'<strong class="mention">{token}</strong>'
        output.append(token)
        previous = end
    return ''.join(output) + escape(body[previous:])


def _posts(posts, agents):
    html = []
    for post in posts:
        n = post['post_no']
        cwd = f'<small>cwd: <code>{escape(post["cwd"])}</code></small>' if post['cwd'] else ''
        error = _badge('[ERROR]', 'error') if post['status'] == 'error' else ''
        html.append(f'<article id="post-{n}" class="post"><header><a href="#post-{n}">#{n}</a> '
                    f'<strong>{escape(post["author_handle"])}</strong> {error} {_time(post["created_at"])} '
                    f'{cwd}</header><div class="post-body">{_post_body(post["body"], agents)}</div></article>')
    return ''.join(html)


def _workers(status, agents):
    items = []
    for worker in status:
        handle = worker['handle']
        label = agents[handle].get('label') or handle
        running = worker['running']
        tid = worker['thread_id']
        stamp = worker['started_at']
        state = (_badge('稼働中', 'running') + f' <a href="{_link(thread=tid)}">#{tid}</a> '
                 + (_time(stamp) if stamp else '')) if running else _badge('休眠中')
        path = f'/api/agents/{escape(handle)}'
        actions = (_op(path + '/stop', '停止', disabled=not running)
                   + _op(path + '/reset', 'セッションリセット', disabled=running))
        items.append(f'<li><strong>@{escape(handle)}</strong> <small>{escape(label)}</small> {state}'
                     f' <small>待機 {worker["queued"]}件</small><div class="actions">{actions}</div></li>')
    return f'<ul class="stack">{"".join(items)}</ul>' if items else '<p>住人は登録されていません。</p>'


def _state(board, query, *, mark=False, full=False):
    try:
        args = {key: items[-1] for key, items in parse_qs(query, max_num_fields=30).items()}
    except ValueError as exc:
        raise BoardError('検索条件が多すぎます。') from exc
    selected = _integer(args['forum']) if 'forum' in args else None
    tid = _integer(args['thread']) if 'thread' in args else None
    since = 0 if full else _integer(args.get('since', '0'), 0)
    archived = args.get('archived') == '1'
    q = args.get('q', '').strip()
    any_word = args.get('or') == '1'
    if mark and tid is None:
        raise BoardError('スレッドを指定してください。')
    thread, posts = (board.show(tid, since=0 if mark else since, reader='user', mark=mark)
                     if tid is not None else (None, []))
    if thread:
        selected = thread['forum_id']
    if mark:
        # Mark the snapshot being opened, but send only posts the tab lacks.
        posts = [post for post in posts if post['post_no'] > since]
    forums = board.forums(archived=True, reader='user')
    forum = next((f for f in forums if f['id'] == selected), None)
    if selected is not None and forum is None:
        raise BoardError('フォーラムが見つかりません。', 404)
    visible = [f for f in forums if archived or f['status'] == 'open']
    if q:
        labels = {t['id']: t for t in board.threads(archived=True, reader='user')}
        threads = [{**t, **labels.get(t['id'], {})} for t in board.search(q.split(), any_word=any_word)]
    elif forum:
        threads = board.threads(forum=forum['name'], archived=archived, reader='user')
    else:
        threads = []
    show_target = not (archived and forum and forum['status'] == ARCHIVED)
    return {
        'forums': _forum_list(visible, selected, archived),
        'threads': _thread_list(threads, selected, tid, archived, q, any_word),
        'thread': _thread_header(thread, forums),
        'posts': _posts(posts, board.agents),
        'workers': _workers(board.status(), board.agents),
        'last_post_no': posts[-1]['post_no'] if posts else since,
        'forum_id': selected or '', 'thread_id': tid or '',
        'forum_title': forum['name'] if forum else 'フォーラム未選択',
        'new_allowed': bool(forum and forum['status'] == 'open'),
        'reply_allowed': bool(thread and ARCHIVED not in (thread['status'], thread['forum_status'])),
        'toggle_url': _url(selected if show_target else None, tid if show_target else None,
                           not archived, q, any_word),
        'toggle_label': 'アーカイブを隠す' if archived else 'アーカイブを表示',
        'query': escape(q), 'search_or': ' checked' if any_word else '',
        'archived_on': '1' if archived else '',
        'chips': ''.join(f'<button type="button" data-mention="@{escape(h)}">@{escape(h)}</button>'
                         for h in board.agents),
    }


class Handler(BaseHTTPRequestHandler):
    timeout = 10

    def log_request(self, code='-', size='-'):
        LOGGER.debug('%s %s', self.command, code)

    def _send(self, status, content_type, data):
        self.send_response(status)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('Referrer-Policy', 'same-origin')
        self.send_header('Content-Security-Policy', "default-src 'self'; frame-ancestors 'none'; "
                         "base-uri 'none'; form-action 'self'")
        self.end_headers()
        if self.command != 'HEAD':
            self.wfile.write(data)

    def _json(self, status, data):
        self._send(status, 'application/json; charset=utf-8', json.dumps(data, ensure_ascii=False).encode())

    def _payload(self):
        if self.headers.get('Transfer-Encoding'):
            raise BoardError('Transfer-Encoding は使用できません。')
        lengths = self.headers.get_all('Content-Length', [])
        if len(lengths) != 1 or not re.fullmatch(r'[0-9]{1,10}', lengths[0]):
            raise BoardError('Content-Length が正しくありません。')
        length = int(lengths[0])
        if length > MAX_BODY:
            raise BoardError('入力が大きすぎます。', 413)
        if self.headers.get_content_type() != 'application/json':
            raise BoardError('JSON を送信してください。', 415)
        try:
            raw = self.rfile.read(length)
            data = json.loads(raw.decode('utf-8')) if len(raw) == length else None
        except (ValueError, RecursionError):
            data = None
        if not isinstance(data, dict):
            raise BoardError('JSON オブジェクトを送信してください。')
        return data

    def _post(self, path, query, data):
        board = self.server.board
        if path == '/api/open':
            return 200, _state(board, query, mark=True)
        if path == '/api/forums':
            return 201, {'forum_id': board.create_forum(_string(data, 'name'))}
        if path == '/api/threads':
            fid = _integer(data.get('forum_id'))
            forum = next((f for f in board.forums(archived=True) if f['id'] == fid), None)
            if forum is None:
                raise BoardError('フォーラムが見つかりません。', 404)
            tid, number = board.new(forum['name'], _string(data, 'title'), _string(data, 'body'), *HUMAN)
            return 201, {'forum_id': fid, 'thread_id': tid, 'post_no': number}
        if match := re.fullmatch(r'/api/(forums|threads)/([0-9]+)/(status|reply|move)', path):
            kind, value, operation = match.groups()
            id = _integer(value)
            if operation == 'status':
                board.set_status('forum' if kind == 'forums' else 'thread', id, _string(data, 'status'))
                return 200, {}
            if operation == 'reply' and kind == 'threads':
                return 201, {'post_no': board.reply(id, _string(data, 'body'), *HUMAN)}
            if operation == 'move' and kind == 'threads':
                board.move(id, _integer(data.get('forum_id')))
                return 200, {}
        if match := re.fullmatch(r'/api/agents/([A-Za-z0-9._-]+)/(stop|reset)', path):
            handle, operation = match.groups()
            if handle not in board.agents:
                raise BoardError('住人が見つかりません。', 404)
            if operation == 'reset':
                board.reset(handle)
            else:
                if self.server.workers is None:
                    raise BoardError('住人は稼働していません。', 409)
                self.server.workers.stop(handle)
            return 200, {}
        raise BoardError('ページが見つかりません。', 404)

    def _check_access(self):
        if not self.server.access.allows(self.headers):
            raise BoardError('このホスト名からの接続は許可されていません。', 403)

    def do_GET(self):
        try:
            self._check_access()
            path, _, query = self.path.partition('?')
            if path in ASSETS:
                file, content_type = ASSETS[path]
                self._send(200, content_type, (STATIC / file).read_bytes())
            elif path == '/api/poll':
                self._json(200, _state(self.server.board, query))
            elif path == '/':
                data = _state(self.server.board, query, full=True)
                for key in ('forum_title', 'toggle_url'):
                    data[key] = escape(data[key])
                data['new_allowed'] = str(data['new_allowed']).lower()
                data['reply_allowed'] = str(data['reply_allowed']).lower()
                data['reply_hidden'] = '' if data['thread_id'] else ' hidden'
                index = Template((STATIC / 'index.html').read_text(encoding='utf-8'))
                self._send(200, 'text/html; charset=utf-8', index.substitute(data).encode())
            else:
                raise BoardError('ページが見つかりません。', 404)
        except BoardError as exc:
            self._json(exc.status, {'error': str(exc)})

    do_HEAD = do_GET

    def do_POST(self):
        try:
            self._check_access()
            if not _same_origin(self.headers):
                raise BoardError('この送信元からの操作は許可されていません。', 403)
            path, _, query = self.path.partition('?')
            status, data = self._post(path, query, self._payload())
            self._json(status, data)
        except BoardError as exc:
            self._json(exc.status, {'error': str(exc)})


class _IPv6Server(ThreadingHTTPServer):
    address_family = socket.AF_INET6


def make_server(host, port, board, workers, access):
    """Bind a server without starting its HTTP loop or any board workers."""
    if host.startswith('[') and host.endswith(']'):
        host = host[1:-1]
    cls = _IPv6Server if ':' in host else ThreadingHTTPServer
    server = cls((host, port), Handler)
    server.board = board
    server.workers = workers
    server.access = access
    return server
