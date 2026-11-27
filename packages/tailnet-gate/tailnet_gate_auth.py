"""Answer Caddy forward_auth: is the peer a tailnet device that may use this service?

Caddy asks GET /check?allow=<device>,<device> with the connecting peer address in
X-Tailnet-Peer. The peer is named by `tailscale whois` (first MagicDNS label). A
peer address that belongs to this machine is this machine itself (--self), because
connections from the server host to its own name do not always use the tailnet
address.
"""

import argparse
import ipaddress
import json
import logging
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

TTL = 60
LOGGER = logging.getLogger('tailnet-gate-auth')


def normalize(address):
    ip = ipaddress.ip_address(address.strip().strip('[]').split('%', 1)[0])
    return getattr(ip, 'ipv4_mapped', None) or ip


def is_local(ip):
    family = socket.AF_INET6 if ip.version == 6 else socket.AF_INET
    try:
        with socket.socket(family, socket.SOCK_STREAM) as probe:
            probe.bind((str(ip), 0))
        return True
    except OSError:
        return False


def tailscale_whois(tailscale):
    def lookup(address):
        try:
            done = subprocess.run([tailscale, 'whois', '--json', address], capture_output=True,
                                  text=True, timeout=5, check=True)
            name = json.loads(done.stdout)['Node']['Name']
        except (OSError, subprocess.SubprocessError, ValueError, KeyError, TypeError) as exc:
            LOGGER.warning('tailscale whois %s failed: %s', address, exc)
            return None
        return name.split('.', 1)[0].lower() if isinstance(name, str) and name else None
    return lookup


class Devices:
    def __init__(self, self_name, lookup, local=is_local, clock=time.monotonic):
        self.self_name = self_name.lower()
        self.lookup = lookup
        self.local = local
        self.clock = clock
        self.cache = {}
        self.lock = threading.Lock()

    def name(self, address):
        try:
            ip = normalize(address)
        except ValueError:
            return None
        if ip.is_loopback or self.local(ip):
            return self.self_name
        key = str(ip)
        now = self.clock()
        with self.lock:
            cached = self.cache.get(key)
        if cached and cached[1] > now:
            return cached[0]
        name = self.lookup(key)
        with self.lock:
            self.cache[key] = (name, now + TTL)
        return name


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        LOGGER.debug(format, *args)

    def _reply(self, status, text):
        body = (text + '\n').encode()
        self.send_response(status)
        self.send_header('Content-Type', 'text/plain; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        url = urlsplit(self.path)
        allow = {d.strip().lower() for v in parse_qs(url.query).get('allow', []) for d in v.split(',') if d.strip()}
        peers = self.headers.get_all('X-Tailnet-Peer', [])
        if url.path != '/check' or len(peers) != 1:
            self._reply(400, 'bad request')
            return
        device = self.server.devices.name(peers[0])
        if device is not None and device in allow:
            self._reply(200, 'ok')
        else:
            LOGGER.info('denied %s (device %s)', peers[0], device or 'unknown')
            self._reply(403, 'この端末からの接続は許可されていません。')


def make_server(listen, devices):
    host, _, port = listen.rpartition(':')
    server = ThreadingHTTPServer((host.strip('[]'), int(port)), Handler)
    server.devices = devices
    return server


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--listen', default='127.0.0.1:8781')
    parser.add_argument('--self', dest='self_name', required=True, help='このホストの tailnet の端末名')
    parser.add_argument('--tailscale', default='tailscale')
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format='%(levelname)s %(message)s')
    with make_server(args.listen, Devices(args.self_name, tailscale_whois(args.tailscale))) as server:
        server.serve_forever()


if __name__ == '__main__':
    main()
