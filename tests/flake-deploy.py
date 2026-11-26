"""Validate release metadata and rollback guards before giving any system path to Nix."""
from contextlib import contextmanager
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location('flake_deploy', Path(__file__).resolve().parents[1] / 'scripts/ci/flake-deploy.py')
deploy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deploy)
BUCKET = 'gs://flake-public-cache-1234'
SHA = 'abcdef0123' * 4
KEY = 'flake-public-cache-1:' + 'A' * 43 + '='
TOP = '/nix/store/' + 'b' * 32 + '-nixos-system-nixos-spin713-26.05'


class Release(unittest.TestCase):
    def setUp(self):
        self.channel = {'version': 1, 'commit': SHA, 'release': f'releases/{SHA}.json'}
        self.manifest = {'version': 1, 'commit': SHA, 'cache': BUCKET + '/cache/flake-public-cache-1',
                         'signing_public_key': KEY, 'hosts': {'nixos-spin713': TOP}}
        mock = patch.object(deploy.GCS, 'read_object', side_effect=self.read)
        self.read_object = mock.start()
        self.addCleanup(mock.stop)

    def read(self, uri):
        return json.dumps(self.channel if uri.endswith('/channels/stable.json') else self.manifest).encode()

    def test_selects_exact_host_and_pinned_key(self):
        self.assertEqual(deploy.resolve(BUCKET, 'nixos-spin713', KEY), (SHA, self.manifest['cache'], TOP))

    def test_pinned_commit_does_not_read_stable(self):
        deploy.resolve(BUCKET, 'nixos-spin713', KEY, SHA)
        self.read_object.assert_called_once_with(BUCKET + f'/releases/{SHA}.json')

    def test_rejects_paths_from_other_hosts_and_arbitrary_sources(self):
        for key, value in (('cache', 'gs://other-bucket/cache/flake-public-cache-1'),
                           ('signing_public_key', 'flake-public-cache-2:' + 'A' * 43 + '='),
                           ('commit', '0' * 40),
                           ('hosts', {'nixos-spin713': TOP.replace('spin713', 'desktop')})):
            with self.subTest(key=key):
                old = self.manifest[key]
                self.manifest[key] = value
                with self.assertRaises(ValueError):
                    deploy.resolve(BUCKET, 'nixos-spin713', KEY)
                self.manifest[key] = old

    def test_rejects_redirected_manifest_name(self):
        self.channel['release'] = 'releases/../../another.json'
        with self.assertRaises(ValueError):
            deploy.resolve(BUCKET, 'nixos-spin713', KEY)
        self.read_object.assert_called_once()

    def test_rejects_addressing_files_outside_nix_cache_layout(self):
        self.assertTrue(deploy.allowed_cache_path('nix-cache-info'))
        self.assertTrue(deploy.allowed_cache_path('b' * 32 + '.narinfo'))
        self.assertTrue(deploy.allowed_cache_path('nar/' + 'b' * 52 + '.nar.zst'))
        for path in ('../secret', 'nar/../../secret', 'releases/demo.json', 'nar/test.nar.zst', 'foo?test=1'):
            self.assertFalse(deploy.allowed_cache_path(path))

    def test_rejects_rollback_unless_explicitly_allowed(self):
        with tempfile.TemporaryDirectory() as tmp:
            def git(*args):
                return subprocess.check_output(['git', '-C', tmp, *args], text=True).strip()
            git('init', '-b', 'main')
            git('config', 'user.email', 'test@example.invalid')
            git('config', 'user.name', 'Test')
            Path(tmp, 'f').write_text('1\n', encoding='utf-8')
            git('add', 'f')
            git('commit', '-m', 'c1')
            c1 = git('rev-parse', 'HEAD')
            Path(tmp, 'f').write_text('2\n', encoding='utf-8')
            git('add', 'f')
            git('commit', '-m', 'c2')
            c2 = git('rev-parse', 'HEAD')

            self.assertEqual(deploy.check_not_rollback(c1, c2, tmp), 'descendant')
            self.assertEqual(deploy.check_not_rollback(c2, c2, tmp), 'same')
            with self.assertRaises(ValueError):
                deploy.check_not_rollback(c2, c1, tmp)
            self.assertEqual(deploy.check_not_rollback(c2, c1, tmp, allow_rollback=True), 'skipped')

    def test_rejects_activating_for_another_host(self):
        with patch.object(deploy.socket, 'gethostname', return_value='nixos-desktop'):
            with self.assertRaises(SystemExit):
                deploy.main(['test', '--bucket', BUCKET, '--public-key', KEY, '--commit', SHA, '--host', 'nixos-spin713'])

    def test_remote_branch_commit_reads_origin_main_without_pull(self):
        with tempfile.TemporaryDirectory() as tmp:
            origin = Path(tmp) / 'origin.git'
            work = Path(tmp) / 'work'
            stale = Path(tmp) / 'stale'

            def git(repo, *args):
                return subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()

            subprocess.check_call(['git', 'init', '--bare', str(origin)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.check_call(['git', 'clone', str(origin), str(work)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            git(work, 'checkout', '-b', 'main')
            git(work, 'config', 'user.email', 'test@example.invalid')
            git(work, 'config', 'user.name', 'Test')
            (work / 'f').write_text('1\n', encoding='utf-8')
            git(work, 'add', 'f')
            git(work, 'commit', '-m', 'c1')
            git(work, 'push', '-u', 'origin', 'main')
            subprocess.check_call(['git', 'clone', str(origin), str(stale)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            (work / 'f').write_text('2\n', encoding='utf-8')
            git(work, 'add', 'f')
            git(work, 'commit', '-m', 'c2')
            c2 = git(work, 'rev-parse', 'HEAD')
            git(work, 'push', 'origin', 'main')

            self.assertNotEqual(git(stale, 'rev-parse', 'HEAD'), c2)
            self.assertEqual(deploy.remote_branch_commit(stale), c2)

    def test_wait_for_published_commit_polls_until_target_appears(self):
        old_sha = '1' * 40
        new_sha = '2' * 40
        responses = [
            HTTPError('https://storage.googleapis.com/', 404, 'Not Found', {}, None),
            json.dumps({'version': 1, 'commit': old_sha, 'release': f'releases/{old_sha}.json'}).encode(),
            json.dumps({'version': 1, 'commit': new_sha, 'release': f'releases/{new_sha}.json'}).encode(),
        ]
        now = [0.0]
        sleeps = []

        def fake_read(uri):
            if '/releases/progress/' in uri:
                raise HTTPError('https://storage.googleapis.com/', 404, 'Not Found', {}, None)
            item = responses.pop(0)
            if isinstance(item, Exception):
                raise item
            return item

        def fake_sleep(seconds):
            sleeps.append(seconds)
            now[0] += seconds

        self.read_object.side_effect = fake_read
        with patch('sys.stdout', new_callable=io.StringIO):
            got = deploy.wait_for_published_commit(
                BUCKET, new_sha, interval=15.0, timeout=120.0,
                sleep_fn=fake_sleep, clock_fn=lambda: now[0],
            )
        self.assertEqual(got, new_sha)
        self.assertEqual(sleeps, [15.0, 15.0])

    def test_wait_for_published_commit_times_out_and_does_not_swallow_403(self):
        old_sha = '1' * 40
        new_sha = '2' * 40
        now = [0.0]

        def fake_sleep(seconds):
            now[0] += seconds

        def read_old(uri):
            if '/releases/progress/' in uri:
                raise HTTPError('https://storage.googleapis.com/', 404, 'Not Found', {}, None)
            return json.dumps({'version': 1, 'commit': old_sha, 'release': f'releases/{old_sha}.json'}).encode()

        self.read_object.side_effect = read_old
        with patch('sys.stdout', new_callable=io.StringIO), self.assertRaises(TimeoutError):
            deploy.wait_for_published_commit(
                BUCKET, new_sha, interval=10.0, timeout=25.0,
                sleep_fn=fake_sleep, clock_fn=lambda: now[0],
            )

        self.read_object.side_effect = HTTPError('https://storage.googleapis.com/', 403, 'Forbidden', {}, None)
        with self.assertRaises(HTTPError):
            deploy.wait_for_published_commit(
                BUCKET, new_sha, interval=10.0, timeout=25.0,
                sleep_fn=fake_sleep, clock_fn=lambda: now[0],
            )

    def test_switch_without_commit_exits_early_when_already_at_origin_main(self):
        with patch.object(deploy.socket, 'gethostname', return_value='nixos-spin713'), \
                patch.object(deploy, 'current_revision', return_value=SHA), \
                patch.object(deploy, 'remote_branch_commit', return_value=SHA), \
                patch.object(deploy, 'github_repo_from_remote', return_value='khimoo/flake_public'), \
                patch.object(deploy.subprocess, 'run') as mock_run, \
                patch('sys.stdout', new_callable=io.StringIO) as out:
            rc = deploy.main(['switch', '--bucket', BUCKET, '--public-key', KEY])
        self.assertEqual(rc, 0)
        self.assertIn('already up to date', out.getvalue())
        self.read_object.assert_not_called()
        mock_run.assert_not_called()

    def test_switch_without_commit_waits_for_origin_main_then_switches(self):
        old_sha = '1' * 40

        @contextmanager
        def fake_proxy(_remote, **_kwargs):
            yield 'http://127.0.0.1:9999/tok'

        calls = []

        def fake_run(cmd, **_kwargs):
            calls.append(cmd)
            return subprocess.CompletedProcess(cmd, 0)

        with patch.object(deploy.socket, 'gethostname', return_value='nixos-spin713'), \
                patch.object(deploy, 'current_revision', return_value=old_sha), \
                patch.object(deploy, 'remote_branch_commit', return_value=SHA), \
                patch.object(deploy, 'github_repo_from_remote', return_value='khimoo/flake_public'), \
                patch.object(deploy, 'wait_for_published_commit', return_value=SHA) as mock_wait, \
                patch.object(deploy, 'check_not_rollback', return_value='descendant'), \
                patch.object(deploy, 'cache_proxy', side_effect=fake_proxy), \
                patch.object(deploy, 'verify') as mock_verify, \
                patch.object(deploy.subprocess, 'run', side_effect=fake_run), \
                patch('sys.stdout', new_callable=io.StringIO):
            rc = deploy.main(['switch', '--bucket', BUCKET, '--public-key', KEY])
        self.assertEqual(rc, 0)
        mock_wait.assert_called_once()
        self.assertEqual(mock_wait.call_args.args, (BUCKET, SHA))
        self.assertEqual(mock_wait.call_args.kwargs['interval'], 20.0)
        self.assertEqual(mock_wait.call_args.kwargs['timeout'], 3600.0)
        mock_verify.assert_called_once_with('http://127.0.0.1:9999/tok', KEY, TOP)
        self.assertEqual(calls[0], ['sudo', '-v'])
        self.assertEqual(calls[1][:4], ['sudo', 'nix', 'copy', '--from'])
        self.assertEqual(calls[2], ['sudo', 'nixos-rebuild', 'switch', '--no-reexec', '--store-path', TOP])

    def test_switch_with_explicit_commit_still_runs_when_current_matches(self):
        @contextmanager
        def fake_proxy(_remote, **_kwargs):
            yield 'http://127.0.0.1:9999/tok'

        calls = []

        def fake_run(cmd, **_kwargs):
            calls.append(cmd)
            return subprocess.CompletedProcess(cmd, 0)

        with patch.object(deploy.socket, 'gethostname', return_value='nixos-spin713'), \
                patch.object(deploy, 'current_revision', return_value=SHA), \
                patch.object(deploy, 'github_repo_from_remote', return_value=None), \
                patch.object(deploy, 'check_not_rollback', return_value='same'), \
                patch.object(deploy, 'cache_proxy', side_effect=fake_proxy), \
                patch.object(deploy, 'verify'), \
                patch.object(deploy.subprocess, 'run', side_effect=fake_run), \
                patch('sys.stdout', new_callable=io.StringIO):
            rc = deploy.main(['switch', '--bucket', BUCKET, '--public-key', KEY, '--commit', SHA])
        self.assertEqual(rc, 0)
        self.assertEqual(calls[-1], ['sudo', 'nixos-rebuild', 'switch', '--no-reexec', '--store-path', TOP])

    def test_switch_no_wait_fails_when_latest_not_yet_published(self):
        old_sha = '1' * 40
        new_sha = '2' * 40
        self.channel = {'version': 1, 'commit': old_sha, 'release': f'releases/{old_sha}.json'}
        with patch.object(deploy.socket, 'gethostname', return_value='nixos-spin713'), \
                patch.object(deploy, 'current_revision', return_value=old_sha), \
                patch.object(deploy, 'remote_branch_commit', return_value=new_sha), \
                patch.object(deploy, 'github_repo_from_remote', return_value=None), \
                patch('sys.stderr', new_callable=io.StringIO) as err:
            rc = deploy.main(['switch', '--no-wait', '--bucket', BUCKET, '--public-key', KEY])
        self.assertEqual(rc, 1)
        self.assertIn('not yet on stable', err.getvalue())

    def test_progress_tracker_advances_monotonically_and_formats_counts(self):
        store = {}
        queries = []

        def fake_read(uri):
            queries.append(uri)
            if uri not in store:
                raise HTTPError('https://storage.googleapis.com/', 404, 'Not Found', {}, None)
            return json.dumps(store[uri]).encode()

        prefix = f'{BUCKET}/releases/progress/{SHA}'
        tracker = deploy.ProgressTracker(BUCKET, SHA, read_object_fn=fake_read)
        tracker.poll()
        self.assertEqual(tracker.format_progress(), 'starting')

        store[f'{prefix}/01-checkout.json'] = {'phase': 'checkout'}
        store[f'{prefix}/02-build-desktop.json'] = {'phase': 'build-desktop'}
        tracker.poll()
        self.assertEqual(tracker.format_progress(), 'building nixos-desktop (2/7)')

        queries.clear()
        store[f'{prefix}/03-build-spin713.json'] = {'phase': 'build-spin713'}
        store[f'{prefix}/04-publish-scan.json'] = {'phase': 'publish-scan'}
        store[f'{prefix}/05-publish-pack.json'] = {'phase': 'publish-pack', 'total': 3420, 'new': 12}
        tracker.poll()
        self.assertEqual(tracker.format_progress(), 'packing cache: 12 new / 3420 total (5/7)')
        self.assertFalse(any('01-checkout.json' in q or '02-build-desktop.json' in q for q in queries))

    def test_wait_stops_on_ci_failure_and_continues_on_retry(self):
        old_sha = '1' * 40
        new_sha = '2' * 40
        prefix = f'{BUCKET}/releases/progress/{new_sha}'
        objects = {
            f'{BUCKET}/channels/stable.json': {'version': 1, 'commit': old_sha, 'release': f'releases/{old_sha}.json'},
            f'{prefix}/01-checkout.json': {'phase': 'checkout'},
            f'{prefix}/99-failed.json': {'phase': 'failed', 'exit_code': 1},
        }

        def fake_read(uri):
            if uri not in objects:
                raise HTTPError('https://storage.googleapis.com/', 404, 'Not Found', {}, None)
            return json.dumps(objects[uri]).encode()

        failed_ci = deploy.CIStatusTracker(
            'khimoo/flake_public', new_sha,
            fetch_fn=lambda _r, _c: {
                'status': 'completed',
                'conclusion': 'failure',
                'html_url': 'https://github.com/khimoo/flake_public/actions/runs/99',
            },
        )
        with patch('sys.stdout', new_callable=io.StringIO), self.assertRaises(ValueError) as ctx:
            deploy.wait_for_published_commit(
                BUCKET, new_sha, interval=5.0, timeout=30.0,
                sleep_fn=lambda _s: None, read_object_fn=fake_read, ci_tracker=failed_ci,
            )
        self.assertIn('failure', str(ctx.exception))
        self.assertIn('actions/runs/99', str(ctx.exception))

        # When CI is actively retrying, a stale 99-failed.json must not abort waiting.
        retrying_ci = deploy.CIStatusTracker(
            'khimoo/flake_public', new_sha,
            fetch_fn=lambda _r, _c: {'status': 'in_progress', 'conclusion': None, 'html_url': 'https://example/run'},
        )

        def publish_on_sleep(_s):
            objects[f'{BUCKET}/channels/stable.json'] = {
                'version': 1, 'commit': new_sha, 'release': f'releases/{new_sha}.json',
            }

        with patch('sys.stdout', new_callable=io.StringIO) as out:
            got = deploy.wait_for_published_commit(
                BUCKET, new_sha, interval=5.0, timeout=30.0,
                sleep_fn=publish_on_sleep, read_object_fn=fake_read, ci_tracker=retrying_ci,
            )
        self.assertEqual(got, new_sha)
        self.assertIn('retrying', out.getvalue())

    def test_github_repo_from_url_and_download_progress(self):
        self.assertEqual(deploy.github_repo_from_url('git@github.com:khimoo/flake_public.git'), 'khimoo/flake_public')
        self.assertEqual(deploy.github_repo_from_url('https://github.com/khimoo/flake_public'), 'khimoo/flake_public')
        self.assertIsNone(deploy.github_repo_from_url('/tmp/local/repo'))

        buf = io.StringIO()
        now = [10.0]
        prog = deploy.DownloadProgress(report_interval=2.0, clock_fn=lambda: now[0], stream=buf)
        prog.start_item('a' * 32 + '.narinfo')
        prog.start_item('nar/' + 'b' * 52 + '.nar.zst')
        prog.add_bytes('nar/' + 'b' * 52 + '.nar.zst', 2 * 1024 * 1024)
        now[0] = 13.0
        prog.add_bytes('nar/' + 'b' * 52 + '.nar.zst', 3 * 1024 * 1024)
        prog.finish()
        text = buf.getvalue()
        self.assertIn('Fetching: 1 narinfo, 1 nar', text)
        self.assertIn('Fetched:  1 narinfo, 1 nar (5.0 MiB total)', text)


if __name__ == '__main__':
    unittest.main()
