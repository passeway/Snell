"""Actual systemd/OpenRC lifecycle checks in disposable, native-architecture CI containers."""
import http.server
import json
import os
from pathlib import Path
import pwd
import socket
import subprocess
import tempfile
import threading
import unittest

from test_core import CLIENT, SNELL, free_port, wait_port
from test_snell import SOURCE


@unittest.skipUnless(os.environ.get('SNELL_SERVICE_TESTS') == '1',
                     'requires a disposable container with a real service manager')
class ServiceTests(unittest.TestCase):
    def test_installed_dependencies_need_no_network_or_package_mutations(self):
        # Use the real package databases populated during image build. Queries
        # are allowed, while a second install/update would fail this test.
        result = self.shell('''source "$1"
apt-get() { echo UNEXPECTED_APT >&2; return 99; }
apk() {
    if [ "$1 $2" = 'info -e' ]; then command apk "$@"
    else echo UNEXPECTED_APK >&2; return 99
    fi
}
install_required_packages''')
        self.assertIn('必要软件包已齐全', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stdout + result.stderr)

    def test_public_ipv6_reads_real_interface_address(self):
        # CI containers have no global IPv6; a documentation address on lo
        # exercises the real ip output (no duplicate address detection on lo).
        subprocess.run(['ip', '-6', 'addr', 'add', '2001:db8::5/128', 'dev', 'lo'], check=True)
        try:
            self.assertEqual(self.shell('get_public_ipv6').stdout.strip(), '2001:db8::5')
        finally:
            subprocess.run(['ip', '-6', 'addr', 'del', '2001:db8::5/128', 'dev', 'lo'], check=True)
        self.shell('get_public_ipv6', expected=1)

    def shell(self, command, data='', expected=0):
        # Dependencies were installed using install_required_packages when building
        # the CI image. Only network downloads/address discovery use local fixtures.
        setup = '''source "$1"
install_required_packages() { :; }
replace_snell_binary() (
    stage=$(mktemp /usr/local/bin/.snell-test.XXXXXX) || exit 1
    trap 'rm -f "$stage"' EXIT
    cp "$SNELL_TEST_BINARY" "$stage" && chmod 755 "$stage" && mv -f "$stage" /usr/local/bin/snell-server
)
get_public_ip() { echo 203.0.113.1; }
get_country() { echo Test; }
'''
        result = subprocess.run(['bash', '-c', setup + command, 'service-test', str(SOURCE)],
                                input=data, text=True, capture_output=True, timeout=45)
        if result.returncode != expected:
            diagnostic = subprocess.run(['bash', '-c', '''source "$1"
set -x
get_system_type
snell_service_pid
snell_listener_pid
pid=$(snell_service_pid)
if [[ "$pid" =~ ^[1-9][0-9]*$ ]]; then
    readlink "/proc/$pid/exe"
    awk '/snell-server/ {print}' "/proc/$pid/maps"
fi
ss -H -ltnp
ls -ld /etc/snell /etc/snell/snell-server.conf
id snell
ps -o pid,ppid,stat,args
''', 'service-diagnostic', str(SOURCE)], capture_output=True, text=True, timeout=10)
            print(diagnostic.stdout + diagnostic.stderr, flush=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def assert_traffic(self):
        fields = self.client.read_text().splitlines()[0].split(',')
        options = dict(item.strip().split('=', 1) for item in fields[3:])

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b'snell-service-user-ok')

            def log_message(self, *args):
                pass

        web = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        thread = threading.Thread(target=web.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as temporary:
                local_port = free_port()
                config = Path(temporary) / 'client.json'
                config.write_text(json.dumps({
                    'log': {'level': 'warn'},
                    'inbounds': [{'type': 'mixed', 'listen': '127.0.0.1', 'listen_port': local_port}],
                    'outbounds': [{'type': 'snell', 'server': '127.0.0.1',
                                   'server_port': int(fields[2]), 'version': 6,
                                   'psk': options['psk'], 'mode': options['mode']}],
                }))
                with (Path(temporary) / 'client.log').open('w+') as log:
                    client = subprocess.Popen([CLIENT, 'run', '-c', str(config)],
                                              stdout=log, stderr=subprocess.STDOUT)
                    try:
                        wait_port(local_port, client)
                        response = subprocess.run([
                            'curl', '-fsS', '--noproxy', '', '--max-time', '10', '--socks5-hostname',
                            f'127.0.0.1:{local_port}', f'http://127.0.0.1:{web.server_port}/',
                        ], capture_output=True, timeout=15)
                        self.assertEqual(response.returncode, 0, response.stderr.decode())
                        self.assertEqual(response.stdout, b'snell-service-user-ok')
                    finally:
                        client.terminate()
                        try:
                            client.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            client.kill(); client.wait()
        finally:
            web.shutdown(); web.server_close(); thread.join(timeout=3)

    def test_real_install_changes_failure_recovery_update_and_uninstall(self):
        self.assertTrue(Path(SNELL).is_file())
        self.assertTrue(Path(CLIENT).is_file())
        self.server = Path('/etc/snell/snell-server.conf')
        self.client = Path('/etc/snell/snell-client.conf')
        self.assertFalse(self.server.exists(), 'service test must start in a clean container')
        try:
            # Retry failures after downloading the core, after creating the
            # server config, and after writing the service but before enabling it.
            self.shell('choose_port() { return 1; }; install_snell', expected=1)
            self.assertTrue(Path('/usr/local/bin/snell-server').exists())
            self.assertFalse(self.server.exists())
            self.shell('uninstall_snell')
            self.assertFalse(Path('/usr/local/bin/snell-server').exists())
            self.shell('choose_port() { return 1; }; install_snell', expected=1)
            self.shell('''eval "$(declare -f write_file | sed '1s/write_file/original_write_file/')"
write_file() {
    case "$1" in /etc/init.d/snell|/etc/systemd/system/snell.service) return 1 ;; esac
    original_write_file "$@"
}
umask 077; install_snell''', expected=1)
            incomplete_config = self.server.read_bytes()
            self.shell('register_snell_service() { return 1; }; install_snell', expected=1)
            self.shell('umask 077; install_snell')
            self.assertEqual(self.server.read_bytes(), incomplete_config)
            self.assertEqual(self.server.parent.stat().st_mode & 0o777, 0o750)
            self.assertEqual(self.server.stat().st_mode & 0o777, 0o640)
            self.assertEqual(self.client.stat().st_mode & 0o777, 0o600)
            identity = pwd.getpwnam('snell')
            self.assertEqual(self.server.parent.stat().st_gid, identity.pw_gid)
            pid = self.shell('snell_listener_pid').stdout.strip()
            uid_line = next(line for line in Path(f'/proc/{pid}/status').read_text().splitlines()
                            if line.startswith('Uid:'))
            self.assertEqual(int(uid_line.split()[1]), identity.pw_uid)
            self.assertNotEqual(identity.pw_uid, 0)
            self.shell('snell_process_exists')
            self.assert_traffic()

            before = self.server.read_bytes(), self.client.read_bytes()
            repeated = self.shell('install_snell')
            self.assertIn('已取消重复安装', repeated.stdout)
            self.assertEqual((self.server.read_bytes(), self.client.read_bytes()), before)

            # PATH must not hide the managed installation, and selecting the
            # current port must leave the actual service process untouched.
            pid = self.shell('snell_listener_pid').stdout.strip()
            self.shell('PATH=/usr/sbin:/usr/bin:/sbin:/bin; check_snell_installed && require_snell_config')
            unchanged = self.shell('change_snell_port', self.client.read_text().split(',')[2].strip() + '\n')
            self.assertIn('无需更改', unchanged.stdout)
            self.assertEqual(self.shell('snell_listener_pid').stdout.strip(), pid)
            self.assertEqual((self.server.read_bytes(), self.client.read_bytes()), before)

            # A bad on-disk config must be rejected before replacing the binary,
            # even while the healthy service continues using its loaded config.
            binary = Path('/usr/local/bin/snell-server')
            binary_before = binary.stat().st_ino, binary.stat().st_mtime_ns
            try:
                self.server.write_text('[snell-server]\npsk = ValidSecret123456\n')
                invalid = self.server.read_bytes()
                rejected = self.shell('update_snell', expected=1)
                self.assertIn('已取消更新', rejected.stderr)
                self.assertEqual(self.server.read_bytes(), invalid)
                self.assertEqual((binary.stat().st_ino, binary.stat().st_mtime_ns), binary_before)
                self.assertEqual(self.shell('snell_service_pid').stdout.strip(), pid)
                self.assert_traffic()
            finally:
                self.server.write_bytes(before[0])
            self.shell('snell_listener_pid')

            self.shell('switch_snell_mode', '2\n')
            self.shell('change_snell_port', str(free_port()) + '\n')
            self.shell('switch_snell_dns', '2\n')
            self.assertIn('mode = unshaped', self.server.read_text())
            self.assertIn('dns-ip-preference = prefer-ipv4', self.server.read_text())
            self.assert_traffic()

            # Model a port stolen after the pre-check: OpenRC's supervisor can
            # remain "started" while its actual child repeatedly fails to bind.
            before = self.server.read_bytes(), self.client.read_bytes()
            with socket.socket() as occupied:
                occupied.bind(('0.0.0.0', 0)); occupied.listen()
                port = occupied.getsockname()[1]
                failed = self.shell(f'apply_snell_setting listen "0.0.0.0:{port}" "监听地址"', expected=1)
                self.assertIn('已恢复原配置', failed.stderr)
                self.assertNotIn('已更改为', failed.stdout)
            self.assertEqual((self.server.read_bytes(), self.client.read_bytes()), before)
            self.shell('snell_listener_pid')
            self.assert_traffic()

            self.shell('stop_snell')
            self.server.parent.chmod(0o700)
            self.shell('update_snell')
            self.shell('check_snell_stopped')
            self.assertEqual(self.server.parent.stat().st_mode & 0o777, 0o750)
            self.assertEqual(self.server.read_bytes(), before[0])
            self.shell('start_snell')
            self.assert_traffic()

            # The documented foreground diagnostic process is outside the
            # service manager. Uninstall must retain files while it is alive.
            self.shell('stop_snell')
            diagnostic = subprocess.Popen(['/usr/local/bin/snell-server', '-l', 'info', '-c', str(self.server)],
                                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                wait_port(int(self.client.read_text().split(',')[2]), diagnostic)
                preserved = self.server.read_bytes(), self.client.read_bytes()
                rejected = self.shell('uninstall_snell', expected=1)
                self.assertIn('进程仍在运行', rejected.stderr)
                self.assertNotIn('卸载成功', rejected.stdout)
                self.assertIsNone(diagnostic.poll())
                self.assertTrue(Path('/usr/local/bin/snell-server').exists())
                self.assertEqual((self.server.read_bytes(), self.client.read_bytes()), preserved)
                self.shell('snell_service_file_exists')
            finally:
                diagnostic.terminate()
                try:
                    diagnostic.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    diagnostic.kill(); diagnostic.wait()

            # A missing core must not prevent entry to residual cleanup via
            # the actual menu. Keep both the real unit and manager here.
            Path('/usr/local/bin/snell-server').unlink()
            uninstalled = self.shell('clear() { :; }; main', '2\n\n0\n')
            self.assertIn('Snell 卸载成功', uninstalled.stdout)
            self.assertFalse(self.server.parent.exists())
            self.assertFalse(Path('/usr/local/bin/snell-server').exists())
            self.assertFalse(Path('/etc/init.d/snell').exists())
            self.assertFalse(Path('/etc/systemd/system/snell.service').exists())
        finally:
            # The container is discarded by CI even if a check fails.
            try:
                subprocess.run(['bash', '-c', 'source "$1"; service_action stop',
                                'service-cleanup', str(SOURCE)],
                               capture_output=True, timeout=20)
            except subprocess.TimeoutExpired:
                print('Service cleanup timed out; CI will remove the disposable container.', flush=True)
