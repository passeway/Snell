"""Offline checks for the Docker installer. Paths are redirected to a temporary tree."""
import pathlib
import re
import subprocess
import tempfile
import unittest

from test_snell import SOURCE, proxy_fields

DOCKER_SOURCE = SOURCE.with_name('Snell-docker.sh')


class DockerInstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.code = DOCKER_SOURCE.read_text().replace(
            'BASE_DIR="/root/snell-docker"', f'BASE_DIR="{self.root}"')
        # The host's own addresses must not leak into exports; IPv6 tests provide fixtures.
        self.code += '\nip() { return 1; }\n'
        self.config = self.root / 'snell-conf/snell.conf'

    def run_shell(self, body, expected=0):
        result = subprocess.run(['bash', '-c', self.code + '\n' + body], text=True,
                                capture_output=True, timeout=8)
        self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
        return result

    def test_version_matches_main_installer(self):
        version = re.compile(r'^VERSION="([^"]+)"$', re.M)
        self.assertEqual(version.search(DOCKER_SOURCE.read_text()).group(1),
                         version.search(SOURCE.read_text()).group(1))

    def test_fresh_config_is_v6(self):
        self.run_shell('ipv6_available() { return 1; }; prepare_server_config')
        text = self.config.read_text()
        self.assertIn('mode = default\n', text)
        self.assertIn('dns-ip-preference = default\n', text)
        port = int(re.search(r'^listen = 0\.0\.0\.0:(\d+)$', text, re.M).group(1))
        self.assertTrue(30000 <= port <= 65000)
        self.assertRegex(text, r'(?m)^psk = [A-Za-z0-9]{48}$')
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)

    def test_v5_config_migrates_port_and_psk(self):
        self.config.parent.mkdir(parents=True)
        self.config.write_text('[snell-server]\nlisten = ::0:41234\npsk = OldV5Secret12345\nipv6 = true\n')
        self.run_shell('ipv6_available() { return 0; }; prepare_server_config')
        self.assertEqual(self.config.read_text(),
                         '[snell-server]\nmode = default\nlisten = 0.0.0.0:41234,[::]:41234\n'
                         'psk = OldV5Secret12345\ndns-ip-preference = default\n')

    def test_existing_v6_config_is_kept(self):
        self.config.parent.mkdir(parents=True)
        original = '[snell-server]\nlisten = 0.0.0.0:40443\npsk = KeepThisSecret99\nmode = unshaped\n'
        self.config.write_text(original)
        self.run_shell('prepare_server_config')
        self.assertEqual(self.config.read_text(), original)

    def test_existing_invalid_config_is_never_regenerated(self):
        self.config.parent.mkdir()
        for original in [
            '[snell-server]\nlisten=0.0.0.0:40443\npsk=OriginalSecret123\nmode=default\nbroken line\n',
            '[snell-server]\nlisten=0.0.0.0:40443\n',
            '',
        ]:
            with self.subTest(config=original):
                self.config.write_text(original)
                result = self.run_shell('choose_port() { echo UNEXPECTED >&2; return 99; }; prepare_server_config', expected=1)
                self.assertEqual(self.config.read_text(), original)
                self.assertIn('保留原文件', result.stderr)
                self.assertNotIn('UNEXPECTED', result.stderr)

    def test_client_export_preserves_previous_file_on_failure(self):
        self.config.parent.mkdir()
        self.config.write_text('[snell-server]\nlisten=[::]:40443\npsk=OriginalSecret123\nmode=default\n')
        client = self.config.with_name('snell.txt')
        client.write_text('previous working client\n')
        self.run_shell('write_client_config 203.0.113.9 HK', expected=1)
        self.assertEqual(client.read_text(), 'previous working client\n')
        self.config.write_text('[snell-server]\nlisten=0.0.0.0:40443\npsk=OriginalSecret123\nmode=default\n')
        for failure in ['mv() { return 1; }', 'chmod() { return 1; }',
                        'printf() { if [ "$2" = "replacement" ]; then return 1; fi; command printf "$@"; }; render_client_config() { echo replacement; }']:
            self.run_shell(failure + '; write_client_config 203.0.113.9 HK', expected=1)
            self.assertEqual(client.read_text(), 'previous working client\n')
            self.assertEqual(list(client.parent.glob('snell.txt.*')), [])
        self.run_shell('write_client_config 203.0.113.9 HK')
        self.assertIn('203.0.113.9, 40443', client.read_text())
        self.assertEqual(client.stat().st_mode & 0o777, 0o600)

    def test_client_entry_quotes_psk(self):
        self.config.parent.mkdir(parents=True)
        self.config.write_text('[snell-server]\nlisten = 0.0.0.0:40443, [::]:40443\n'
                               'psk = a "quoted", secret\nmode = unsafe-raw\n')
        line = self.run_shell('render_client_config 203.0.113.9 JP').stdout.strip()
        self.assertEqual(proxy_fields(line.split('=', 1)[1]),
                         ['snell', '203.0.113.9', '40443', 'psk=a "quoted", secret',
                          'version=6', 'mode=unsafe-raw', 'reuse=true'])

    def test_client_entry_adds_ipv6_node_for_ipv6_listener(self):
        self.config.parent.mkdir(parents=True)
        self.config.write_text('[snell-server]\nlisten = 0.0.0.0:40443,[::]:40443\npsk = KeepThisSecret99\nmode = default\n')
        lines = self.run_shell('get_public_ipv6() { echo 2001:db8::1; }; render_client_config 203.0.113.9 JP').stdout.splitlines()
        self.assertEqual(lines, [
            'JP = snell, 203.0.113.9, 40443, psk=KeepThisSecret99, version=6, mode=default, reuse=true',
            'JP-v6 = snell, 2001:db8::1, 40443, psk=KeepThisSecret99, version=6, mode=default, reuse=true'])
        self.config.write_text('[snell-server]\nlisten = 0.0.0.0:40443\npsk = KeepThisSecret99\nmode = default\n')
        lines = self.run_shell('get_public_ipv6() { echo 2001:db8::1; }; render_client_config 203.0.113.9 JP').stdout.splitlines()
        self.assertEqual(len(lines), 1)

    def test_shared_ipv6_helpers_match_main_installer(self):
        main, docker = SOURCE.read_text(), DOCKER_SOURCE.read_text()
        for name in ('get_public_ipv6', 'parse_snell_config', 'client_ipv4_port', 'client_ipv6_endpoint'):
            pattern = re.compile(r'^' + name + r'\(\) \{\n.*?^\}\n', re.M | re.S)
            self.assertEqual(pattern.search(docker).group(0), pattern.search(main).group(0), name)

    def test_export_matches_address_family_and_explicit_ipv6_binding(self):
        self.config.parent.mkdir()
        for listen, expected4, expected6 in [
            ('[::]:40444,0.0.0.0:40443', '40443', ('2001:db8::1', '40444')),
            ('0.0.0.0:40443,[2001:db8::2]:40444', '40443', ('2001:db8::2', '40444')),
            ('0.0.0.0:40443,[fd00::2]:40444', '40443', None),
            ('0.0.0.0:40443,[2001:db8::2]:40444,[2001:db8::3]:40445', '40443', None),
        ]:
            with self.subTest(listen=listen):
                self.config.write_text(f'[snell-server]\nlisten={listen}\npsk=KeepThisSecret99\nmode=default\n')
                lines = self.run_shell('get_public_ipv6() { echo 2001:db8::1; }; render_client_config 203.0.113.9 HK').stdout.splitlines()
                self.assertEqual(proxy_fields(lines[0].split('=', 1)[1])[1:3], ['203.0.113.9', expected4])
                self.assertEqual(len(lines), 2 if expected6 else 1)
                if expected6:
                    self.assertEqual(proxy_fields(lines[1].split('=', 1)[1])[1:3], list(expected6))

    def test_export_rejects_missing_or_ambiguous_ipv4_listener(self):
        self.config.parent.mkdir()
        for listen in ['[::]:40444', '10.0.0.1:40443,10.0.0.2:40444']:
            self.config.write_text(f'[snell-server]\nlisten={listen}\npsk=KeepThisSecret99\nmode=default\n')
            result = self.run_shell('render_client_config 203.0.113.9 HK', expected=1)
            self.assertEqual(result.stdout, '')

    def test_export_uses_effective_ini_values(self):
        self.config.parent.mkdir()
        self.config.write_text('\ufeff[snell-server]\nlisten=0.0.0.0:40443 ; listener\n'
                               'psk=KeepThisSecret99 ; comment\nmode=default\n  unshaped\n')
        line = self.run_shell('render_client_config 203.0.113.9 HK').stdout.strip()
        fields = proxy_fields(line.split('=', 1)[1])
        self.assertIn('psk=KeepThisSecret99', fields)
        self.assertIn('mode=unshaped', fields)
        self.config.write_text('[snell-server]\nlisten=0.0.0.0:40443\n'
                               'psk=KeepThisSecret99\nmode=default ; comment\n')
        self.assertIn('mode=default, reuse=true', self.run_shell('render_client_config 203.0.113.9 HK').stdout)

    def test_export_rejects_malformed_config_before_printing(self):
        self.config.parent.mkdir()
        self.config.write_text('[snell-server]\nlisten=0.0.0.0:40443\npsk=KeepThisSecret99\nbroken line\n')
        result = self.run_shell('render_client_config 203.0.113.9 HK', expected=1)
        self.assertEqual(result.stdout, '')

    def test_compose_uses_local_v6_build(self):
        self.root.joinpath('snell-conf').mkdir()
        self.run_shell('uname() { echo aarch64; }; write_compose_files')
        compose = (self.root / 'docker-compose.yml').read_text()
        self.assertIn('SNELL_ARCH: aarch64', compose)
        self.assertIn('image: snell-server:v6', compose)
        self.assertIn('./snell-conf:/etc/snell:ro', compose)
        self.assertNotIn('accors', compose)
        self.assertIn('/etc/snell/snell.conf', (self.root / 'Dockerfile').read_text())


if __name__ == '__main__':
    unittest.main()

