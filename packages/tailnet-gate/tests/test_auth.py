import http.client
import stat
import tempfile
import threading
import unittest
from pathlib import Path

import tailnet_gate_auth as gate


class DevicesTests(unittest.TestCase):
    def devices(self, names, local=lambda ip: False):
        self.lookups = []

        def lookup(address):
            self.lookups.append(address)
            return names.get(address)

        self.now = 0.0
        return gate.Devices('server', lookup, local=local, clock=lambda: self.now)

    def test_tailnet_peer_is_named_by_whois_and_cached(self):
        devices = self.devices({'100.117.26.65': 'laptop'})
        self.assertEqual(devices.name('100.117.26.65'), 'laptop')
        self.assertEqual(devices.name('::ffff:100.117.26.65'), 'laptop')
        self.assertEqual(self.lookups, ['100.117.26.65'])
        self.now += gate.TTL + 1
        self.assertEqual(devices.name('100.117.26.65'), 'laptop')
        self.assertEqual(len(self.lookups), 2)

    def test_own_addresses_are_this_machine(self):
        devices = self.devices({}, local=lambda ip: str(ip) == '192.168.1.10')
        for address in ['127.0.0.1', '::1', '192.168.1.10', '[::1]']:
            with self.subTest(address=address):
                self.assertEqual(devices.name(address), 'server')
        self.assertEqual(self.lookups, [])

    def test_unknown_or_malformed_peers_have_no_name(self):
        devices = self.devices({})
        self.assertIsNone(devices.name('100.64.0.9'))
        self.assertIsNone(devices.name('not-an-address'))
        self.assertIsNone(devices.name(''))

    def test_real_local_probe(self):
        self.assertTrue(gate.is_local(gate.normalize('127.0.0.1')))
        self.assertFalse(gate.is_local(gate.normalize('192.0.2.1')))


class WhoisTests(unittest.TestCase):
    def fake(self, script):
        path = Path(self.enterContext(tempfile.TemporaryDirectory())) / 'tailscale'
        path.write_text('#!/bin/sh\n' + script)
        path.chmod(path.stat().st_mode | stat.S_IXUSR)
        return str(path)

    def test_first_magicdns_label(self):
        tool = self.fake('[ "$1 $2 $3" = "whois --json 100.117.26.65" ] || exit 9\n'
                         'echo \'{"Node": {"Name": "Nixos-Spin713.tail90f228.ts.net."}}\'\n')
        self.assertEqual(gate.tailscale_whois(tool)('100.117.26.65'), 'nixos-spin713')

    def test_failures_are_no_device(self):
        for script in ['exit 1\n', 'echo not-json\n', 'echo \'{"Node": {}}\'\n']:
            with self.subTest(script=script), self.assertLogs('tailnet-gate-auth', 'WARNING'):
                self.assertIsNone(gate.tailscale_whois(self.fake(script))('100.64.0.1'))


class HTTPTests(unittest.TestCase):
    def setUp(self):
        devices = gate.Devices('server', {'100.117.26.65': 'laptop', '100.79.124.110': 'vm'}.get,
                               local=lambda ip: False)
        self.server = gate.make_server('127.0.0.1:0', devices)
        thread = threading.Thread(target=self.server.serve_forever, kwargs={'poll_interval': 0.01})
        thread.start()
        self.addCleanup(thread.join, 5)
        self.addCleanup(self.server.server_close)
        self.addCleanup(self.server.shutdown)

    def check(self, path, peers):
        conn = http.client.HTTPConnection('127.0.0.1', self.server.server_port, timeout=5)
        try:
            conn.putrequest('GET', path)
            for peer in peers:
                conn.putheader('X-Tailnet-Peer', peer)
            conn.endheaders()
            return conn.getresponse().status
        finally:
            conn.close()

    def test_listed_devices_pass_and_others_are_forbidden(self):
        allow = '/check?allow=laptop,server'
        with self.assertLogs('tailnet-gate-auth', 'INFO'):
            self.assertEqual(self.check(allow, ['100.117.26.65']), 200)
            self.assertEqual(self.check(allow, ['127.0.0.1']), 200)
            self.assertEqual(self.check(allow, ['100.79.124.110']), 403)
            self.assertEqual(self.check(allow, ['100.64.0.9']), 403)
            self.assertEqual(self.check('/check', ['100.117.26.65']), 403)

    def test_request_shape_is_strict(self):
        self.assertEqual(self.check('/check?allow=laptop', []), 400)
        self.assertEqual(self.check('/check?allow=laptop', ['100.117.26.65', '100.79.124.110']), 400)
        self.assertEqual(self.check('/other?allow=laptop', ['100.117.26.65']), 400)


if __name__ == '__main__':
    unittest.main()
