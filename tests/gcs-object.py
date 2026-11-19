"""Check exact-object HTTP requests and distinguish missing objects from failures."""
import importlib.util
import io
from pathlib import Path
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location('gcs_object', Path(__file__).resolve().parents[1] / 'scripts/ci/gcs-object.py')
gcs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gcs)


class GCSObject(unittest.TestCase):
    def setUp(self):
        self.addCleanup(patch.stopall)
        patch.object(gcs, 'access_token', return_value='fake-test-token').start()
        self.open = patch.object(gcs.OPENER, 'open').start()
        self.open.return_value = io.BytesIO(b'{"generation":"73"}')

    def test_read_exact_generation_without_list(self):
        result = gcs.read_object('gs://private-test/channels/stable.json', generation='73')
        self.assertEqual(result, b'{"generation":"73"}')
        request = self.open.call_args.args[0]
        self.assertEqual(request.get_method(), 'GET')
        self.assertEqual(request.full_url, 'https://storage.googleapis.com/storage/v1/b/private-test/o/channels%2Fstable.json?alt=media&generation=73')
        self.assertEqual(request.get_header('Authorization'), 'Bearer fake-test-token')

    def test_get_metadata_uses_object_endpoint(self):
        self.assertEqual(gcs.object_generation('gs://private-test/requests/pending.json'), '73')
        self.assertTrue(self.open.call_args.args[0].full_url.endswith('/o/requests%2Fpending.json?fields=generation'))

    def test_write_carries_compare_and_swap(self):
        gcs.put_object('gs://private-test/channels/stable.json', b'{"data":true}', '0')
        request = self.open.call_args.args[0]
        self.assertEqual(request.get_method(), 'POST')
        self.assertEqual(request.full_url, 'https://storage.googleapis.com/upload/storage/v1/b/private-test/o?uploadType=media&name=channels%2Fstable.json&ifGenerationMatch=0')
        self.assertEqual(request.data, b'{"data":true}')
        self.assertEqual(request.get_header('Content-type'), 'application/json')

    def test_http_errors_are_distinct_and_never_reported_as_success(self):
        for status, rc in ((404, 44), (403, 1), (412, 12), (503, 1)):
            with self.subTest(status=status), patch('sys.stderr', new_callable=io.StringIO):
                self.open.side_effect = HTTPError('https://storage.googleapis.com/', status, 'test', None, None)
                self.assertEqual(gcs.main(['get', 'gs://private-test/status/1.json']), rc)
                self.assertEqual(self.open.call_args.args[0].get_method(), 'GET')

    def test_rejects_bucket_wildcards_and_does_not_call_api(self):
        for uri in ('gs://private-test', 'gs://private*/foo', 'gs://private-test/foo?alt=media', 'https://other.example/abc'):
            with self.subTest(uri=uri), self.assertRaises(ValueError):
                gcs.read_object(uri)
        self.open.assert_not_called()


if __name__ == '__main__':
    unittest.main()
