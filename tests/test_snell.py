"""Offline regression tests. All installer paths are redirected to a temporary tree."""
import os
import pathlib
import pty
import select
import shlex
import signal
import subprocess
import tempfile
import time
import unittest

SOURCE = pathlib.Path(__file__).resolve().parents[1] / 'Snell.sh'


def proxy_fields(text):
    """Decode quoted proxy values independently using the standard lexer."""
    lexer = shlex.shlex(text, posix=True)
    lexer.whitespace = ','
    lexer.whitespace_split = True
    lexer.commenters = ''
    return [field.strip() for field in lexer]


class SnellTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.code = SOURCE.read_text().replace('if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then\n    main\nfi\n', '')
        for path in ['/usr/local/bin', '/etc/snell', '/etc/init.d',
                     '/etc/systemd/system', '/etc/periodic/hourly',
                     '/etc/logrotate.d', '/etc/runlevels/default', '/var/lib/logrotate', '/var/log']:
            (self.root / path.lstrip('/')).mkdir(parents=True, exist_ok=True)
            self.code = self.code.replace(path, str(self.root / path.lstrip('/')))
        os_release = self.root / 'os-release'
        os_release.write_text('ID=debian\n')
        self.code = self.code.replace('/etc/os-release', str(os_release))
        self.code = self.code.replace('/run/snell-manager.lock', str(self.root / 'manager.lock'))
        self.code += '\nchown() { printf "%s\\n" "$*" >> "' + str(self.root / 'owners') + '"; }\n'
        self.code += '\ngetent() { return 0; }\ngroupadd() { return 99; }; addgroup() { return 99; }; useradd() { return 99; }; adduser() { return 99; }\n'
        # No offline test may change packages on the host, including repair paths.
        self.code += '\napt-get() { return 99; }; apk() { return 99; }\n'
        # Keep download fixtures as shell functions; timeout itself is exercised separately.
        self.code += '\ntimeout() { [ "$1" != -k ] || shift 2; shift; "$@"; }\n'
        self.code += '\neval "$(declare -f snell_listener_pid | sed \'1s/snell_listener_pid/real_snell_listener_pid/\')"\nsnell_listener_pid() { echo 123; }\n'
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

    def test_installed_detection_uses_managed_executable_without_path_entry(self):
        self.server_config()
        self.binary.write_text('#!/bin/sh\necho snell-server v6.0.0\n')
        self.binary.chmod(0o755)
        result = self.run_shell('''PATH=/usr/bin:/bin
check_snell_installed && require_snell_config || exit 1
check_snell_running() { return 1; }; show_menu''', '0\n')
        self.assertIn('已安装', result.stdout)
        self.assertIn('3. 启动 Snell 服务', result.stdout)
        self.assertIn('v6.0.0', result.stdout)

    def test_unrelated_path_binary_and_nonexecutable_do_not_count_as_installed(self):
        unrelated = self.root / 'other-bin'
        unrelated.mkdir()
        other = unrelated / 'snell-server'
        other.write_text('#!/bin/sh\nexit 0\n')
        other.chmod(0o755)
        for state in ('missing', 'not-executable', 'directory'):
            with self.subTest(state=state):
                if state == 'not-executable':
                    self.binary.write_text('incomplete'); self.binary.chmod(0o644)
                elif state == 'directory':
                    self.binary.unlink(); self.binary.mkdir()
                self.run_shell(f'PATH="{unrelated}:/usr/bin:/bin"; check_snell_installed', expected=1)

    def test_complete_dependencies_skip_package_mutations(self):
        for system in ('debian', 'ubuntu', 'alpine'):
            with self.subTest(system=system):
                result = self.run_shell(f'''get_system_type() {{ echo {system}; }}
dpkg-query() {{ echo 'install ok installed'; }}
apt-get() {{ echo UNEXPECTED_NETWORK; return 1; }}
apk() {{ [ "$1 $2" = 'info -e' ] || {{ echo UNEXPECTED_NETWORK; return 1; }}; }}
install_required_packages''')
                self.assertIn('必要软件包已齐全', result.stdout)
                self.assertNotIn('UNEXPECTED_NETWORK', result.stdout)

    def test_missing_dependencies_only_install_missing_packages(self):
        for system in ('debian', 'ubuntu', 'alpine'):
            with self.subTest(system=system):
                result = self.run_shell(f'''get_system_type() {{ echo {system}; }}
dpkg-query() {{ case "${{@: -1}}" in curl) return 1 ;; unzip) echo 'install ok unpacked' ;; *) echo 'hold ok installed' ;; esac; }}
apt-get() {{ printf 'APT:%s\\n' "$*"; }}
apk() {{ if [ "$1" = info ]; then [ "$3" != curl ] && [ "$3" != unzip ]; else printf 'APK:%s\\n' "$*"; fi; }}
install_required_packages''')
                lines = [line for line in result.stdout.splitlines() if line.startswith(('APT:', 'APK:'))]
                if system == 'alpine':
                    self.assertEqual(lines, ['APK:add --no-cache unzip curl'])
                else:
                    self.assertEqual(lines, ['APT:-o DPkg::Lock::Timeout=120 update',
                                             'APT:-o DPkg::Lock::Timeout=120 install -y unzip curl'])

    def test_dependency_install_failure_stops_update_before_replacing_binary(self):
        self.binary.write_text('original'); self.server_config()
        for system in ('debian', 'ubuntu', 'alpine'):
            for failure in ('refresh', 'install'):
                with self.subTest(system=system, failure=failure):
                    result = self.run_shell(f'''get_system_type() {{ echo {system}; }}
check_snell_running() {{ :; }}; ipv6_available() {{ :; }}
dpkg-query() {{ return 1; }}
apt-get() {{ printf 'APT:%s\\n' "$*"; [ '{failure}' != refresh ] && [[ "$*" != *'install -y'* ]]; }}
apk() {{ [ "$1" != info ] && echo APK_INSTALL; return 1; }}
secure_config_files() {{ echo UNEXPECTED_PERMISSIONS; }}
replace_snell_binary() {{ echo UNEXPECTED_REPLACE; }}; update_snell''', expected=1)
                    self.assertNotIn('UNEXPECTED', result.stdout)
                    self.assertEqual(self.binary.read_text(), 'original')
                    if system != 'alpine' and failure == 'refresh':
                        self.assertNotIn('install -y', result.stdout)

    def test_dependency_repair_reinstalls_and_upgrades_requested_packages(self):
        for system in ('debian', 'ubuntu', 'alpine'):
            result = self.run_shell(f'''get_system_type() {{ echo {system}; }}
dpkg-query() {{ echo 'install ok installed'; }}
apt-get() {{ printf 'APT:%s\\n' "$*"; }}
apk() {{ printf 'APK:%s\\n' "$*"; }}
install_required_packages repair''')
            self.assertIn('fix --no-cache --reinstall --upgrade' if system == 'alpine'
                          else 'install -y --reinstall', result.stdout)
            self.assertIn('coreutils', result.stdout)
            if system == 'alpine':
                self.assertIn('gcompat libstdc++', result.stdout)

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
                               ' listen = 0.0.0.0:45678 ; note\npsk = CorrectSecret=123456\n')
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
        self.server_config()
        result = self.run_shell('''check_snell_running() { return 0; }
ipv6_available() { :; }
install_required_packages() { :; }; secure_config_files() { :; }
replace_snell_binary() { echo REPLACED; }; restart_snell() { echo RESTART_REACHED; return 1; }
update_snell''', expected=1)
        self.assertIn('REPLACED', result.stdout)
        self.assertEqual(result.stdout.count('RESTART_REACHED'), 1)
        self.assertIn('新程序已替换，但重启失败', result.stdout)
        self.assertNotIn('更新成功', result.stdout)

    def test_binary_probe_repairs_dependencies_once_before_replacement(self):
        for outcome in ('recovered', 'still-broken', 'repair-failed'):
            with self.subTest(outcome=outcome):
                self.binary.write_text('original')
                result = self.run_shell(f'''wget() {{ :; }}
unzip() {{ printf '#!/bin/sh\\nexit 0\\n' > "$5/snell-server"; }}
probes=0
snell_binary_version() {{ probes=$((probes+1)); echo PROBE; [ "$probes" -gt 1 ] && [ '{outcome}' = recovered ]; }}
install_required_packages() {{ [ "$1" = repair ] || return 1; echo REPAIR; [ '{outcome}' != repair-failed ]; }}
replace_snell_binary''', expected=0 if outcome == 'recovered' else 1)
                self.assertEqual(result.stdout.count('REPAIR'), 1)
                self.assertEqual(result.stdout.count('PROBE'), 1 if outcome == 'repair-failed' else 2)
                if outcome == 'recovered':
                    self.assertTrue(self.binary.read_text().startswith('#!/bin/sh'))
                else:
                    self.assertEqual(self.binary.read_text(), 'original')
                self.assertFalse(list(self.binary.parent.glob('.snell-install.*')))

    def test_invalid_update_config_fails_before_any_changes(self):
        valid = '[snell-server]\nlisten = 0.0.0.0:40443\npsk = ValidSecret123456\nmode = default\n'
        cases = {
            'missing-file': None,
            'missing-listen': valid.replace('listen = 0.0.0.0:40443\n', ''),
            'malformed-ini': valid + 'invalid line\n',
            'missing-psk': valid.replace('psk = ValidSecret123456\n', ''),
            'short-psk': valid.replace('ValidSecret123456', 'short'),
            'invalid-mode': valid.replace('mode = default', 'mode = wrong'),
            'invalid-dns': valid + 'dns-ip-preference = wrong\n',
            'ambiguous-edit-section': valid + '[snell-server]\n',
        }
        for listener in ('0.0.0.0:0', '[::]:65536', ':40443', '0.0.0.0', '::1:40443',
                         '0.0.0.0:40443,', ',0.0.0.0:40443', '0.0.0.0:40443,,[::]:40443'):
            cases[listener] = valid.replace('0.0.0.0:40443', listener)
        self.binary.write_text('original')
        self.client.write_text('existing client')
        for name, config in cases.items():
            with self.subTest(config=name):
                if config is None:
                    self.server.unlink(missing_ok=True)
                else:
                    self.server.write_text(config)
                result = self.run_shell('''check_snell_running() { :; }; ipv6_available() { :; }
install_required_packages() { echo UNEXPECTED_DEPENDENCIES; }
secure_config_files() { echo UNEXPECTED_PERMISSIONS; }
replace_snell_binary() { echo UNEXPECTED_REPLACE; }
write_openrc_service() { echo UNEXPECTED_SERVICE; }
restart_snell() { echo UNEXPECTED_RESTART; }
refresh_client_config() { echo UNEXPECTED_CLIENT; }; update_snell''', expected=1)
                self.assertNotIn('UNEXPECTED', result.stdout)
                self.assertEqual(self.binary.read_text(), 'original')
                self.assertEqual(self.client.read_text(), 'existing client')
                self.assertEqual(self.server.read_text() if self.server.exists() else None, config)

    def test_update_preflight_preserves_custom_and_ipv6_only_listeners(self):
        self.binary.write_text('original')
        for listen in ('[::1]:40443', '[2001:db8::1]:40443',
                       '192.0.2.1:40443,[2001:db8::1]:40444'):
            self.server.write_text(f'[snell-server]\nlisten = {listen}\npsk = ExampleKey #literal\n')
            before = self.server.read_bytes()
            result = self.run_shell('''check_snell_running() { return 1; }; check_snell_stopped() { :; }
install_required_packages() { :; }; replace_snell_binary() { echo REPLACED; }
restart_snell() { echo UNEXPECTED_RESTART; }
refresh_client_config() { :; }; update_snell''')
            self.assertIn('REPLACED', result.stdout)
            self.assertNotIn('UNEXPECTED', result.stdout)
            self.assertEqual(self.server.read_bytes(), before)

    def test_install_file_failure_stops_before_start(self):
        for failed_name in ['snell-server.conf', 'snell.service', 'snell']:
            self.server.unlink(missing_ok=True)
            system = 'alpine' if failed_name == 'snell' else 'debian'
            result = self.run_shell(f'''
get_system_type() {{ echo {system}; }}
install_required_packages() {{ :; }}; replace_snell_binary() {{ :; }}; choose_port() {{ echo 32000; }}
id() {{ :; }}
write_file() {{ command cat >/dev/null; [ "${{1##*/}}" != '{failed_name}' ]; }}
systemctl() {{ :; }}; rc-update() {{ :; }}
restart_snell() {{ echo UNEXPECTED_START; }}
install_snell''', expected=1)
            self.assertNotIn('UNEXPECTED_START', result.stdout)
            self.assertNotIn('安装成功', result.stdout)

    def test_menu_eof_exits_without_loop(self):
        result = self.run_shell('check_root() { :; }; clear() { :; }; check_snell_installed() { return 1; }; check_snell_running() { return 1; }; main')
        self.assertEqual(result.stdout.count('=== Snell 管理工具 ==='), 1)
        result = self.run_shell('check_root() { :; }; clear() { :; }; check_snell_installed() { return 1; }; check_snell_running() { return 1; }; main', 'invalid\n')
        self.assertEqual(result.stdout.count('=== Snell 管理工具 ==='), 1)

    def test_ctrl_c_returns_from_live_logs(self):
        journal = self.binary.parent / 'journalctl'
        journal.write_text('#!/bin/sh\necho LOG_READY\nexec sleep 30\n')
        journal.chmod(0o755)
        runner = self.root / 'runner.sh'
        runner.write_text(self.code + f'\nPATH="{journal.parent}:$PATH"; show_logs follow; echo BACK_TO_MENU\n')
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

    def test_alpine_logs_return_immediately_with_diagnostic_guidance(self):
        for mode in ('follow', 'recent'):
            result = self.run_shell(f'''get_system_type() {{ echo alpine; }}
tail() {{ echo UNEXPECTED_READ; return 1; }}
journalctl() {{ echo UNEXPECTED_READ; return 1; }}
show_logs {mode}''')
            self.assertIn('已关闭 Snell 日志文件输出', result.stdout)
            self.assertIn('snell-server -l info -c', result.stdout)
            self.assertNotIn('UNEXPECTED_READ', result.stdout)

    def test_uninstall_removes_only_snell_logging_files(self):
        (self.root / 'etc/init.d/snell').write_text('service')
        owned = ['etc/snell/logrotate.conf', 'etc/periodic/hourly/snell-logrotate',
                 'var/lib/logrotate/snell.status', 'var/log/snell.log',
                 'var/log/snell.log.1', 'var/log/snell.log.2.gz']
        shared = ['etc/periodic/hourly/other', 'var/lib/logrotate/status',
                  'var/log/other.log', 'etc/init.d/crond']
        for name in owned + shared:
            (self.root / name).write_text('keep-until-stopped')
        self.binary.write_text('original')
        self.run_shell('get_system_type() { echo alpine; }; rc-service() { [ "$2" != status ] || return 3; }; rc-update() { :; }; uninstall_snell')
        for name in owned:
            self.assertFalse((self.root / name).exists(), name)
        for name in shared:
            self.assertEqual((self.root / name).read_text(), 'keep-until-stopped', name)

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
check_snell_running() { checks=$((checks+1)); printf 'checks=%s\\n' "$checks"; [ "$checks" -ge 3 ]; }
start_snell''')
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
            service = self.root / ('etc/init.d/snell' if system == 'alpine' else 'etc/systemd/system/snell.service')
            service.write_text('service')
            self.binary.write_text('old-core'); self.server_config()
            result = self.run_shell(f'''get_system_type() {{ echo {system}; }}
ipv6_available() {{ :; }}
check_snell_running() {{ return 1; }}
service_action() {{ echo ACTION:"$1"; state=stopped; }}
check_snell_stopped() {{ [ "$state" = stopped ]; }}
rc-update() {{ :; }}; systemctl() {{ :; }}
uninstall_snell''')
            self.assertIn('ACTION:stop', result.stdout)
            self.assertFalse(self.binary.exists()); self.assertFalse(self.server.exists())
            self.server.parent.mkdir(parents=True, exist_ok=True)

    def test_uninstall_keeps_files_if_stop_fails_or_cannot_be_confirmed(self):
        (self.root / 'etc/systemd/system/snell.service').write_text('service')
        self.binary.write_text('old-core'); self.server_config()
        for command_result in (0, 1):
            result = self.run_shell(f'''service_action() {{ return {command_result}; }}
check_snell_stopped() {{ return 1; }}; sleep() {{ :; }}; show_logs() {{ :; }}
systemctl() {{ echo UNEXPECTED_DISABLE; }}; uninstall_snell''', expected=1)
            self.assertNotIn('UNEXPECTED_DISABLE', result.stdout)
            self.assertEqual(self.binary.read_text(), 'old-core')
            self.assertTrue(self.server.exists())

    def test_update_preserves_stopped_or_running_state_and_credentials(self):
        for system in ('debian', 'ubuntu', 'alpine'):
            for running in (0, 1):
                self.binary.write_text('old-core'); self.server_config()
                before = self.server.read_bytes()
                log = self.root / 'var/log/snell.log'
                cron = self.root / 'etc/periodic/hourly/snell-logrotate'
                service = self.root / 'etc/init.d/snell'
                for path in (log, cron, service):
                    path.write_text('old-content')
                result = self.run_shell(f'''get_system_type() {{ echo {system}; }}
ipv6_available() {{ :; }}
check_snell_running() {{ return {0 if running else 1}; }}
check_snell_stopped() {{ return {1 if running else 0}; }}
install_required_packages() {{ :; }}
replace_snell_binary() {{ echo REPLACED; }}
restart_snell() {{ [ -f '{log}' ] || return 1; echo RESTARTED; }}
show_logs() {{ :; }}; refresh_client_config() {{ :; }}; update_snell''')
                self.assertIn('REPLACED', result.stdout)
                self.assertEqual('RESTARTED' in result.stdout, bool(running))
                self.assertEqual(self.server.read_bytes(), before)
                if system == 'alpine':
                    self.assertIn('output_log="/dev/null"', service.read_text())
                    self.assertIn('error_log="/dev/null"', service.read_text())
                    self.assertFalse(log.exists())
                    self.assertFalse(cron.exists())
                else:
                    for path in (log, cron, service):
                        self.assertEqual(path.read_text(), 'old-content')

    def test_alpine_update_service_write_failure_is_not_success(self):
        self.binary.write_text('old-core'); self.server_config()
        result = self.run_shell('''get_system_type() { echo alpine; }
check_snell_running() { return 0; }; install_required_packages() { :; }
replace_snell_binary() { :; }; write_file() { cat >/dev/null; return 1; }
restart_snell() { echo UNEXPECTED_RESTART; }; update_snell''', expected=1)
        self.assertNotIn('UNEXPECTED_RESTART', result.stdout)
        self.assertNotIn('更新成功', result.stdout)

    def test_alpine_install_does_not_create_log_or_cron_job(self):
        result = self.run_shell('''get_system_type() { echo alpine; }
install_required_packages() { :; }; replace_snell_binary() { :; }
choose_port() { echo 32000; }; id() { :; }; rc-update() { :; }
restart_snell() { :; }; refresh_client_config() { :; }; install_snell''')
        self.assertIn('安装成功', result.stdout)
        self.assertTrue(self.server.exists())
        self.assertIn('error_log="/dev/null"', (self.root / 'etc/init.d/snell').read_text())
        self.assertFalse(list((self.root / 'var/log').iterdir()))
        self.assertFalse(list((self.root / 'etc/periodic/hourly').iterdir()))
        self.assertFalse((self.root / 'etc/snell/logrotate.conf').exists())

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

    def test_openrc_service_discards_stdout_and_stderr(self):
        self.run_shell('write_openrc_service')
        service = self.root / 'etc/init.d/snell'
        subprocess.run(['sh', '-n', str(service)], check=True)
        self.assertEqual(service.stat().st_mode & 0o777, 0o755)
        self.assertNotIn('start_pre', service.read_text())
        # Execute a noisy process with the destinations from the generated service.
        self.binary.write_text('#!/bin/sh\necho STDOUT_LOG\necho STDERR_LOG >&2\n')
        self.binary.chmod(0o755)
        result = self.run_shell(f'''. "{service}"
[ "$output_log" = /dev/null ] && [ "$error_log" = /dev/null ] || exit 1
"$command" >"$output_log" 2>"$error_log"''')
        self.assertEqual(result.stdout + result.stderr, '')
        self.assertFalse(list((self.root / 'var/log').iterdir()))

    def prepare_mode_switch(self, mode='default'):
        self.server_config(mode=mode)
        self.client.write_text('HK = snell, 203.0.113.1, 40443, psk=OldSecret, version=6, mode=default\n')
        return self.server.read_bytes(), self.client.read_bytes()

    def assert_mode_files_unchanged(self, before):
        self.assertEqual((self.server.read_bytes(), self.client.read_bytes()), before)
        self.assertFalse(list(self.server.parent.glob('*.tmp.*')))

    def test_mode_switch_menu_keeps_existing_labels_and_dispatches_nine(self):
        result = self.run_shell('''check_root() { :; }; clear() { :; }
check_snell_installed() { return 1; }; check_snell_running() { return 1; }
change_snell_config() { echo CONFIG_MENU_CALLED; }; main''', '9\n\n0\n')
        self.assertIn('7. 查看 Snell 日志', result.stdout)
        self.assertIn('8. 查看 Snell 配置', result.stdout)
        self.assertIn('9. 更改 Snell 配置', result.stdout)
        self.assertIn('CONFIG_MENU_CALLED', result.stdout)

    def test_mode_switch_all_modes_on_both_service_managers(self):
        for system in ('debian', 'ubuntu', 'alpine'):
            for running in (False, True):
                for selection, mode in [('1', 'default'), ('2', 'unshaped'), ('3', 'unsafe-raw')]:
                    with self.subTest(system=system, running=running, mode=mode):
                        self.prepare_mode_switch('unshaped' if mode == 'default' else 'default')
                        result = self.run_shell(f'''get_system_type() {{ echo {system}; }}
check_snell_installed() {{ :; }}; sleep() {{ :; }}
systemctl() {{
    case "$1" in
        is-active) return {0 if running else 3} ;;
        show) echo inactive ;;
        reset-failed) return 0 ;;
        restart) echo RESTARTED ;;
        *) return 99 ;;
    esac
}}
rc-service() {{
    case "$2" in
        status) return {0 if running else 3} ;;
        restart) echo RESTARTED ;;
        *) return 99 ;;
    esac
}}
fetch_text() {{ echo UNEXPECTED_LOOKUP >&2; return 1; }}
switch_snell_mode''', selection + '\n')
                        self.assertIn(f'mode = {mode}\n', self.server.read_text())
                        self.assertIn('listen = [::]:40443,0.0.0.0:40443', self.server.read_text())
                        self.assertIn('psk = ChangedSecret=123456789', self.server.read_text())
                        self.assertIn(f'mode={mode}, reuse=true', self.client.read_text())
                        self.assertIn('HK = snell, 203.0.113.1, 40443, psk=ChangedSecret=123456789', result.stdout)
                        self.assertEqual('RESTARTED' in result.stdout, running)
                        self.assertNotIn('UNEXPECTED_LOOKUP', result.stderr)
                        self.assertEqual(self.server.stat().st_mode & 0o777, 0o640)
                        self.assertEqual(self.client.stat().st_mode & 0o777, 0o600)
                        self.assertEqual(sorted(p.name for p in self.server.parent.iterdir()),
                                         ['snell-client.conf', 'snell-server.conf'])

    def test_mode_switch_cancellation_and_invalid_input_keep_files(self):
        for data, expected in [('', 0), ('\n', 0), ('0\n', 0), ('9\n', 1), ('2; touch bad\n', 1)]:
            before = self.prepare_mode_switch()
            result = self.run_shell('''check_snell_installed() { :; }
check_snell_running() { echo UNEXPECTED_SERVICE; return 0; }
switch_snell_mode''', data, expected=expected)
            self.assert_mode_files_unchanged(before)
            self.assertNotIn('UNEXPECTED_SERVICE', result.stdout)

    def test_mode_switch_rejects_uninstalled_or_missing_config(self):
        self.run_shell('check_snell_installed() { return 1; }; switch_snell_mode', '1\n', expected=1)
        self.run_shell('check_snell_installed() { :; }; switch_snell_mode', '1\n', expected=1)

    def test_mode_switch_same_mode_refreshes_client_without_restart(self):
        before = self.prepare_mode_switch()
        result = self.run_shell('''check_snell_installed() { :; }
restart_snell() { echo UNEXPECTED_RESTART; }; switch_snell_mode''', '1\n')
        self.assertEqual(self.server.read_bytes(), before[0])
        self.assertIn('psk=ChangedSecret=123456789', self.client.read_text())
        self.assertNotIn('UNEXPECTED_RESTART', result.stdout)

    def test_mode_switch_normalizes_only_the_server_mode(self):
        for mode_lines in ('', '  mode = default ; old\nmode=default\n'):
            self.prepare_mode_switch()
            self.server.write_text('[other]\nmode = keep\n[snell-server] ; note\n'
                                   '# mode = comment\n' + mode_lines +
                                   'listen = 0.0.0.0:40443\npsk = Secret123456789\n'
                                   'dns-ip-preference = ipv4\n[extra]\nmode = keep-too\n')
            self.run_shell('''check_snell_installed() { :; }
check_snell_running() { return 1; }; check_snell_stopped() { :; }
switch_snell_mode''', '2\n')
            self.assertEqual(self.server.read_text(),
                             '[other]\nmode = keep\n[snell-server] ; note\n'
                             '# mode = comment\nlisten = 0.0.0.0:40443\npsk = Secret123456789\n'
                             'dns-ip-preference = ipv4\nmode = unshaped\n[extra]\nmode = keep-too\n')

    def test_mode_switch_invalid_config_does_not_write_files(self):
        for config in ('[other]\nmode=default\n',
                       '[snell-server]\nmode=default\n[snell-server]\nmode=default\n',
                       '[snell-server]\nmode=default\nlisten=0.0.0.0:99999\npsk=secret\n'):
            self.prepare_mode_switch()
            self.server.write_text(config)
            before = self.server.read_bytes(), self.client.read_bytes()
            self.run_shell('''check_snell_installed() { :; }
check_snell_running() { return 1; }; check_snell_stopped() { :; }
switch_snell_mode''', '2\n', expected=1)
            self.assert_mode_files_unchanged(before)

    def test_mode_switch_unknown_service_state_does_not_write_files(self):
        before = self.prepare_mode_switch()
        self.run_shell('''check_snell_installed() { :; }
check_snell_running() { return 1; }; check_snell_stopped() { return 1; }
switch_snell_mode''', '2\n', expected=1)
        self.assert_mode_files_unchanged(before)

    def test_mode_switch_cancelled_address_lookup_keeps_server_config(self):
        self.server_config(mode='default')
        before = self.server.read_bytes()
        self.run_shell('''check_snell_installed() { :; }
check_snell_running() { return 1; }; check_snell_stopped() { :; }
fetch_text() { return 1; }; switch_snell_mode''', '2\n\n', expected=1)
        self.assertEqual(self.server.read_bytes(), before)
        self.assertFalse(self.client.exists())

    def test_mode_switch_write_failure_preserves_both_configs(self):
        for destination in (self.server, self.client):
            before = self.prepare_mode_switch()
            result = self.run_shell(f'''check_snell_installed() {{ :; }}
check_snell_running() {{ return 0; }}
mv() {{ [ "${{@: -1}}" != '{destination}' ] || return 1; command mv "$@"; }}
restart_snell() {{ echo UNEXPECTED_RESTART; }}; switch_snell_mode''', '2\n', expected=1)
            self.assert_mode_files_unchanged(before)
            self.assertNotIn('UNEXPECTED_RESTART', result.stdout)

    def test_mode_switch_restart_failure_restores_configs_and_original_service(self):
        for had_client in (True, False):
            before = self.prepare_mode_switch()
            if not had_client:
                self.client.unlink()
            result = self.run_shell('''check_snell_installed() { :; }; check_snell_running() { :; }
get_public_ip() { echo 203.0.113.1; }; get_country() { echo HK; }
attempts=0
restart_snell() { attempts=$((attempts+1)); echo RESTART_MODE:$(config_value mode); [ "$attempts" -gt 1 ]; }
switch_snell_mode''', '2\n', expected=1)
            self.assertEqual(self.server.read_bytes(), before[0])
            if had_client:
                self.assertEqual(self.client.read_bytes(), before[1])
            else:
                self.assertFalse(self.client.exists())
            self.assertIn('RESTART_MODE:unshaped\nRESTART_MODE:default', result.stdout)
            self.assertIn('已恢复原配置', result.stderr)
            self.assertNotIn('模式已切换', result.stdout)

    def test_mode_switch_failed_recovery_is_reported(self):
        before = self.prepare_mode_switch()
        result = self.run_shell('''check_snell_installed() { :; }; check_snell_running() { :; }
restart_snell() { return 1; }; switch_snell_mode''', '2\n', expected=1)
        self.assert_mode_files_unchanged(before)
        self.assertIn('自动恢复未完成', result.stderr)
        self.assertNotIn('模式已切换', result.stdout)

    def test_mode_switch_interruption_restores_previous_mode(self):
        before = self.prepare_mode_switch()
        result = self.run_shell('''check_snell_installed() { :; }; check_snell_running() { :; }
attempts=0
restart_snell() {
    attempts=$((attempts+1))
    if [ "$attempts" -eq 1 ]; then kill -TERM "$BASHPID"; else return 0; fi
}
switch_snell_mode''', '2\n', expected=143)
        self.assert_mode_files_unchanged(before)
        self.assertIn('已恢复原配置', result.stderr)


    def test_configuration_submenu_routes_port_mode_and_dns(self):
        self.prepare_mode_switch()
        for selection, target in [('1', 'PORT'), ('2', 'MODE'), ('3', 'DNS')]:
            result = self.run_shell('''check_snell_installed() { :; }
change_snell_port() { echo CALL_PORT; }; switch_snell_mode() { echo CALL_MODE; }
switch_snell_dns() { echo CALL_DNS; }; change_snell_config''', selection + '\n')
            self.assertIn('1. 端口\n2. 模式\n3. DNS\n0. 返回', result.stdout)
            self.assertIn('CALL_' + target, result.stdout)
        for data, status in [('', 0), ('\n', 0), ('0\n', 0), ('8\n', 1)]:
            before = self.server.read_bytes(), self.client.read_bytes()
            self.run_shell('check_snell_installed() { :; }; change_snell_config', data, expected=status)
            self.assert_mode_files_unchanged(before)

    def test_ipv6_detection_and_automatic_listeners(self):
        disabled = self.root / 'disable_ipv6'
        addresses = self.root / 'if_inet6'
        self.code = self.code.replace('/proc/sys/net/ipv6/conf/all/disable_ipv6', str(disabled))
        self.code = self.code.replace('/proc/net/if_inet6', str(addresses))
        for flag, address, expected in [('0', '00000000000000000000000000000001 lo', True),
                                        ('1', '00000000000000000000000000000001 lo', False),
                                        ('0', '', False), ('0', None, False), (None, None, False)]:
            for path, text in [(disabled, flag), (addresses, address)]:
                if text is None:
                    path.unlink(missing_ok=True)
                else:
                    path.write_text(text + ('\n' if text else ''))
            result = self.run_shell('auto_listen_address 40443')
            self.assertEqual(result.stdout.strip(), '0.0.0.0:40443' + (',[::]:40443' if expected else ''))

    def test_port_validation_and_listener_address_preservation(self):
        for port in ('1', '65535', '00123'):
            self.run_shell(f'valid_port {port}')
        for port in ('0', '65536', '-1', '1.5', 'abc', '100000', ''):
            self.run_shell('valid_port "' + port + '"', expected=1)
        for available, expected in [(True, '0.0.0.0:12345,[::]:12345'), (False, '0.0.0.0:12345')]:
            result = self.run_shell(f'ipv6_available() {{ return {0 if available else 1}; }}; listen_with_port "0.0.0.0:40443" 12345')
            self.assertEqual(result.stdout.strip(), expected)
        self.assertEqual(self.run_shell('listen_with_port "192.0.2.5:40443,[2001:db8::1]:40444" 12345').stdout.strip(),
                         '192.0.2.5:12345,[2001:db8::1]:12345')

    def test_port_change_updates_both_configs_and_preserves_service_state(self):
        for running in (False, True):
            for ipv6 in (False, True):
                self.prepare_mode_switch(mode='unsafe-raw')
                result = self.run_shell(f'''check_snell_installed() {{ :; }}
check_snell_running() {{ return {0 if running else 1}; }}; check_snell_stopped() {{ :; }}
ipv6_available() {{ return {0 if ipv6 else 1}; }}; ss() {{ :; }}
restart_snell() {{ echo RESTARTED; }}; change_snell_port''', '01234\n')
                self.assertIn('listen = 0.0.0.0:1234' + (',[::]:1234' if ipv6 else '') + '\n', self.server.read_text())
                self.assertIn('mode = unsafe-raw', self.server.read_text())
                self.assertIn('HK = snell, 203.0.113.1, 1234, psk=ChangedSecret=123456789', self.client.read_text())
                self.assertIn('mode=unsafe-raw', self.client.read_text())
                self.assertEqual('RESTARTED' in result.stdout, running)

    def test_port_change_rejects_occupied_ports_and_ss_errors(self):
        for ss in ['echo "LISTEN 0 128 0.0.0.0:1234 0.0.0.0:*"',
                   'echo "LISTEN 0 128 [::]:1234 [::]:*"', 'return 1']:
            before = self.prepare_mode_switch()
            self.run_shell('check_snell_installed() { :; }; ss() { ' + ss + '; }; change_snell_port',
                           '1234\n', expected=1)
            self.assert_mode_files_unchanged(before)
        for data, status in [('', 0), ('\n', 0), ('65536\n', 1), ('0\n', 1), ('hello\n', 1)]:
            before = self.prepare_mode_switch()
            self.run_shell('check_snell_installed() { :; }; change_snell_port', data, expected=status)
            self.assert_mode_files_unchanged(before)

    def test_port_change_same_running_port_allows_dual_stack_upgrade(self):
        self.prepare_mode_switch()
        self.server.write_text(self.server.read_text().replace('[::]:40443,0.0.0.0:40443', '0.0.0.0:40443'))
        result = self.run_shell('''check_snell_installed() { :; }; check_snell_running() { :; }
ipv6_available() { :; }; ss() { echo UNEXPECTED_PORT_SCAN; return 1; }
restart_snell() { :; }; change_snell_port''', '40443\n')
        self.assertIn('0.0.0.0:40443,[::]:40443', self.server.read_text())
        self.assertNotIn('UNEXPECTED_PORT_SCAN', result.stdout)

    def test_same_port_preserves_server_file_and_state_and_refreshes_client(self):
        for running in (False, True):
            for listen, ipv6 in [('0.0.0.0:40443', False),
                                  ('0.0.0.0:40443, [::]:40443', True),
                                  ('[::]:40443,0.0.0.0:40443', True),
                                  ('192.0.2.1:40443,[2001:db8::1]:40443', True)]:
                with self.subTest(running=running, listen=listen):
                    self.prepare_mode_switch()
                    self.server.write_text(self.server.read_text().replace('[::]:40443,0.0.0.0:40443', listen))
                    before = self.server.read_bytes(), self.server.stat().st_mtime_ns
                    result = self.run_shell(f'''check_snell_installed() {{ :; }}
check_snell_running() {{ return {0 if running else 1}; }}; check_snell_stopped() {{ :; }}
ipv6_available() {{ return {0 if ipv6 else 1}; }}
ss() {{ echo UNEXPECTED_SCAN >&2; return 1; }}
restart_snell() {{ echo UNEXPECTED_RESTART; return 1; }}
apply_snell_setting() {{ echo UNEXPECTED_WRITE; return 1; }}; change_snell_port''', '40443\n')
                    self.assertIn('无需更改', result.stdout)
                    self.assertNotIn('UNEXPECTED', result.stdout + result.stderr)
                    self.assertEqual((self.server.read_bytes(), self.server.stat().st_mtime_ns), before)
                    self.assertIn('psk=ChangedSecret=123456789', self.client.read_text())

    def test_same_first_port_still_updates_different_secondary_port(self):
        self.prepare_mode_switch()
        self.server.write_text(self.server.read_text().replace('[::]:40443', '[::]:40444'))
        result = self.run_shell('''check_snell_installed() { :; }; check_snell_running() { :; }
ipv6_available() { :; }; ss() { :; }
restart_snell() { echo RESTARTED; }; change_snell_port''', '40444\n')
        self.assertIn('[::]:40444,0.0.0.0:40444', self.server.read_text())
        self.assertIn('RESTARTED', result.stdout)
        self.assertIn(', 40444,', self.client.read_text())

    def test_dns_modes_preserve_client_and_custom_dns_servers(self):
        modes = ['default', 'prefer-ipv4', 'prefer-ipv6', 'ipv4-only', 'ipv6-only']
        for running in (False, True):
            for selection, mode in enumerate(modes, 1):
                before = self.prepare_mode_switch('unshaped')
                current = 'prefer-ipv6' if mode == 'default' else 'default'
                with self.server.open('a') as out:
                    out.write(f'dns-ip-preference = {current}\ndns = 192.0.2.53\n')
                result = self.run_shell(f'''check_snell_installed() {{ :; }}
check_snell_running() {{ return {0 if running else 1}; }}; check_snell_stopped() {{ :; }}
get_public_ip() {{ echo UNEXPECTED_LOOKUP >&2; return 1; }}
restart_snell() {{ echo RESTARTED; }}; switch_snell_dns''', str(selection) + '\n')
                self.assertIn(f'dns-ip-preference = {mode}\n', self.server.read_text())
                self.assertIn('dns = 192.0.2.53', self.server.read_text())
                self.assertIn('mode = unshaped', self.server.read_text())
                self.assertEqual(self.client.read_bytes(), before[1])
                self.assertEqual('RESTARTED' in result.stdout, running)
                self.assertNotIn('UNEXPECTED_LOOKUP', result.stderr)

    def test_dns_switch_supports_legacy_keys_and_cancellation(self):
        for legacy in ('ipv6 = false', 'ipv-preference = prefer-ipv6'):
            self.prepare_mode_switch()
            with self.server.open('a') as out:
                out.write(legacy + '\n')
            self.run_shell('''check_snell_installed() { :; }; check_snell_running() { return 1; }
check_snell_stopped() { :; }; switch_snell_dns''', '1\n')
            self.assertIn('dns-ip-preference = default', self.server.read_text())
            self.assertNotIn('ipv-preference = ', self.server.read_text())
        for data, status in [('', 0), ('\n', 0), ('0\n', 0), ('6\n', 1), ('1\n', 0)]:
            before = self.prepare_mode_switch()
            self.run_shell('check_snell_installed() { :; }; switch_snell_dns', data, expected=status)
            self.assert_mode_files_unchanged(before)

    def test_network_setting_failures_restore_configs(self):
        for action, data in [('change_snell_port', '1234\n'), ('switch_snell_dns', '5\n')]:
            before = self.prepare_mode_switch()
            result = self.run_shell('''check_snell_installed() { :; }; check_snell_running() { :; }
ipv6_available() { :; }; ss() { :; }; attempts=0
restart_snell() { attempts=$((attempts+1)); [ "$attempts" -gt 1 ]; }
''' + action, data, expected=1)
            self.assert_mode_files_unchanged(before)
            self.assertIn('已恢复原配置', result.stderr)

    def test_auto_listen_update_preserves_custom_addresses_and_ports(self):
        for value in ['192.0.2.1:40443,[2001:db8::1]:40444', '0.0.0.0:40443,[::]:40444',
                      '[::]:40443,0.0.0.0:40443']:
            self.assertEqual(self.run_shell('ipv6_available() { :; }; auto_listen_for_existing "' + value + '"').stdout.strip(), value)
        self.assertEqual(self.run_shell('ipv6_available() { :; }; auto_listen_for_existing "0.0.0.0:40443"').stdout.strip(),
                         '0.0.0.0:40443,[::]:40443')
        self.assertEqual(self.run_shell('ipv6_available() { return 1; }; auto_listen_for_existing "0.0.0.0:40443,[::]:40443"').stdout.strip(),
                         '0.0.0.0:40443')

    def test_update_applies_dual_stack_once_and_recovers_on_restart_failure(self):
        for running, fails in [(False, False), (True, False), (True, True)]:
            self.binary.write_text('old-core')
            before = self.prepare_mode_switch()
            self.server.write_text(self.server.read_text().replace('[::]:40443,0.0.0.0:40443', '0.0.0.0:40443'))
            old_server = self.server.read_bytes()
            result = self.run_shell(f'''check_snell_running() {{ return {0 if running else 1}; }}
check_snell_stopped() {{ :; }}; ipv6_available() {{ :; }}
install_required_packages() {{ :; }}; replace_snell_binary() {{ :; }}
refresh_client_config() {{ :; }}; show_logs() {{ :; }}; attempts=0
restart_snell() {{ attempts=$((attempts+1)); echo RESTARTED; [ {1 if fails else 0} -eq 0 ] || [ "$attempts" -gt 1 ]; }}
update_snell''', expected=1 if fails else 0)
            self.assertEqual(result.stdout.count('RESTARTED'), 2 if fails else int(running))
            self.assertEqual(self.client.read_bytes(), before[1])
            if fails:
                self.assertEqual(self.server.read_bytes(), old_server)
                self.assertNotIn('更新成功', result.stdout)
            else:
                self.assertIn('0.0.0.0:40443,[::]:40443', self.server.read_text())

    def test_repeat_install_preserves_existing_configuration_and_binary(self):
        before = self.prepare_mode_switch('unsafe-raw')
        self.binary.write_text('installed-core')
        self.binary.chmod(0o755)
        (self.root / 'etc/systemd/system/snell.service').write_text('service')
        result = self.run_shell('''snell_service_enabled() { :; }
install_required_packages() { echo UNEXPECTED_CHANGE; }
replace_snell_binary() { echo UNEXPECTED_CHANGE; }; restart_snell() { echo UNEXPECTED_CHANGE; }
install_snell''')
        self.assert_mode_files_unchanged(before)
        self.assertEqual(self.binary.read_text(), 'installed-core')
        self.assertIn('已取消重复安装', result.stdout)
        self.assertNotIn('UNEXPECTED_CHANGE', result.stdout)
        self.assertNotIn('安装成功', result.stdout)

    def test_install_and_update_directory_permissions_ignore_umask(self):
        self.server.parent.rmdir()
        self.run_shell('''umask 077
install_required_packages() { :; }; replace_snell_binary() { :; }; choose_port() { echo 32000; }
id() { :; }; systemctl() { :; }; restart_snell() { :; }; show_logs() { :; }
get_public_ip() { echo 203.0.113.1; }; get_country() { echo Test; }; install_snell''')
        self.assertEqual(self.server.parent.stat().st_mode & 0o777, 0o750)
        self.assertEqual(self.server.stat().st_mode & 0o777, 0o640)
        self.assertEqual(self.client.stat().st_mode & 0o777, 0o600)
        self.assertIn('root:snell ' + str(self.server.parent), (self.root / 'owners').read_text())
        self.server.parent.chmod(0o700)
        self.run_shell('secure_config_files')
        self.assertEqual(self.server.parent.stat().st_mode & 0o777, 0o750)

    def test_export_selects_ipv4_listener_instead_of_first_listener(self):
        self.prepare_mode_switch()
        for listen, expected in [('[::]:41000,0.0.0.0:42000', '42000'),
                                 ('0.0.0.0:42000,[::]:41000', '42000'),
                                 ('[::]:41000,192.168.1.2:43000', '43000'),
                                 ('0.0.0.0:42000,203.0.113.1:44000', '44000')]:
            self.server.write_text('[snell-server]\nlisten = ' + listen + '\npsk = TestSecret123456\n')
            self.run_shell('get_public_ip() { echo UNEXPECTED; return 1; }; refresh_client_config')
            self.assertEqual(self.client.read_text().split(',')[2].strip(), expected)

    def test_ambiguous_or_ipv6_only_listener_keeps_existing_client(self):
        for listen in ('[::]:41000', '192.168.1.2:42000,192.168.1.3:43000'):
            self.prepare_mode_switch()
            before = self.client.read_bytes()
            self.server.write_text('[snell-server]\nlisten = ' + listen + '\npsk = TestSecret123456\n')
            self.run_shell('refresh_client_config', expected=1)
            self.assertEqual(self.client.read_bytes(), before)

    def test_concurrent_operations_are_rejected_then_can_retry(self):
        self.prepare_mode_switch('default')
        ready, release = self.root / 'ready', self.root / 'release'
        body = f'''check_snell_installed() {{ :; }}; check_snell_running() {{ return 1; }}
check_snell_stopped() {{ :; }}; ipv6_available() {{ :; }}; ss() {{ :; }}
eval "$(declare -f write_file | sed '1s/write_file/original_write_file/')"
write_file() {{
    if [ "$1" = '{self.server}' ]; then
        touch '{ready}'
        while [ ! -f '{release}' ]; do sleep .02; done
    fi
    original_write_file "$@"
}}
change_snell_port'''
        process = subprocess.Popen(['bash', '-c', self.code + '\n' + body],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            process.stdin.write('33333\n'); process.stdin.flush(); process.stdin.close(); process.stdin = None
            deadline = time.monotonic() + 3
            while not ready.exists() and time.monotonic() < deadline:
                time.sleep(.02)
            self.assertTrue(ready.exists())
            for action in ('switch_snell_mode', 'switch_snell_dns', 'change_snell_port',
                           'refresh_client_config', 'install_snell', 'update_snell',
                           'uninstall_snell', 'start_snell', 'stop_snell', 'restart_snell'):
                result = self.run_shell(action, '2\n', expected=1)
                self.assertIn('另一个 Snell 管理操作', result.stderr)
            release.touch()
            stdout, stderr = process.communicate(timeout=5)
            self.assertEqual(process.returncode, 0, stdout + stderr)
            self.run_shell('''check_snell_installed() { :; }; check_snell_running() { return 1; }
check_snell_stopped() { :; }; switch_snell_mode''', '2\n')
            self.assertIn('mode = unshaped', self.server.read_text())
            self.assertIn('33333', self.server.read_text())
            self.assertIn('33333', self.client.read_text())
        finally:
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()

    def test_operation_lock_released_after_failure_and_signal(self):
        self.run_shell('with_snell_lock false', expected=1)
        self.run_shell('with_snell_lock true')
        self.run_shell('terminate_self() { kill -TERM "$BASHPID"; }; with_snell_lock terminate_self', expected=143)
        self.run_shell('with_snell_lock true')

    def test_service_process_does_not_inherit_operation_lock(self):
        result = self.run_shell('''get_system_type() { echo alpine; }
rc-service() {
    [ ! -e "/proc/$BASHPID/fd/$SNELL_LOCK_FD" ] || return 1
    sleep 1 >/dev/null 2>&1 &
}
with_snell_lock service_action start && with_snell_lock true''')
        self.assertNotIn('另一个', result.stderr)

    def test_start_rejects_supervisor_without_healthy_child(self):
        result = self.run_shell('''service_action() { :; }; sleep() { :; }; show_logs() { :; }
check_snell_running() { :; }; snell_listener_pid() { return 1; }; start_snell''', expected=1)
        self.assertNotIn('启动成功', result.stdout)

    def test_start_requires_same_pid_across_successive_checks(self):
        counter = self.root / 'pid_counter'
        result = self.run_shell(f'''service_action() {{ :; }}; sleep() {{ :; }}; show_logs() {{ :; }}
check_snell_running() {{ :; }}
snell_listener_pid() {{ local n=100; [ ! -f '{counter}' ] || read -r n < '{counter}'; echo $((n+1)) > '{counter}'; echo "$n"; }}
start_snell''', expected=1)
        self.assertNotIn('启动成功', result.stdout)

    def test_listener_health_checks_all_families_and_service_pid(self):
        self.server_config()
        for ipv4_pid, ipv6_pid, binary_ok, expected in [(123, 123, True, 0), (123, 456, True, 1),
                                                      (456, 123, True, 1), (123, 0, True, 1),
                                                      (123, 123, False, 1)]:
            body = f'''snell_service_pid() {{ echo 123; }}
readlink() {{ echo '{self.binary if binary_ok else "/other/program"}'; }}
ss() {{
    if [ "$2" = -4 ]; then echo 'LISTEN 0 128 0.0.0.0:40443 0.0.0.0:* users:(("snell-server",pid={ipv4_pid},fd=4))'
    elif [ {ipv6_pid} -gt 0 ]; then echo 'LISTEN 0 128 [::]:40443 [::]:* users:(("snell-server",pid={ipv6_pid},fd=5))'
    fi
}}
real_snell_listener_pid'''
            self.run_shell(body, expected=expected)

    def test_listener_health_recognizes_gcompat_only_with_mapped_snell(self):
        self.server_config()
        maps = self.root / 'process-maps'
        self.code = self.code.replace('/proc/$pid/maps', str(maps))
        for system, loader, mapped, permissions, expected in [
                ('alpine', '/lib/ld-musl-x86_64.so.1', self.binary, 'r-xp', 0),
                ('alpine', '/lib/ld-musl-aarch64.so.1', self.binary, 'r-xp', 0),
                ('alpine', '/lib/ld-musl-x86_64.so.1', '/other/program', 'r-xp', 1),
                ('alpine', '/lib/ld-musl-x86_64.so.1', self.binary, 'r--p', 1),
                ('debian', '/lib/ld-musl-x86_64.so.1', self.binary, 'r-xp', 1)]:
            maps.write_text(f'1000-2000 {permissions} 00000000 00:01 123 {mapped}\n')
            self.run_shell(f'''get_system_type() {{ echo {system}; }}
snell_service_pid() {{ echo 123; }}
readlink() {{ echo {loader}; }}
ss() {{ echo 'LISTEN 0 128 *:40443 *:* users:(("ld-musl",pid=123,fd=4))'; }}
real_snell_listener_pid''', expected=expected)

    def test_partial_install_can_retry_after_core_download(self):
        setup = f'''install_required_packages() {{ :; }}; id() {{ :; }}
replace_snell_binary() {{ echo DOWNLOAD >> '{self.root / 'downloads'}'; printf '#!/bin/sh\\nexit 0\\n' > '{self.binary}'; chmod 755 '{self.binary}'; }}
systemctl() {{ :; }}; restart_snell() {{ :; }}; show_logs() {{ :; }}
get_public_ip() {{ echo 203.0.113.1; }}; get_country() {{ echo Test; }}
'''
        self.run_shell(setup + 'choose_port() { return 1; }; install_snell', expected=1)
        self.assertTrue(self.binary.exists())
        self.assertFalse(self.server.exists())
        self.run_shell(setup + 'choose_port() { echo 32000; }; install_snell')
        self.assertIn('32000', self.server.read_text())
        self.assertTrue(self.client.exists())
        self.assertEqual((self.root / 'downloads').read_text(), 'DOWNLOAD\n')

    def test_partial_install_preserves_config_and_existing_service(self):
        for system in ('debian', 'alpine'):
            for has_service in (False, True):
                self.prepare_mode_switch('unsafe-raw')
                self.server.write_text(self.server.read_text() + 'dns = 192.0.2.53\ndns-ip-preference = ipv4-only\n')
                before = self.server.read_bytes()
                self.binary.unlink(missing_ok=True)
                service = self.root / ('etc/init.d/snell' if system == 'alpine' else 'etc/systemd/system/snell.service')
                service.unlink(missing_ok=True)
                if has_service:
                    service.write_text('existing custom service\n')
                self.run_shell(f'''get_system_type() {{ echo {system}; }}
check_snell_stopped() {{ :; }}; install_required_packages() {{ :; }}; id() {{ :; }}
replace_snell_binary() {{ printf '#!/bin/sh\\nexit 0\\n' > '{self.binary}'; chmod 755 '{self.binary}'; }}
choose_port() {{ echo UNEXPECTED >&2; return 1; }}
systemctl() {{ :; }}; rc-update() {{ :; }}; restart_snell() {{ :; }}; show_logs() {{ :; }}
install_snell''')
                self.assertEqual(self.server.read_bytes(), before)
                self.assertIn('mode=unsafe-raw', self.client.read_text())
                self.assertTrue(service.exists())
                if has_service:
                    self.assertEqual(service.read_text(), 'existing custom service\n')

    def test_partial_install_reuses_preexisting_group(self):
        result = self.run_shell('''install_required_packages() { :; }; replace_snell_binary() { :; }
choose_port() { echo 32000; }; getent() { return 0; }; id() { return 1; }
useradd() { printf 'CREATE_USER:%s\\n' "$*"; }; systemctl() { :; }
restart_snell() { :; }; show_logs() { :; }; refresh_client_config() { :; }; install_snell''')
        self.assertIn('CREATE_USER:-r -g snell', result.stdout)

    def test_partial_install_retries_registration_without_replacing_files(self):
        before = self.prepare_mode_switch('unsafe-raw')
        self.binary.write_text('existing-core'); self.binary.chmod(0o755)
        service = self.root / 'etc/systemd/system/snell.service'
        service.write_text('existing-service')
        result = self.run_shell('''snell_service_enabled() { return 1; }
check_snell_running() { return 1; }; check_snell_stopped() { :; }
install_required_packages() { :; }; id() { :; }
replace_snell_binary() { echo UNEXPECTED_DOWNLOAD; return 1; }
systemctl() { echo SYSTEMCTL:"$1"; }; restart_snell() { echo RESTARTED; }; show_logs() { :; }
install_snell''')
        self.assertIn('SYSTEMCTL:enable', result.stdout)
        self.assertIn('RESTARTED', result.stdout)
        self.assertNotIn('UNEXPECTED', result.stdout)
        self.assertEqual(self.server.read_bytes(), before[0])
        self.assertEqual(self.binary.read_text(), 'existing-core')
        self.assertEqual(service.read_text(), 'existing-service')

    def test_partial_uninstall_without_service_removes_residual_files(self):
        for system in ('debian', 'alpine'):
            self.server.parent.mkdir(parents=True, exist_ok=True)
            self.server_config(); self.binary.write_text('partial-core')
            result = self.run_shell(f'''get_system_type() {{ echo {system}; }}
check_snell_running() {{ return 1; }}; systemctl() {{ [ "$1" = daemon-reload ]; }}
service_action() {{ echo UNEXPECTED_STOP; return 1; }}
rc-update() {{ echo UNEXPECTED_DISABLE; return 1; }}
uninstall_snell''')
            self.assertNotIn('UNEXPECTED', result.stdout)
            self.assertFalse(self.binary.exists())
            self.assertFalse(self.server.parent.exists())

    def test_partial_install_and_uninstall_preserve_live_process_files(self):
        self.prepare_mode_switch(); self.binary.write_text('partial-core')
        self.binary.chmod(0o755)
        before = self.server.read_bytes(), self.binary.read_bytes()
        for action in ('install_snell', 'uninstall_snell'):
            self.run_shell('check_snell_running() { return 1; }; snell_process_exists() { return 0; }; ' + action, expected=1)
            self.assertEqual((self.server.read_bytes(), self.binary.read_bytes()), before)

    def test_config_signals_after_either_rename_restore_both_files(self):
        for target in (self.server, self.client):
            for sig, status in [('HUP', 129), ('INT', 130), ('TERM', 143)]:
                before = self.prepare_mode_switch()
                marker = self.root / 'signalled'
                marker.unlink(missing_ok=True)
                result = self.run_shell(f'''check_snell_installed() {{ :; }}; check_snell_running() {{ :; }}
eval "$(declare -f write_file | sed '1s/write_file/original_write_file/')"
write_file() {{
    original_write_file "$@" || return
    if [ "$1" = '{target}' ] && [ ! -e '{marker}' ]; then
        touch '{marker}'; kill -{sig} "$BASHPID"
    fi
}}
restart_snell() {{ :; }}; switch_snell_mode''', '2\n', expected=status)
                self.assert_mode_files_unchanged(before)
                self.assertIn('已恢复原配置', result.stderr)

    def test_dns_conflicting_aliases_follow_core_order_and_normalize(self):
        for lines, current in [
                ('dns-ip-preference = ipv4-only\nipv-preference = ipv6-only\n', 'ipv6-only'),
                ('ipv-preference = ipv6-only\ndns-ip-preference = ipv4-only\n', 'ipv4-only')]:
            self.prepare_mode_switch()
            self.server.write_text(self.server.read_text() + lines)
            result = self.run_shell('''check_snell_installed() { :; }; check_snell_running() { return 1; }
check_snell_stopped() { :; }; switch_snell_dns''', '4\n')
            self.assertIn('当前 DNS 模式: ' + current, result.stdout)
            self.assertIn('dns-ip-preference = ipv4-only', self.server.read_text())
            self.assertNotIn('\nipv-preference', self.server.read_text())
            self.assertEqual(self.server.read_text().count('dns-ip-preference'), 1)

    def test_menu_marks_supervisor_without_listener_as_abnormal(self):
        for healthy in (True, False):
            result = self.run_shell(f'''clear() {{ :; }}; get_system_type() {{ echo alpine; }}
check_snell_installed() {{ :; }}; rc-service() {{ return 0; }}
snell_binary_version() {{ echo 'snell-server v6.0.0'; }}
snell_listener_pid() {{ return {0 if healthy else 1}; }}; show_menu''', '0\n')
            self.assertIn('已启动' if healthy else '异常（内核进程或监听不可用）', result.stdout)
            self.assertIn('3. 停止 Snell 服务', result.stdout)
            if not healthy:
                self.assertNotIn('已启动', result.stdout)

    def test_menu_uninstalls_residual_files_without_executable_core(self):
        for system in ('debian', 'ubuntu', 'alpine'):
            for binary_state in ('missing', 'not-executable'):
                with self.subTest(system=system, binary=binary_state):
                    self.server.parent.mkdir(parents=True, exist_ok=True)
                    self.server_config()
                    if binary_state == 'not-executable':
                        self.binary.write_text('partial download'); self.binary.chmod(0o600)
                    service = self.root / ('etc/init.d/snell' if system == 'alpine'
                                           else 'etc/systemd/system/snell.service')
                    service.write_text('residual service')
                    result = self.run_shell(f'''PATH='{self.binary.parent}:/usr/bin:/bin'
get_system_type() {{ echo {system}; }}; clear() {{ :; }}; check_root() {{ :; }}
check_snell_running() {{ return 1; }}; check_snell_stopped() {{ :; }}
service_action() {{ [ "$1" = stop ]; }}; systemctl() {{ :; }}; rc-update() {{ :; }}
main''', '2\n\n0\n')
                    self.assertIn('Snell 卸载成功', result.stdout)
                    self.assertFalse(service.exists())
                    self.assertFalse(self.binary.exists())
                    self.assertFalse(self.server.parent.exists())

    def test_uninstall_preserves_files_if_process_survives_service_stop(self):
        self.server_config(); self.binary.write_text('installed core')
        service = self.root / 'etc/systemd/system/snell.service'
        service.write_text('existing service')
        result = self.run_shell('''service_action() { echo STOP_REQUESTED; }
check_snell_stopped() { :; }; snell_process_exists() { return 0; }
systemctl() { echo UNEXPECTED_DISABLE; }; uninstall_snell''', expected=1)
        self.assertIn('STOP_REQUESTED', result.stdout)
        self.assertNotIn('UNEXPECTED_DISABLE', result.stdout)
        self.assertNotIn('卸载成功', result.stdout)
        self.assertIn('进程仍在运行', result.stderr)
        self.assertTrue(service.exists() and self.binary.exists() and self.server.exists())

    def test_update_client_failure_is_reported_as_partial_completion(self):
        self.prepare_mode_switch(); self.binary.write_text('installed core')
        before = self.client.read_bytes()
        for failure in ('render', 'write'):
            failing_step = ('render_client_config() { return 1; }' if failure == 'render'
                            else 'write_file() { cat >/dev/null; return 1; }')
            result = self.run_shell('''check_snell_running() { :; }; ipv6_available() { :; }
install_required_packages() { :; }; replace_snell_binary() { :; }
restart_snell() { :; }; show_logs() { :; }
''' + failing_step + '; update_snell', expected=1)
            self.assertNotIn('更新成功', result.stdout)
            self.assertIn('内核已更新，但客户端配置生成或写入失败', result.stderr)
            self.assertEqual(self.client.read_bytes(), before)

    def test_export_preserves_literal_psk_and_quotes_surge_delimiters(self):
        for psk in ('ExampleKey #suffix', r'Example,"quoted"\path #suffix',
                    'ExampleKey;literal', 'ExampleKey //literal'):
            self.server.write_text('[snell-server]\nlisten=0.0.0.0:40443\npsk=' + psk + '\n')
            self.client.write_text('Test = snell, 203.0.113.1, 40443, psk=old\n')
            self.run_shell('refresh_client_config')
            options = dict(field.split('=', 1) for field in proxy_fields(self.client.read_text())[3:])
            self.assertEqual(options['psk'], psk)
            self.assertIn('psk="', self.client.read_text())

    def test_invalid_psk_lengths_preserve_client(self):
        for psk in ('short', 'a' * 256, '密' * 86):
            self.server.write_text('[snell-server]\nlisten=0.0.0.0:40443\npsk=' + psk + '\n')
            self.client.write_text('keep existing client')
            self.run_shell('refresh_client_config', expected=1)
            self.assertEqual(self.client.read_text(), 'keep existing client')

    def test_ini_continuations_follow_previous_key_even_with_delimiters(self):
        self.server.write_text('\ufeff[snell-server]\nlisten:0.0.0.0:40443\n'
                               'psk:OriginalSecret123\n  AnotherSecret #literal\n'
                               'mode:default\n  unshaped\n'
                               'dns-ip-preference:ipv4-only\n  ipv6-only\n')
        for key, expected in [('psk', 'AnotherSecret #literal'), ('mode', 'unshaped'),
                              ('dns-ip-preference', 'ipv6-only')]:
            self.assertEqual(self.run_shell('config_value ' + key).stdout.strip(), expected)
        self.server.write_text('[snell-server]\npsk=OriginalSecret123\n mode=unshaped\n')
        self.assertEqual(self.run_shell('config_value psk').stdout.strip(), 'mode=unshaped')
        self.run_shell('config_value mode', expected=1)
        self.server.write_text('[snell-server]\nmode=default\n unshaped ; literal\n')
        self.assertEqual(self.run_shell('config_value mode').stdout.strip(), 'unshaped ; literal')

    def test_mode_edit_removes_continuations_and_preserves_other_fields(self):
        for first_line in (' listen = 0.0.0.0:40443\n', 'listen:0.0.0.0:40443\n'):
            self.server.write_text('[snell-server]\n' + first_line +
                                   'psk=ExampleKey #suffix\nmode=default\n  unshaped\n'
                                   '# retained comment\n[other]\nmode=untouched\n')
            self.client.write_text('Test = snell, 203.0.113.1, 40443, psk=old\n')
            result = self.run_shell('''check_snell_installed() { :; }; check_snell_running() { return 1; }
check_snell_stopped() { :; }; switch_snell_mode''', '1\n')
            self.assertIn('当前配置模式: unshaped', result.stdout)
            self.assertNotIn('  unshaped', self.server.read_text())
            self.assertIn('# retained comment', self.server.read_text())
            self.assertIn('[other]\nmode=untouched', self.server.read_text())
            self.assertEqual(self.run_shell('config_value psk').stdout.strip(), 'ExampleKey #suffix')
            self.assertEqual(self.run_shell('config_value mode').stdout.strip(), 'default')

    def test_ini_section_names_are_literal_and_malformed_input_is_rejected(self):
        for section in ('[ snell-server ]', '[snell - server]'):
            self.server.write_text(section + '\nmode=default\n')
            self.run_shell('config_value mode', expected=1)
            self.run_shell('render_server_setting mode unshaped', expected=2)
        self.server.write_text('[snell-server]\nmode=default\n[broken\n')
        self.run_shell('config_value mode', expected=2)
        self.run_shell('render_server_setting mode unshaped', expected=2)


if __name__ == '__main__':
    unittest.main()
