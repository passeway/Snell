"""Real Snell v6 traffic using the installer template and an independent client."""
import http.server
import json
import os
from pathlib import Path
import secrets
import socket
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


@unittest.skipUnless(SNELL and CLIENT and Path(SNELL).is_file() and Path(CLIENT).is_file(),
                     'requires official Snell and sing-box test binaries')
class CoreTests(unittest.TestCase):
    def test_default_mode_relays_real_traffic(self):
        self.check_mode_traffic('default', '1')

    def test_unshaped_mode_relays_real_traffic(self):
        self.check_mode_traffic('unshaped', '2')

    def test_unsafe_raw_mode_relays_real_traffic(self):
        self.check_mode_traffic('unsafe-raw', '3')

    def check_mode_traffic(self, mode, selection):
        with tempfile.TemporaryDirectory(prefix='snell-core-') as td:
            root = Path(td)
            processes = []
            logs = []

            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    self.send_response(200)
                    self.end_headers()
                    self.wfile.write(b'snell-v6-regression-ok')

                def log_message(self, *args):
                    pass

            web = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
            thread = threading.Thread(target=web.serve_forever, daemon=True)
            thread.start()

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
                # Use the actual production template, limiting the test listener to loopback.
                config = SOURCE.read_text().split(
                    'write_file /etc/snell/snell-server.conf 640 root:snell << EOF || return 1\n', 1)[1].split('\nEOF', 1)[0]
                config = config.replace('${RANDOM_PORT}', str(port)).replace('${RANDOM_PSK}', psk)
                config = config.replace('0.0.0.0:', '127.0.0.1:')
                if mode == 'default':
                    config = config.replace('mode = default', 'mode = unshaped')
                (root / 'snell-server.conf').write_text(config + '\n')
                (root / 'snell-client.conf').write_text(
                    f'Test = snell, 203.0.113.1, {port}, psk={psk}, version=6, mode=default\n')
                # Exercise the real menu operation in an isolated config directory.
                # Only the service manager and ownership are mocked; both cores run below.
                script = root / 'installer.sh'
                script.write_text(SOURCE.read_text().replace('/etc/snell', str(root)))
                subprocess.run(['bash', '-c', '''source "$1"
check_snell_installed() { :; }; check_snell_running() { return 1; }
check_snell_stopped() { :; }; chown() { :; }
switch_snell_mode''', 'mode-test', str(script)], input=selection + '\n',
                               text=True, capture_output=True, check=True, timeout=10)
                fields = dict(field.strip().split('=', 1) for field in
                              (root / 'snell-client.conf').read_text().split(',')[3:])
                self.assertEqual(fields['mode'], mode)
                self.assertEqual(fields['psk'], psk)
                server = start([SNELL, '-l', 'info', '-c', str(root / 'snell-server.conf')], 'server.log')
                wait_port(port, server)
                local_port = free_port()
                client_config = {
                    'log': {'level': 'warn'},
                    'inbounds': [{'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': local_port}],
                    'outbounds': [{'type': 'snell', 'server': '127.0.0.1', 'server_port': port,
                                   'version': 6, 'psk': fields['psk'], 'mode': fields['mode']}],
                }
                client_file = root / 'client.json'
                client_file.write_text(json.dumps(client_config))
                subprocess.run([CLIENT, 'check', '-c', str(client_file)], check=True, capture_output=True, timeout=10)
                client = start([CLIENT, 'run', '-c', str(client_file)], 'client.log')
                wait_port(local_port, client)
                response = subprocess.run([
                    'curl', '-fsS', '--noproxy', '', '--max-time', '10', '--socks5-hostname',
                    f'127.0.0.1:{local_port}', f'http://127.0.0.1:{web.server_port}/',
                ], capture_output=True, timeout=15)
                self.assertEqual(response.returncode, 0, response.stderr.decode())
                self.assertEqual(response.stdout, b'snell-v6-regression-ok')
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
                web.shutdown()
                web.server_close()
                thread.join(timeout=3)
                for log in logs:
                    log.close()


if __name__ == '__main__':
    unittest.main()
