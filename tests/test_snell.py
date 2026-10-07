"""Offline regression tests. All installer paths are redirected to a temporary tree."""
import os
import pathlib
import pty
import select
import shutil
import signal
import subprocess
import tempfile
import time
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'Snell.sh'


class SnellTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.code = SOURCE.read_text().replace('if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then\n    main\nfi\n', '')
        for path in ['/usr/local/bin', '/etc/snell', '/etc/init.d',
                     '/etc/systemd/system', '/etc/periodic/hourly',
                     '/etc/logrotate.d', '/var/lib/logrotate', '/var/log']:
            (self.root / path.lstrip('/')).mkdir(parents=True, exist_ok=True)
            self.code = self.code.replace(path, str(self.root / path.lstrip('/')))
        os_release = self.root / 'os-release'
        os_release.write_text('ID=debian\n')
        self.code = self.code.replace('/etc/os-release', str(os_release))
        self.code += '\nchown() { printf "%s\\n" "$*" >> "' + str(self.root / 'owners') + '"; }\n'
        # Keep download fixtures as shell functions; timeout itself is exercised separately.
        self.code += '\ntimeout() { [ "$1" != -k ] || shift 2; shift; "$@"; }\n'
        self.server = self.root / 'etc/snell/snell-server.conf'
        self.client = self.root / 'etc/snell/snell-client.conf'
        self.binary = self.root / 'usr/local/bin/snell-server'

    def run_shell(self, body, data='', expected=0):
        result = subprocess.run(['bash', '-c', self.code + '\n' + body], input=data,
                                text=True, capture_output=True, timeout=8)
        self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
        return result

    def server_config(self, mode='unshaped', port=40443):
        self.server.write_text(f'[snell-server]\nlisten = [::]:{port},0.0.0.0:{port}\n'
                               f'psk = ChangedSecret=123456789\nmode = {mode}\n')

    def test_systems_and_architectures(self):
        for system in ['debian', 'ubuntu', 'alpine', 'centos']:
            (self.root / 'os-release').write_text(f'ID={system}\n')
            want = system if system != 'centos' else 'unknown'
            self.assertEqual(self.run_shell('get_system_type').stdout.strip(), want)
        for machine, want in [('x86_64', 'amd64'), ('amd64', 'amd64'),
                              ('arm64', 'aarch64'), ('aarch64', 'aarch64')]:
            self.assertEqual(self.run_shell(f'uname() {{ echo {machine}; }}; get_architecture').stdout.strip(), want)
        self.run_shell('uname() { echo armv7l; }; get_architecture', expected=1)

    def test_ip_validation(self):
        for address in ['8.218.121.94', '203.0.113.7', '192.168.1.10', '223.255.255.254']:
            self.run_shell(f'valid_ipv4 {address}')
        for address in ['', '0.0.0.0', '0.1.2.3', '127.0.0.1', '127.255.255.254',
                        '0127.0.0.1', '169.254.2.3', '224.0.0.1', '239.255.255.250',
                        '240.0.0.1', '255.255.255.255', '999.1.1.1', '1.2.3',
                        '<html>error</html>', '1.2.3.4,psk=x']:
            self.run_shell('valid_ipv4 "$candidate"', expected=1) if address == '' else self.run_shell(
                'candidate=' + repr(address) + '; valid_ipv4 "$candidate"', expected=1)

    def test_ip_fallback_and_manual_input(self):
        result = self.run_shell('''fetch_text() {
            case "$1" in
                *amazonaws*) echo '<html>error</html>' ;;
                *ipify*) printf '203.0.113.8\\r\\n' ;;
                *) return 1 ;;
            esac
        }; get_public_ip''')
        self.assertEqual(result.stdout.strip(), '203.0.113.8')
        result = self.run_shell('fetch_text() { return 1; }; get_public_ip', '999.2.3.4\n203.0.113.9\n')
        self.assertEqual(result.stdout.strip(), '203.0.113.9')
        self.run_shell('fetch_text() { return 1; }; get_public_ip', expected=1)
        self.assertEqual(self.run_shell('fetch_text() { return 1; }; get_country 203.0.113.1').stdout.strip(), 'Snell')

    def test_network_requests_have_bounds(self):
        args = self.run_shell('curl() { printf "%s\\n" "$@"; }; fetch_text https://example.com').stdout.splitlines()
        self.assertIn('--connect-timeout', args)
        self.assertIn('--max-time', args)
        self.assertEqual(args[-1], 'https://example.com')

    def test_client_configuration_is_regenerated(self):
        self.server_config()
        self.client.write_text('HK = snell, 203.0.113.1, 12345, psk=OldSecret, version=6, mode=default\n')
        result = self.run_shell('fetch_text() { return 99; }; refresh_client_config')
        self.assertIn('203.0.113.1, 40443, psk=ChangedSecret=123456789', result.stdout)
        self.assertIn('mode=unshaped', result.stdout)
        self.assertNotIn('OldSecret', self.client.read_text())
        self.assertEqual(self.client.stat().st_mode & 0o777, 0o600)
        self.assertIn('root:root', (self.root / 'owners').read_text())

    def test_bad_server_config_does_not_replace_client(self):
        self.client.write_text('keep')
        self.server_config(port=99999)
        self.run_shell('refresh_client_config', expected=1)
        self.assertEqual(self.client.read_text(), 'keep')
        self.server_config(mode='invalid')
        self.run_shell('refresh_client_config', expected=1)
        self.assertEqual(self.client.read_text(), 'keep')

    def test_missing_mode_defaults_and_comments(self):
        self.server.write_text('[other]\npsk=wrong\n[snell-server]\n'
                               ' listen = 0.0.0.0:45678 # note\n psk = CorrectSecret=123456\n')
        self.client.write_text('HK = snell, 203.0.113.1, 1, psk=old\n')
        output = self.run_shell('refresh_client_config').stdout
        self.assertIn('45678, psk=CorrectSecret=123456', output)
        self.assertIn('mode=default', output)

    def test_private_permissions_for_existing_files(self):
        self.server_config()
        self.client.write_text('secret')
        self.run_shell('secure_config_files')
        self.assertEqual(self.server.stat().st_mode & 0o777, 0o640)
        self.assertEqual(self.client.stat().st_mode & 0o777, 0o600)
        self.assertIn('root:snell', (self.root / 'owners').read_text())

    def test_failed_write_preserves_previous_file(self):
        destination = self.root / 'result'
        destination.write_text('previous')
        for failure in ['cat', 'chown', 'chmod', 'mv']:
            body = f'{failure}() {{ return 1; }}; write_file "{destination}" 600 root:root <<< new'
            self.run_shell(body, expected=1)
            self.assertEqual(destination.read_text(), 'previous')
            self.assertEqual(list(self.root.glob('result.tmp.*')), [])

    def test_choose_port_retries_occupied_ipv4_and_ipv6(self):
        counter = self.root / 'counter'
        result = self.run_shell(f'''
ss() {{ printf 'LISTEN 0 128 0.0.0.0:31000 0.0.0.0:*\\nLISTEN 0 128 [::]:31001 [::]:*\\n'; }}
shuf() {{ local n=31000; [ ! -f '{counter}' ] || read -r n < '{counter}'; echo $((n+1)) > '{counter}'; echo "$n"; }}
choose_port
''')
        self.assertEqual(result.stdout.strip(), '31002')
        self.run_shell('ss() { return 1; }; choose_port', expected=1)
        self.run_shell('ss() { echo "LISTEN 0 128 [::]:31000 [::]:*"; }; shuf() { echo 31000; }; choose_port', expected=1)

    def test_binary_failures_keep_installed_binary(self):
        self.binary.write_text('original')
        for failure in ['download', 'unzip', 'binary', 'rename']:
            download = 'return 1' if failure == 'download' else ':'
            extract = 'return 1' if failure == 'unzip' else 'printf "#!/bin/sh\\nexit %s\\n" ' + ('1' if failure == 'binary' else '0') + ' > "$5/snell-server"'
            move = 'mv() { return 1; };' if failure == 'rename' else ''
            self.run_shell(f'wget() {{ {download}; }}; unzip() {{ {extract}; }}; {move} replace_snell_binary', expected=1)
            self.assertEqual(self.binary.read_text(), 'original')
            self.assertEqual(list(self.binary.parent.glob('.snell-install.*')), [])

    def test_successful_binary_replace_without_backup(self):
        self.binary.write_text('original')
        self.run_shell('wget() { :; }; unzip() { printf "#!/bin/sh\\nexit 0\\n" > "$5/snell-server"; }; replace_snell_binary')
        self.assertTrue(self.binary.read_text().startswith('#!/bin/sh'))
        self.assertEqual([p.name for p in self.binary.parent.iterdir()], ['snell-server'])

    def test_failed_restart_not_reported_as_update_success(self):
        self.binary.write_text('original')
        result = self.run_shell('''check_snell_running() { return 0; }
install_required_packages() { :; }; secure_config_files() { :; }
configure_log_rotation() { :; }; replace_snell_binary() { :; }; restart_snell() { return 1; }
update_snell''', expected=1)
        self.assertNotIn('更新成功', result.stdout)

    def test_install_file_failure_stops_before_start(self):
        for failed_name in ['snell-server.conf', 'snell.service', 'snell']:
            system = 'alpine' if failed_name == 'snell' else 'debian'
            result = self.run_shell(f'''
get_system_type() {{ echo {system}; }}
install_required_packages() {{ :; }}; replace_snell_binary() {{ :; }}; choose_port() {{ echo 32000; }}
id() {{ :; }}
write_file() {{ command cat >/dev/null; [ "${{1##*/}}" != '{failed_name}' ]; }}
systemctl() {{ :; }}; rc-update() {{ :; }}
configure_log_rotation() {{ :; }}; restart_snell() {{ echo UNEXPECTED_START; }}
install_snell''', expected=1)
            self.assertNotIn('UNEXPECTED_START', result.stdout)
            self.assertNotIn('安装成功', result.stdout)

    def test_menu_eof_exits_without_loop(self):
        result = self.run_shell('check_root() { :; }; clear() { :; }; check_snell_installed() { return 1; }; check_snell_running() { return 1; }; main')
        self.assertEqual(result.stdout.count('=== Snell 管理工具 ==='), 1)
        result = self.run_shell('check_root() { :; }; clear() { :; }; check_snell_installed() { return 1; }; check_snell_running() { return 1; }; main', 'invalid\n')
        self.assertEqual(result.stdout.count('=== Snell 管理工具 ==='), 1)

    def test_ctrl_c_returns_from_live_logs(self):
        log = self.root / 'var/log/snell.log'
        log.write_text('LOG_READY\n')
        runner = self.root / 'runner.sh'
        runner.write_text(self.code + '\nget_system_type() { echo alpine; }; show_logs follow; echo BACK_TO_MENU\n')
        pid, fd = pty.fork()
        if pid == 0:
            os.execlp('bash', 'bash', str(runner))
        output = b''
        try:
            deadline = time.monotonic() + 5
            while b'LOG_READY' not in output and time.monotonic() < deadline:
                if select.select([fd], [], [], 0.1)[0]:
                    output += os.read(fd, 4096)
            self.assertIn(b'LOG_READY', output)
            os.write(fd, b'\x03')
            while b'BACK_TO_MENU' not in output and time.monotonic() < deadline:
                if select.select([fd], [], [], 0.1)[0]:
                    try:
                        output += os.read(fd, 4096)
                    except OSError:
                        break
            self.assertIn(b'BACK_TO_MENU', output)
        finally:
            try:
                os.killpg(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            os.waitpid(pid, 0)
            os.close(fd)

    def test_log_rotation_setup_and_uninstall(self):
        self.run_shell('get_system_type() { echo alpine; }; rc-update() { :; }; rc-service() { :; }; configure_log_rotation')
        config = self.root / 'etc/snell/logrotate.conf'
        cron = self.root / 'etc/periodic/hourly/snell-logrotate'
        self.assertIn('size 1M', config.read_text())
        self.assertIn('rotate 3', config.read_text())
        self.assertIn('copytruncate', config.read_text())
        self.assertEqual(cron.stat().st_mode & 0o777, 0o755)
        subprocess.run(['sh', '-n', str(cron)], check=True)
        self.binary.write_text('original')
        self.run_shell('get_system_type() { echo alpine; }; rc-service() { [ "$2" != status ] || return 3; }; rc-update() { :; }; uninstall_snell')
        self.assertFalse(cron.exists())
        self.assertFalse(config.exists())

    def test_start_and_stop_command_failures_return_nonzero(self):
        for operation in ('start_snell', 'restart_snell', 'stop_snell'):
            result = self.run_shell('service_action() { return 1; }; show_logs() { echo FAILURE_LOG; }; ' + operation, expected=1)
            self.assertNotIn('成功', result.stdout)
            self.assertIn('FAILURE_LOG', result.stderr)

    def test_start_checks_survival_and_reports_early_exit(self):
        result = self.run_shell('''service_action() { :; }; sleep() { :; }; show_logs() { :; }
checks=0
check_snell_running() { checks=$((checks+1)); [ "$checks" -eq 1 ]; }
start_snell''', expected=1)
        self.assertNotIn('启动成功', result.stdout)

    def test_start_allows_delayed_start_and_requires_stable_status(self):
        result = self.run_shell('''service_action() { :; }; sleep() { :; }
checks=0
check_snell_running() { checks=$((checks+1)); [ "$checks" -ge 3 ]; }
start_snell && printf 'checks=%s\\n' "$checks"''')
        self.assertIn('启动成功', result.stdout)
        self.assertIn('checks=5', result.stdout)

    def test_stop_requires_explicit_stopped_status(self):
        for state in ('active', 'activating', 'deactivating', 'reloading', '', 'unknown'):
            result = self.run_shell(f'''service_action() {{ :; }}; sleep() {{ :; }}; show_logs() {{ :; }}
systemctl() {{ echo '{state}'; }}; stop_snell''', expected=1)
            self.assertNotIn('停止成功', result.stdout)
        self.run_shell('service_action() { :; }; sleep() { :; }; show_logs() { :; }; systemctl() { return 1; }; stop_snell', expected=1)
        for state in ('inactive', 'failed'):
            self.run_shell(f'service_action() {{ :; }}; systemctl() {{ echo {state}; }}; stop_snell')

    def test_openrc_stopped_status_codes(self):
        for code in (0, 1, 3, 4, 8, 16, 32, 64):
            self.run_shell(f'get_system_type() {{ echo alpine; }}; rc-service() {{ return {code}; }}; check_snell_stopped', expected=0 if code == 3 else 1)

    def test_uninstall_stops_transitional_services_before_deleting(self):
        for system in ('debian', 'alpine'):
            self.binary.write_text('old-core'); self.server_config()
            result = self.run_shell(f'''get_system_type() {{ echo {system}; }}
check_snell_running() {{ return 1; }}
service_action() {{ echo ACTION:"$1"; state=stopped; }}
check_snell_stopped() {{ [ "$state" = stopped ]; }}
rc-update() {{ :; }}; systemctl() {{ :; }}
uninstall_snell''')
            self.assertIn('ACTION:stop', result.stdout)
            self.assertFalse(self.binary.exists()); self.assertFalse(self.server.exists())
            self.server.parent.mkdir(parents=True, exist_ok=True)

    def test_uninstall_keeps_files_if_stop_fails_or_cannot_be_confirmed(self):
        self.binary.write_text('old-core'); self.server_config()
        for command_result in (0, 1):
            result = self.run_shell(f'''service_action() {{ return {command_result}; }}
check_snell_stopped() {{ return 1; }}; sleep() {{ :; }}; show_logs() {{ :; }}
systemctl() {{ echo UNEXPECTED_DISABLE; }}; uninstall_snell''', expected=1)
            self.assertNotIn('UNEXPECTED_DISABLE', result.stdout)
            self.assertEqual(self.binary.read_text(), 'old-core')
            self.assertTrue(self.server.exists())

    def test_update_preserves_stopped_or_running_state_and_credentials(self):
        for running in (0, 1):
            self.binary.write_text('old-core'); self.server_config()
            before = self.server.read_bytes()
            result = self.run_shell(f'''check_snell_running() {{ return {0 if running else 1}; }}
check_snell_stopped() {{ return {1 if running else 0}; }}
install_required_packages() {{ :; }}; configure_log_rotation() {{ :; }}
replace_snell_binary() {{ echo REPLACED; }}; restart_snell() {{ echo RESTARTED; }}
show_logs() {{ :; }}; refresh_client_config() {{ :; }}; update_snell''')
            self.assertIn('REPLACED', result.stdout)
            self.assertEqual('RESTARTED' in result.stdout, bool(running))
            self.assertEqual(self.server.read_bytes(), before)

    def test_update_does_not_modify_files_on_unknown_or_transitional_state(self):
        self.binary.write_text('old-core'); self.server_config()
        result = self.run_shell('''check_snell_running() { return 1; }; check_snell_stopped() { return 1; }
install_required_packages() { echo UNEXPECTED_DEPENDENCIES; }
replace_snell_binary() { echo UNEXPECTED_REPLACE; }; update_snell''', expected=1)
        self.assertNotIn('UNEXPECTED', result.stdout)
        self.assertEqual(self.binary.read_text(), 'old-core')

    def test_download_timeout_keeps_binary_and_cleans_staging(self):
        self.binary.write_text('old-core')
        result = self.run_shell('timeout() { printf "BOUND:%s\\n" "$*"; return 124; }; replace_snell_binary', expected=1)
        self.assertIn('BOUND:-k 5 180 wget --timeout=15 --tries=3', result.stdout)
        self.assertEqual(self.binary.read_text(), 'old-core')
        self.assertFalse(list(self.binary.parent.glob('.snell-install.*')))

    def test_real_version_probe_timeout(self):
        self.binary.write_text('#!/bin/sh\nexec sleep 30\n'); self.binary.chmod(0o755)
        start = time.monotonic()
        self.run_shell(f'unset -f timeout; snell_binary_version "{self.binary}" 0.2', expected=124)
        self.assertLess(time.monotonic() - start, 4)

    def test_invalid_saved_address_is_not_reused(self):
        self.server_config()
        self.client.write_text('HK = snell, 127.0.0.1, 12345, psk=old\n')
        result = self.run_shell('get_public_ip() { echo 203.0.113.10; }; refresh_client_config')
        self.assertIn('203.0.113.10', result.stdout)
        self.assertNotIn('127.0.0.1', result.stdout)

    @unittest.skipUnless(shutil.which('logrotate') and os.geteuid() == 0, 'requires logrotate and root')
    def test_real_rotation_keeps_open_log_and_limits_archives(self):
        self.run_shell('get_system_type() { echo alpine; }; rc-update() { :; }; rc-service() { :; }; configure_log_rotation')
        config = self.root / 'etc/snell/logrotate.conf'
        config.write_text(config.read_text().replace('su root snell', 'su root root'))
        log = self.root / 'var/log/snell.log'
        with log.open('ab', buffering=0) as stream:
            for i in range(5):
                stream.write(b'x' * (1024 * 1024 + 1))
                subprocess.run(['logrotate', '-s', str(self.root / 'state'), str(config)], check=True, capture_output=True)
                self.assertEqual(log.stat().st_size, 0)
            stream.write(b'new log line\n')
        self.assertEqual(log.read_bytes(), b'new log line\n')
        self.assertEqual(len(list(log.parent.glob('snell.log.*'))), 3)


if __name__ == '__main__':
    unittest.main()
