"""Real Snell v6 traffic using the installer template and an independent client."""
import http.server
import json
import os
from pathlib import Path
import secrets
import socket
import struct
import subprocess
import tempfile
import threading
import time
import unittest

from test_snell import SOURCE

SNELL = os.environ.get('SNELL_TEST_BINARY', '')
CLIENT = os.environ.get('SING_BOX_TEST_BINARY', '')


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def wait_port(port, process):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f'proxy exited with code {process.returncode}')
        try:
            with socket.create_connection(('127.0.0.1', port), timeout=.2):
                return
        except OSError:
            time.sleep(.1)
    raise RuntimeError(f'proxy port {port} did not start')


class DNSFixture:
    """A local DNS server returning both loopback address families."""
    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.address = '127.0.0.153'
        self.sock.bind((self.address, 53))
        self.sock.settimeout(.1)
        self.stopped = threading.Event()
        self.thread = threading.Thread(target=self.serve, daemon=True)
        self.thread.start()

    def serve(self):
        while not self.stopped.is_set():
            try:
                data, peer = self.sock.recvfrom(4096)
            except socket.timeout:
                continue
            except OSError:
                return
            end = 12
            while end < len(data) and data[end]:
                end += data[end] + 1
            if end + 5 > len(data):
                continue
            qtype = struct.unpack('!H', data[end + 1:end + 3])[0]
            answer = b''
            if qtype in (1, 28):
                address = socket.inet_pton(socket.AF_INET if qtype == 1 else socket.AF_INET6,
                                          '127.0.0.1' if qtype == 1 else '::1')
                answer = b'\xc0\x0c' + struct.pack('!HHIH', qtype, 1, 60, len(address)) + address
            header = data[:2] + struct.pack('!HHHHH', 0x8180, 1, bool(answer), 0, 0)
            self.sock.sendto(header + data[12:end + 5] + answer, peer)

    def close(self):
        self.stopped.set()
        self.thread.join(timeout=2)
        self.sock.close()


class IPv6HTTPServer(http.server.ThreadingHTTPServer):
    address_family = socket.AF_INET6


@unittest.skipUnless(SNELL and CLIENT and Path(SNELL).is_file() and Path(CLIENT).is_file(),
                     'requires official Snell and sing-box test binaries')
class CoreTests(unittest.TestCase):
    def test_default_mode_relays_real_traffic(self):
        self.check_mode_traffic('default', '1')

    def test_unshaped_mode_relays_real_traffic(self):
        self.check_mode_traffic('unshaped', '2')

    def test_unsafe_raw_mode_relays_real_traffic(self):
        self.check_mode_traffic('unsafe-raw', '3')

    def test_ipv4_only_listener_relays_real_traffic(self):
        self.check_mode_traffic('default', '1', ipv6=False)

    def test_port_change_relays_real_traffic(self):
        self.check_mode_traffic('default', '1', change_port=True)

    def test_dns_preferences_choose_expected_address_family(self):
        for selection, preference, expected in [('1', 'default', None), ('2', 'prefer-ipv4', b'ipv4'),
                                                ('3', 'prefer-ipv6', b'ipv6'), ('4', 'ipv4-only', b'ipv4'),
                                                ('5', 'ipv6-only', b'ipv6')]:
            with self.subTest(preference=preference):
                self.check_mode_traffic('default', '1', dns=(selection, preference, expected))

    def check_mode_traffic(self, mode, selection, ipv6=True, dns=None, change_port=False):
        with tempfile.TemporaryDirectory(prefix='snell-core-') as td:
            root = Path(td)
            processes = []
            logs = []

            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    self.send_response(200)
                    self.end_headers()
                    payload = b'ipv6' if self.server.address_family == socket.AF_INET6 else b'ipv4'
                    self.wfile.write(payload if dns else b'snell-v6-regression-ok')

                def log_message(self, *args):
                    pass

            web = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            thread = threading.Thread(target=web.serve_forever, daemon=True)
            thread.start()
            dns_server = DNSFixture() if dns else None
            web6 = IPv6HTTPServer(('::1', web.server_port), Handler) if dns else None
            thread6 = threading.Thread(target=web6.serve_forever, daemon=True) if web6 else None
            if thread6:
                thread6.start()

            def start(args, name):
                log = (root / name).open('w+')
                logs.append(log)
                process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
                processes.append(process)
                return process

            try:
                version = subprocess.run([SNELL, '-v'], capture_output=True, text=True, check=True, timeout=10)
                self.assertIn('snell-server v6.', version.stdout + version.stderr)
                port = free_port()
                psk = secrets.token_hex(24)
                script = root / 'installer.sh'
                script.write_text(SOURCE.read_text().replace('/etc/snell', str(root)))
                detect = '' if ipv6 else 'ipv6_available() { return 1; }; '
                listen = subprocess.run(['bash', '-c', 'source "$1"; ' + detect + 'auto_listen_address "$2"',
                                         'listen-test', str(script), str(port)],
                                        capture_output=True, text=True, check=True, timeout=5).stdout.strip()
                self.assertEqual(listen, f'0.0.0.0:{port}' + (f',[::]:{port}' if ipv6 else ''))
                # Use the actual generated listening addresses and production config template.
                config = SOURCE.read_text().split(
                    'write_file /etc/snell/snell-server.conf 640 root:snell << EOF || return 1\n', 1)[1].split('\nEOF', 1)[0]
                config = config.replace('${RANDOM_PORT}', str(port)).replace('${RANDOM_PSK}', psk)
                config = config.replace('${LISTEN_ADDRESS}', listen)
                if dns_server:
                    config += f'\ndns = {dns_server.address}\n'
                    config = config.replace('dns-ip-preference = default', 'dns-ip-preference = ipv4-only')
                if mode == 'default':
                    config = config.replace('mode = default', 'mode = unshaped')
                (root / 'snell-server.conf').write_text(config + '\n')
                (root / 'snell-client.conf').write_text(
                    f'Test = snell, 203.0.113.1, {port}, psk={psk}, version=6, mode=default\n')
                # Exercise the real menu operation in an isolated config directory.
                # Only the service manager and ownership are mocked; both cores run below.
                subprocess.run(['bash', '-c', '''source "$1"
check_snell_installed() { :; }; check_snell_running() { return 1; }
check_snell_stopped() { :; }; chown() { :; }
change_snell_config''', 'mode-test', str(script)], input='2\n' + selection + '\n',
                               text=True, capture_output=True, check=True, timeout=10)
                if change_port:
                    new_port = free_port()
                    while new_port == port:
                        new_port = free_port()
                    subprocess.run(['bash', '-c', '''source "$1"
check_snell_installed() { :; }; check_snell_running() { return 1; }
check_snell_stopped() { :; }; chown() { :; }; change_snell_config''', 'port-test', str(script)],
                                   input='1\n' + str(new_port) + '\n', text=True, capture_output=True, check=True, timeout=10)
                    port = new_port
                if dns:
                    subprocess.run(['bash', '-c', '''source "$1"
check_snell_installed() { :; }; check_snell_running() { return 1; }
check_snell_stopped() { :; }; chown() { :; }; change_snell_config''', 'dns-test', str(script)],
                                   input='3\n' + dns[0] + '\n', text=True, capture_output=True, check=True, timeout=10)
                    self.assertIn('dns-ip-preference = ' + dns[1], (root / 'snell-server.conf').read_text())
                fields = dict(field.strip().split('=', 1) for field in
                              (root / 'snell-client.conf').read_text().split(',')[3:])
                self.assertEqual(fields['mode'], mode)
                self.assertEqual(fields['psk'], psk)
                self.assertEqual(int((root / 'snell-client.conf').read_text().split(',')[2]), port)
                server = start([SNELL, '-l', 'info', '-c', str(root / 'snell-server.conf')], 'server.log')
                wait_port(port, server)
                # Both inbound families must carry proxy traffic, not merely accept TCP.
                for peer in (['127.0.0.1', '::1'] if ipv6 else ['127.0.0.1']):
                    local_port = free_port()
                    client_config = {
                        'log': {'level': 'warn'},
                        'inbounds': [{'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': local_port}],
                        'outbounds': [{'type': 'snell', 'server': peer, 'server_port': port,
                                       'version': 6, 'psk': fields['psk'], 'mode': fields['mode']}],
                    }
                    client_file = root / 'client.json'
                    client_file.write_text(json.dumps(client_config))
                    subprocess.run([CLIENT, 'check', '-c', str(client_file)], check=True, capture_output=True, timeout=10)
                    client = start([CLIENT, 'run', '-c', str(client_file)], 'client-' + str(local_port) + '.log')
                    wait_port(local_port, client)
                    destination = 'snell-regression.test' if dns else '127.0.0.1'
                    response = subprocess.run([
                        'curl', '-fsS', '--noproxy', '', '--max-time', '10', '--socks5-hostname',
                        f'127.0.0.1:{local_port}', f'http://{destination}:{web.server_port}/',
                    ], capture_output=True, timeout=15)
                    self.assertEqual(response.returncode, 0, response.stderr.decode())
                    if dns:
                        self.assertIn(response.stdout, [dns[2]] if dns[2] else [b'ipv4', b'ipv6'])
                    else:
                        self.assertEqual(response.stdout, b'snell-v6-regression-ok')
                    client.terminate()
                    client.wait(timeout=5)
                if not ipv6:
                    with self.assertRaises(OSError):
                        socket.create_connection(('::1', port), timeout=.5)
                self.assertIsNone(server.poll())
            except Exception:
                for log in logs:
                    log.flush()
                    log.seek(0)
                    print(log.read(), flush=True)
                raise
            finally:
                for process in reversed(processes):
                    if process.poll() is None:
                        process.terminate()
                        try:
                            process.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            process.kill()
                            process.wait()
                if dns_server:
                    dns_server.close()
                if web6:
                    web6.shutdown()
                    web6.server_close()
                    thread6.join(timeout=3)
                web.shutdown()
                web.server_close()
                thread.join(timeout=3)
                for log in logs:
                    log.close()


if __name__ == '__main__':
    unittest.main()
