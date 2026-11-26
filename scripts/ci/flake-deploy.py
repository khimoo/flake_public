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
_DEFAULT_GCS_READ = GCS.read_object
PROGRESS_PHASES = (
    ('01-checkout', 'fetching repository'),
    ('02-build-desktop', 'building nixos-desktop'),
    ('03-build-spin713', 'building nixos-spin713'),
    ('04-publish-scan', 'scanning published cache'),
    ('05-publish-pack', 'packing cache'),
    ('06-publish-upload', 'uploading cache'),
    ('07-published', 'published, waiting for stable promote'),
)


class CachedGCSReader:
    """Read small GCS objects while reusing a short-lived access token."""

    def __init__(self):
        self.lock = Lock()
        self.token = None
        self.expires = 0.0

    def _get_token(self):
        with self.lock:
            if time.monotonic() >= self.expires:
                self.token = GCS.access_token()
                self.expires = time.monotonic() + 240.0
            return self.token

    def read_object(self, uri):
        bucket, key = GCS.split_uri(uri)
        url = f'{GCS.BASE}/storage/v1/b/{bucket}/o/{parse.quote(key, safe="")}?alt=media'
        for attempt in range(2):
            token = self._get_token()
            req = request.Request(url, headers={'Authorization': f'Bearer {token}'})
            try:
                with GCS.OPENER.open(req, timeout=30) as response:
                    payload = response.read(GCS.MAX_BYTES + 1)
                if len(payload) > GCS.MAX_BYTES:
                    raise ValueError('object response exceeded the size limit')
                return payload
            except HTTPError as exc:
                if exc.code != 401 or attempt:
                    raise
                exc.close()
                with self.lock:
                    if self.token == token:
                        self.expires = 0.0
        raise AssertionError('unreachable')


def make_gcs_reader():
    # Respect unittest patches on GCS.read_object while caching tokens in real runs.
    if GCS.read_object is _DEFAULT_GCS_READ:
        return CachedGCSReader().read_object
    return GCS.read_object


def format_duration(seconds):
    total = max(0, int(seconds))
    hours, rem = divmod(total, 3600)
    minutes, secs = divmod(rem, 60)
    if hours:
        return f'{hours:02d}:{minutes:02d}:{secs:02d}'
    return f'{minutes:02d}:{secs:02d}'


def validate_target(bucket, host, key):
    if not re.fullmatch(r'gs://flake-public-cache-[0-9]+', bucket):
        raise ValueError('Expected the production cache bucket URI')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]+', host):
        raise ValueError('Unexpected system hostname')
    key_match = re.fullmatch(KEY_RE, key)
    if not key_match:
        raise ValueError('Expected the independently pinned cache public key')
    return key_match[1]


def read_stable_commit(bucket, *, read_object_fn=None):
    read_obj = read_object_fn or GCS.read_object
    channel = json.loads(read_obj(bucket + '/channels/stable.json'))
    commit = channel['commit']
    if channel['version'] != 1 or not isinstance(commit, str) or not re.fullmatch(SHA_RE, commit) \
            or channel['release'] != f'releases/{commit}.json':
        raise ValueError('Invalid stable pointer')
    return commit


def resolve(bucket, host, key, commit=None, *, read_object_fn=None):
    read_obj = read_object_fn or GCS.read_object
    key_name = validate_target(bucket, host, key)
    if commit is None:
        commit = read_stable_commit(bucket, read_object_fn=read_obj)
    if not re.fullmatch(SHA_RE, commit):
        raise ValueError('Expected a full Git commit SHA')
    manifest = json.loads(read_obj(f'{bucket}/releases/{commit}.json'))
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


def github_repo_from_url(url):
    match = re.search(r'github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?/?$', url.strip())
    return match[1] if match else None


def github_repo_from_remote(repo_dir, remote='origin'):
    if not remote or remote.startswith('-') or not repo_dir or not Path(repo_dir).exists():
        return None
    try:
        result = subprocess.run(
            ['git', '-C', str(repo_dir), 'remote', 'get-url', '--', remote],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    return github_repo_from_url(result.stdout)


def fetch_ci_run(github_repo, commit):
    if not github_repo or not re.fullmatch(SHA_RE, commit):
        return None
    url = f'https://api.github.com/repos/{github_repo}/actions/runs?head_sha={commit}&per_page=10'
    headers = {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'flake-deploy',
    }
    if token := os.environ.get('GITHUB_TOKEN', '').strip():
        headers['Authorization'] = f'Bearer {token}'
    req = request.Request(url, headers=headers)
    try:
        with request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read(256 * 1024))
    except (OSError, URLError, ValueError):
        return None
    runs = data.get('workflow_runs') or []
    for run in runs:
        if (run.get('path') == '.github/workflows/publish-nixos-cache.yml'
                or run.get('name') == 'Build and publish NixOS cache'):
            return {
                'status': run.get('status'),
                'conclusion': run.get('conclusion'),
                'html_url': run.get('html_url'),
            }
    return None


class CIStatusTracker:
    def __init__(self, github_repo, commit, *, min_interval=60.0, fetch_fn=None, clock_fn=time.monotonic):
        self.github_repo = github_repo
        self.commit = commit
        self.min_interval = min_interval
        self.fetch_fn = fetch_fn or fetch_ci_run
        self.clock_fn = clock_fn
        self.last_fetch = None
        self.last_run = None

    def poll(self):
        if not self.github_repo:
            return None
        now = self.clock_fn()
        if self.last_fetch is None or (now - self.last_fetch) >= self.min_interval:
            self.last_fetch = now
            run = self.fetch_fn(self.github_repo, self.commit)
            if run is not None:
                self.last_run = run
        return self.last_run


def _read_json_optional(uri, read_object_fn):
    try:
        return json.loads(read_object_fn(uri))
    except HTTPError as exc:
        if exc.code == 404:
            exc.close()
            return None
        raise
    except (ValueError, KeyError, TypeError):
        return None


class ProgressTracker:
    """Track monotonic append-only worker progress markers under releases/progress/<SHA>/."""

    def __init__(self, bucket, commit, *, read_object_fn=None):
        self.bucket = bucket
        self.commit = commit
        self.read_object = read_object_fn or GCS.read_object
        self.next_index = 0
        self.current_index = -1
        self.current_data = None
        self.failed_data = None

    def poll(self):
        prefix = f'{self.bucket}/releases/progress/{self.commit}'
        while self.next_index < len(PROGRESS_PHASES):
            name = PROGRESS_PHASES[self.next_index][0]
            data = _read_json_optional(f'{prefix}/{name}.json', self.read_object)
            if data is None:
                break
            self.current_index = self.next_index
            self.current_data = data
            self.next_index += 1
        if self.failed_data is None and self.current_index < len(PROGRESS_PHASES) - 1:
            self.failed_data = _read_json_optional(f'{prefix}/99-failed.json', self.read_object)
        return self.current_index

    def format_progress(self):
        total_steps = len(PROGRESS_PHASES)
        if self.current_index < 0:
            return 'starting'
        name, label = PROGRESS_PHASES[self.current_index]
        data = self.current_data or {}
        step = f'{self.current_index + 1}/{total_steps}'
        if name == '05-publish-pack' and 'new' in data and 'total' in data:
            return f'packing cache: {data["new"]} new / {data["total"]} total ({step})'
        if name == '06-publish-upload' and 'nar_files' in data and 'meta_files' in data:
            return f'uploading cache: {data["nar_files"]} nar, {data["meta_files"]} meta ({step})'
        return f'{label} ({step})'


def wait_for_published_commit(bucket, desired_commit, *, interval=20.0, timeout=3600.0,
                              sleep_fn=time.sleep, clock_fn=time.monotonic,
                              read_object_fn=None, ci_tracker=None, progress_tracker=None):
    if not re.fullmatch(SHA_RE, desired_commit):
        raise ValueError('Expected a full Git commit SHA')
    read_obj = read_object_fn or GCS.read_object
    tracker = progress_tracker or ProgressTracker(bucket, desired_commit, read_object_fn=read_obj)
    start = clock_fn()
    deadline = start + timeout
    waited = False
    printed_url = None
    while True:
        try:
            published = read_stable_commit(bucket, read_object_fn=read_obj)
        except HTTPError as exc:
            if exc.code != 404:
                raise
            exc.close()
            published = None
        if published == desired_commit:
            if waited:
                elapsed = format_duration(clock_fn() - start)
                print(f'Published: {desired_commit[:12]} is now on stable [{elapsed}].', flush=True)
            return desired_commit

        try:
            tracker.poll()
        except HTTPError as exc:
            if exc.code in (401, 403):
                raise
            exc.close()
        except (OSError, URLError):
            pass

        ci_run = ci_tracker.poll() if ci_tracker else None
        if ci_run and ci_run.get('html_url') and ci_run['html_url'] != printed_url:
            printed_url = ci_run['html_url']
            print(f'CI run:  {printed_url}', flush=True)

        if ci_run and ci_run.get('status') == 'completed' \
                and ci_run.get('conclusion') in ('failure', 'cancelled', 'timed_out'):
            detail = f' ({ci_run["html_url"]})' if ci_run.get('html_url') else ''
            raise ValueError(
                f'CI build for {desired_commit[:12]} ended with {ci_run["conclusion"]}{detail}'
            )
        if ci_run is None and tracker.failed_data is not None:
            code = tracker.failed_data.get('exit_code', 'unknown')
            raise ValueError(f'Cache worker failed for {desired_commit[:12]} (exit_code={code})')

        now = clock_fn()
        remaining = deadline - now
        if remaining <= 0:
            seen_str = published[:12] if published else 'none'
            raise TimeoutError(
                f'Timed out waiting for {desired_commit[:12]} on stable '
                f'(last seen: {seen_str}, worker: {tracker.format_progress()})'
            )

        elapsed = format_duration(now - start)
        parts = []
        if ci_run:
            ci_state = ci_run.get('conclusion') or ci_run.get('status') or 'unknown'
            parts.append(f'ci={ci_state}')
        parts.append(f'worker={tracker.format_progress()}')
        if tracker.failed_data is not None and ci_run and ci_run.get('status') in ('queued', 'in_progress'):
            parts.append('retrying')
        seen_str = published[:12] if published else 'none'
        print(
            f'Waiting: {desired_commit[:12]} [{elapsed}] {" | ".join(parts)} (stable: {seen_str})',
            flush=True,
        )
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


class DownloadProgress:
    """Thread-safe download progress reporter for the local cache proxy."""

    def __init__(self, *, report_interval=2.0, clock_fn=time.monotonic, stream=None):
        self.lock = Lock()
        self.report_interval = report_interval
        self.clock_fn = clock_fn
        self.stream = stream if stream is not None else sys.stdout
        self.narinfo_count = 0
        self.nar_count = 0
        self.nar_bytes = 0
        self.last_report = 0.0

    def start_item(self, path):
        with self.lock:
            if path.endswith('.narinfo'):
                self.narinfo_count += 1
            elif path.startswith('nar/'):
                self.nar_count += 1
            self._maybe_report_locked()

    def add_bytes(self, path, count):
        if not count or not path.startswith('nar/'):
            return
        with self.lock:
            self.nar_bytes += count
            self._maybe_report_locked()

    def _maybe_report_locked(self):
        if self.nar_count == 0 and self.narinfo_count < 10:
            return
        now = self.clock_fn()
        if self.last_report and (now - self.last_report) < self.report_interval:
            return
        self.last_report = now
        mib = self.nar_bytes / (1024 * 1024)
        print(
            f'Fetching: {self.narinfo_count} narinfo, {self.nar_count} nar ({mib:.1f} MiB)...',
            file=self.stream, flush=True,
        )

    def finish(self):
        with self.lock:
            if self.nar_count == 0:
                return
            mib = self.nar_bytes / (1024 * 1024)
            print(
                f'Fetched:  {self.narinfo_count} narinfo, {self.nar_count} nar ({mib:.1f} MiB total)',
                file=self.stream, flush=True,
            )


@contextmanager
def cache_proxy(remote, *, progress=None):
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
                    if progress is not None:
                        progress.start_item(path)
                    try:
                        while chunk := src.read(1024 * 1024):
                            self.wfile.write(chunk)
                            if progress is not None:
                                progress.add_bytes(path, len(chunk))
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
            if progress is not None:
                progress.finish()


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
        read_obj = make_gcs_reader()
        github_repo = github_repo_from_remote(args.repo, args.remote)
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
                    published = read_stable_commit(args.bucket, read_object_fn=read_obj)
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
                ci_tracker = CIStatusTracker(github_repo, desired) if github_repo else None
                wait_for_published_commit(
                    args.bucket, desired,
                    interval=args.wait_interval, timeout=args.wait_timeout,
                    read_object_fn=read_obj, ci_tracker=ci_tracker,
                )
            target_commit = desired
        elif args.wait:
            validate_target(args.bucket, target_host, key)
            desired = target_commit or remote_branch_commit(args.repo, args.remote, args.branch)
            ci_tracker = CIStatusTracker(github_repo, desired) if github_repo else None
            wait_for_published_commit(
                args.bucket, desired,
                interval=args.wait_interval, timeout=args.wait_timeout,
                read_object_fn=read_obj, ci_tracker=ci_tracker,
            )
            target_commit = desired

        commit, cache, top = resolve(args.bucket, target_host, key, target_commit, read_object_fn=read_obj)
        print(f'Host:    {target_host}')
        print(f'Current: {cur_rev or "unknown"}')
        print(f'Target:  {commit}')
        print(f'System:  {top}', flush=True)
        if args.action == 'status':
            if cur_rev == commit:
                print('Status:  up to date with published release')
            else:
                print('Status:  update available (or running uncommitted/unknown revision)')
            if args.commit is None:
                try:
                    latest = remote_branch_commit(args.repo, args.remote, args.branch)
                except (ValueError, OSError, subprocess.SubprocessError):
                    latest = None
                if latest and latest != commit:
                    print(f'Latest:  {latest} ({args.remote}/{args.branch}, pending publish)')
                    tracker = ProgressTracker(args.bucket, latest, read_object_fn=read_obj)
                    try:
                        tracker.poll()
                    except (HTTPError, OSError, URLError):
                        pass
                    ci_run = fetch_ci_run(github_repo, latest) if github_repo else None
                    parts = []
                    if ci_run:
                        parts.append(f'ci={ci_run.get("conclusion") or ci_run.get("status") or "unknown"}')
                    parts.append(f'worker={tracker.format_progress()}')
                    if tracker.failed_data is not None:
                        parts.append(f'worker_exit={tracker.failed_data.get("exit_code", "unknown")}')
                    print(f'Progress: {" | ".join(parts)}')
                    if ci_run and ci_run.get('html_url'):
                        print(f'CI run:  {ci_run["html_url"]}')
            return 0
        if args.action in ('fetch', 'test', 'switch') and target_host == local_host:
            rb_state = check_not_rollback(cur_rev, commit, args.repo, allow_rollback=args.allow_rollback)
            if rb_state in ('no-repo', 'missing-commit'):
                print(f'Note:    local git ancestry check skipped ({rb_state}); relying on signed channel')
        if args.action != 'verify':
            subprocess.run(['sudo', '-v'], check=True)
        dl_progress = DownloadProgress() if args.action != 'verify' else None
        with cache_proxy(DownloadCache(cache), progress=dl_progress) as source:
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
