"""Verify, fetch, and activate a published NixOS closure from a private GCS cache."""
import argparse
from contextlib import contextmanager
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import socket
import subprocess
import sys
from threading import Lock, Thread
import time
from urllib import parse, request
from urllib.error import HTTPError, URLError

_gcs_path = Path(os.environ.get('FLAKE_DEPLOY_GCS_OBJECT') or Path(__file__).with_name('gcs-object.py'))
_spec = importlib.util.spec_from_file_location('gcs_object', _gcs_path)
GCS = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(GCS)

SHA_RE = r'[0-9a-f]{40}'
KEY_RE = r'(flake-public-cache-[1-9][0-9]*):[A-Za-z0-9+/]{43}='
NIX32 = '[0-9abcdfghijklmnpqrsvwxyz]'


def validate_target(bucket, host, key):
    if not re.fullmatch(r'gs://flake-public-cache-[0-9]+', bucket):
        raise ValueError('Expected the production cache bucket URI')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]+', host):
        raise ValueError('Unexpected system hostname')
    key_match = re.fullmatch(KEY_RE, key)
    if not key_match:
        raise ValueError('Expected the independently pinned cache public key')
    return key_match[1]


def read_stable_commit(bucket):
    channel = json.loads(GCS.read_object(bucket + '/channels/stable.json'))
    commit = channel['commit']
    if channel['version'] != 1 or not isinstance(commit, str) or not re.fullmatch(SHA_RE, commit) \
            or channel['release'] != f'releases/{commit}.json':
        raise ValueError('Invalid stable pointer')
    return commit


def resolve(bucket, host, key, commit=None):
    key_name = validate_target(bucket, host, key)
    if commit is None:
        commit = read_stable_commit(bucket)
    if not re.fullmatch(SHA_RE, commit):
        raise ValueError('Expected a full Git commit SHA')
    manifest = json.loads(GCS.read_object(f'{bucket}/releases/{commit}.json'))
    cache = f'{bucket}/cache/{key_name}'
    if (manifest['version'] != 1 or manifest['commit'] != commit or manifest['cache'] != cache
            or not secrets.compare_digest(manifest['signing_public_key'], key)):
        raise ValueError('Release manifest has an unexpected commit, cache URI or signing key')
    path = manifest['hosts'][host]
    if not re.fullmatch(fr'/nix/store/{NIX32}{{32}}-nixos-system-{re.escape(host)}-[A-Za-z0-9.+-]+', path):
        raise ValueError('Release does not name a NixOS system for this host')
    return commit, cache, path


def remote_branch_commit(repo_dir, remote='origin', branch='main'):
    if not remote or remote.startswith('-'):
        raise ValueError('Invalid git remote name')
    if not branch or branch.startswith('-') or any(c.isspace() for c in branch):
        raise ValueError('Invalid git branch name')
    if not repo_dir or not Path(repo_dir).exists():
        raise ValueError(f'Local git checkout not found at {repo_dir}; pass --repo or --commit')
    ref = f'refs/heads/{branch}'
    result = subprocess.run(
        ['git', '-C', str(repo_dir), 'ls-remote', '--', remote, ref],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=45,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or f'git ls-remote exited with {result.returncode}'
        raise ValueError(f'Failed to query {remote}/{branch}: {detail}')
    matches = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == ref:
            matches.append(parts[0])
    if len(matches) != 1 or not re.fullmatch(SHA_RE, matches[0]):
        raise ValueError(f'Could not resolve a single commit SHA for {remote}/{branch}')
    return matches[0]


def wait_for_published_commit(bucket, desired_commit, *, interval=20.0, timeout=3600.0,
                              sleep_fn=time.sleep, clock_fn=time.monotonic):
    if not re.fullmatch(SHA_RE, desired_commit):
        raise ValueError('Expected a full Git commit SHA')
    deadline = clock_fn() + timeout
    last_seen = object()
    waited = False
    while True:
        try:
            published = read_stable_commit(bucket)
        except HTTPError as exc:
            if exc.code != 404:
                raise
            exc.close()
            published = None
        if published == desired_commit:
            if waited:
                print(f'Published: {desired_commit[:12]} is now on stable.', flush=True)
            return desired_commit
        remaining = deadline - clock_fn()
        if remaining <= 0:
            seen_str = published[:12] if published else 'none'
            raise TimeoutError(
                f'Timed out waiting for {desired_commit[:12]} on stable (last seen: {seen_str})'
            )
        if published != last_seen:
            seen_str = published[:12] if published else 'none'
            print(
                f'Waiting: {desired_commit[:12]} is not yet on stable '
                f'(current stable: {seen_str}; polling every {interval:g}s)...',
                flush=True,
            )
            last_seen = published
        waited = True
        sleep_fn(min(interval, remaining))


def current_revision():
    result = subprocess.run(
        ['nixos-version', '--configuration-revision'],
        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
    )
    if result.returncode != 0:
        return None
    rev = result.stdout.strip()
    return rev or None


def check_not_rollback(current_rev, target_commit, repo_dir, *, allow_rollback=False):
    if allow_rollback or not current_rev or not re.fullmatch(SHA_RE, current_rev):
        return 'skipped'
    if current_rev == target_commit:
        return 'same'
    if not repo_dir or not Path(repo_dir).exists():
        return 'no-repo'
    have_cur = subprocess.run(
        ['git', '-C', str(repo_dir), 'cat-file', '-e', f'{current_rev}^{{commit}}'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0
    have_tgt = subprocess.run(
        ['git', '-C', str(repo_dir), 'cat-file', '-e', f'{target_commit}^{{commit}}'],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0
    if not (have_cur and have_tgt):
        return 'missing-commit'
    is_anc = subprocess.run(
        ['git', '-C', str(repo_dir), 'merge-base', '--is-ancestor', current_rev, target_commit],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0
    if not is_anc:
        raise ValueError(
            f'Refusing rollback from {current_rev[:12]} to {target_commit[:12]}; '
            'pass --commit <SHA> --allow-rollback to override'
        )
    return 'descendant'


def allowed_cache_path(path):
    return path == 'nix-cache-info' or re.fullmatch(
        fr'{NIX32}{{32}}\.narinfo|nar/{NIX32}{{52}}\.nar\.zst', path
    ) is not None


class DownloadCache:
    def __init__(self, uri):
        self.bucket, self.prefix = GCS.split_uri(uri)
        self.lock = Lock()
        self.token = None
        self.expires = 0

    def get(self, path):
        uri = f'{GCS.BASE}/storage/v1/b/{self.bucket}/o/{parse.quote(self.prefix + "/" + path, safe="")}?alt=media'
        for attempt in range(2):
            with self.lock:
                if time.monotonic() >= self.expires:
                    self.token = GCS.access_token()
                    # Refresh early without fetching a new token for every NAR.
                    self.expires = time.monotonic() + 240
                token = self.token
            req = request.Request(uri, headers={'Authorization': f'Bearer {token}'})
            try:
                return GCS.OPENER.open(req, timeout=90)
            except HTTPError as exc:
                if exc.code != 401 or attempt:
                    raise
                exc.close()
                with self.lock:
                    if self.token == token:
                        self.expires = 0
        raise AssertionError('unreachable')


@contextmanager
def cache_proxy(remote):
    prefix = '/' + secrets.token_urlsafe(24) + '/'

    class Handler(BaseHTTPRequestHandler):
        protocol_version = 'HTTP/1.0'

        def log_message(self, *_args):
            pass

        def do_GET(self):
            self.serve(True)

        def do_HEAD(self):
            self.serve(False)

        def serve(self, body):
            path = self.path.removeprefix(prefix)
            if path == self.path or not allowed_cache_path(path):
                self.send_error(404)
                return
            try:
                src = remote.get(path)
            except HTTPError as exc:
                exc.close()
                self.send_error(exc.code if exc.code in (401, 403, 404) else 502)
                return
            except (OSError, URLError, ValueError, subprocess.SubprocessError):
                self.send_error(502)
                return
            with src:
                self.send_response(200)
                # Upstream may be chunked. HTTP/1.0 close delimits the body if no length is available.
                if length := src.headers.get('Content-Length'):
                    self.send_header('Content-Length', length)
                self.end_headers()
                if body:
                    try:
                        shutil.copyfileobj(src, self.wfile, 1024 * 1024)
                    except (BrokenPipeError, ConnectionResetError):
                        pass

    with ThreadingHTTPServer(('127.0.0.1', 0), Handler) as server:
        thread = Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f'http://127.0.0.1:{server.server_port}{prefix[:-1]}'
        finally:
            server.shutdown()
            thread.join()


def verify(source, key, top):
    subprocess.run(['nix', 'store', 'verify', '--no-contents', '--sigs-needed', '1',
                    '--option', 'trusted-public-keys', key, '--store', source, top], check=True)


def load_public_key(args):
    if args.key_file:
        return args.key_file.read_text(encoding='ascii').strip()
    if args.public_key:
        return args.public_key.strip()
    raise ValueError('Specify --public-key / --key-file (or FLAKE_DEPLOY_PUBLIC_KEY)')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('status', 'verify', 'fetch', 'test', 'switch'))
    parser.add_argument('--bucket', default=os.environ.get('FLAKE_DEPLOY_BUCKET'))
    parser.add_argument('--public-key', default=os.environ.get('FLAKE_DEPLOY_PUBLIC_KEY'),
                        help='trusted cache public key pinned independently from the manifest')
    parser.add_argument('--key-file', type=Path,
                        default=Path(p) if (p := os.environ.get('FLAKE_DEPLOY_KEY_FILE')) else None,
                        help='file containing the trusted cache public key')
    parser.add_argument('--reader-sa', default=os.environ.get('FLAKE_DEPLOY_READER_SA'),
                        help='read-only service account to impersonate via gcloud')
    parser.add_argument('--host', help='target hostname (defaults to this host; test/switch require local host)')
    parser.add_argument('--commit',
                        help='exact release SHA; if omitted for test/switch, wait for remote main on stable')
    parser.add_argument('--repo', type=Path, default=Path('/etc/nixos'),
                        help='local git checkout used for remote lookup and client-side rollback detection')
    parser.add_argument('--remote', default='origin',
                        help='git remote used to resolve the latest branch commit (default: origin)')
    parser.add_argument('--branch', default='main',
                        help='git branch used to resolve the latest commit (default: main)')
    parser.add_argument('--wait', action='store_true',
                        help='wait until the target commit is published on stable')
    parser.add_argument('--no-wait', action='store_true',
                        help='fail immediately if the latest remote commit is not yet on stable')
    parser.add_argument('--wait-interval', type=float, default=20.0,
                        help='seconds between stable channel polls while waiting (default: 20)')
    parser.add_argument('--wait-timeout', type=float, default=3600.0,
                        help='maximum seconds to wait for publication on stable (default: 3600)')
    parser.add_argument('--allow-rollback', action='store_true',
                        help='allow switching to a commit that is not a descendant of the running revision')
    args = parser.parse_args(argv)

    if not args.bucket:
        parser.error('specify --bucket or set FLAKE_DEPLOY_BUCKET')
    if args.wait and args.no_wait:
        parser.error('--wait and --no-wait cannot be used together')
    if args.wait_interval <= 0:
        parser.error('--wait-interval must be positive')
    if args.wait_timeout < 0:
        parser.error('--wait-timeout must be non-negative')
    if args.allow_rollback and args.commit is None:
        parser.error('--allow-rollback requires an explicit --commit')

    local_host = socket.gethostname()
    target_host = args.host or local_host
    if args.action in ('test', 'switch') and target_host != local_host:
        parser.error(f'cannot run {args.action} for another host ({target_host} != {local_host})')

    if args.reader_sa:
        os.environ['GCS_IMPERSONATE_SERVICE_ACCOUNT'] = args.reader_sa

    try:
        key = load_public_key(args)
        cur_rev = current_revision()
        target_commit = args.commit
        if args.action in ('test', 'switch') and target_commit is None:
            validate_target(args.bucket, target_host, key)
            desired = remote_branch_commit(args.repo, args.remote, args.branch)
            if cur_rev == desired:
                print(f'Host:    {target_host}')
                print(f'Current: {cur_rev}')
                print(f'Target:  {desired}')
                print(f'Status:  already up to date with {args.remote}/{args.branch}')
                return 0
            if args.no_wait:
                try:
                    published = read_stable_commit(args.bucket)
                except HTTPError as exc:
                    if exc.code != 404:
                        raise
                    exc.close()
                    published = None
                if published != desired:
                    seen_str = published[:12] if published else 'none'
                    raise ValueError(
                        f'Latest {args.remote}/{args.branch} commit {desired[:12]} '
                        f'is not yet on stable (current stable: {seen_str})'
                    )
            else:
                wait_for_published_commit(
                    args.bucket, desired,
                    interval=args.wait_interval, timeout=args.wait_timeout,
                )
            target_commit = desired
        elif args.wait:
            validate_target(args.bucket, target_host, key)
            desired = target_commit or remote_branch_commit(args.repo, args.remote, args.branch)
            wait_for_published_commit(
                args.bucket, desired,
                interval=args.wait_interval, timeout=args.wait_timeout,
            )
            target_commit = desired

        commit, cache, top = resolve(args.bucket, target_host, key, target_commit)
        print(f'Host:    {target_host}')
        print(f'Current: {cur_rev or "unknown"}')
        print(f'Target:  {commit}')
        print(f'System:  {top}', flush=True)
        if args.action == 'status':
            if cur_rev == commit:
                print('Status:  up to date with published release')
            else:
                print('Status:  update available (or running uncommitted/unknown revision)')
            return 0
        if args.action in ('fetch', 'test', 'switch') and target_host == local_host:
            rb_state = check_not_rollback(cur_rev, commit, args.repo, allow_rollback=args.allow_rollback)
            if rb_state in ('no-repo', 'missing-commit'):
                print(f'Note:    local git ancestry check skipped ({rb_state}); relying on signed channel')
        if args.action != 'verify':
            subprocess.run(['sudo', '-v'], check=True)
        with cache_proxy(DownloadCache(cache)) as source:
            verify(source, key, top)
            if args.action != 'verify':
                # Import only; never evaluate a flake or fall back to building.
                subprocess.run(['sudo', 'nix', 'copy', '--from', source,
                                '--option', 'require-sigs', 'true',
                                '--option', 'trusted-public-keys', key,
                                '--option', 'max-jobs', '0',
                                '--option', 'builders', '',
                                top], check=True)
        if args.action == 'verify':
            print('Verified the published system signature; nothing imported or activated.')
        elif args.action == 'fetch':
            print('Imported the verified system; nothing activated.')
        else:
            # nixos-rebuild-ng (26.05) re-execs into a freshly built nixos-rebuild before it
            # applies --store-path. That re-exec evaluates <nixpkgs/nixos>, which fails when
            # NIX_PATH has no nixos-config, and it would build and run unverified code.
            subprocess.run(['sudo', 'nixos-rebuild', args.action, '--no-reexec', '--store-path', top], check=True)
    except KeyboardInterrupt:
        print('flake-deploy: interrupted', file=sys.stderr)
        return 130
    except (KeyError, TypeError, ValueError, OSError, URLError, subprocess.SubprocessError) as exc:
        print(f'flake-deploy: {exc}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
