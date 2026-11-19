"""Validate release metadata and rollback guards before giving any system path to Nix."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

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


if __name__ == '__main__':
    unittest.main()
