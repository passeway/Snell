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
        for name in ('get_public_ipv6', 'client_ipv6_port'):
            pattern = re.compile(r'^' + name + r'\(\) \{\n.*?^\}\n', re.M | re.S)
            self.assertEqual(pattern.search(docker).group(0), pattern.search(main).group(0), name)

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
