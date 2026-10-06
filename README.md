<div align="center">

# Snell

### Simple deployment. Clear control.

Snell v6 installation and management for Debian · Ubuntu · Alpine.

[![Checks](https://github.com/passeway/Snell/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/passeway/Snell/actions/workflows/check.yml)
![Platform](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20Alpine-2563eb?style=flat-square)
![Architecture](https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-475569?style=flat-square)
[![License](https://img.shields.io/github/license/passeway/Snell?style=flat-square)](LICENSE)

**English** · [简体中文](README_zh.md)

[Quick start](#quick-start) · [Service management](#service-management) · [Client configuration](#client-configuration) · [Report an issue](https://github.com/passeway/Snell/issues)

</div>

---

Install, start, stop and update Snell from one interactive menu. The script adapts to systemd or OpenRC and generates a proxy entry for Surge.

| Deploy | Manage | Connect |
| :--- | :--- | :--- |
| Debian, Ubuntu and Alpine | Start, stop, restart and update | Generated Surge proxy entry |
| AMD64 and ARM64 | Installation, runtime and version status | Random port and PSK |
| Automatic dependency installation | Service status and live logs | Export from the current server configuration |

## Quick start

Run as **root**. The script currently downloads **v6.0.0rc2**; the server version output may report **v6.0.0**.

### Debian / Ubuntu

With `bash` and `curl` installed:

```bash
bash <(curl -fsSL snell-ten.vercel.app)
```

### Alpine

Install the command dependencies first:

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://snell-ten.vercel.app)'
```

**Run the script → Choose `1` → Allow the generated TCP port → Copy the proxy entry into Surge.**

> [!IMPORTANT]
> Allow the actual listening TCP port in both your cloud security group and server firewall. Snell carries UDP relay traffic over TCP; an additional UDP firewall opening is not required for this relay.

## Supported environments

| System | Service manager | Architecture |
| :--- | :--- | :--- |
| Debian | systemd | AMD64 / ARM64 |
| Ubuntu | systemd | AMD64 / ARM64 |
| Alpine | OpenRC | AMD64 / ARM64 |

The main script installs Alpine dependencies including `gcompat` and `libstdc++`. This support matrix applies to the main installer.

## Service management

Run the installation command again to open the menu. Once installed, option `3` switches between start and stop according to the service state.

| Option | Action |
| :---: | :--- |
| `1` | Install Snell |
| `2` | Uninstall Snell |
| `3` | Start or stop the service |
| `4` | Update the Snell binary |
| `5` | Restart the service |
| `6` | View service status |
| `7` | Follow logs; press `Ctrl+C` to return to the menu |
| `8` | Regenerate and display the client entry from the current server configuration |
| `0` | Exit |

## Client configuration

Copy the generated entry into the `[Proxy]` section of your Surge configuration:

```ini
[Proxy]
My-Snell = snell, YOUR_SERVER_IP, YOUR_PORT, psk=YOUR_PSK, version=6, mode=default, reuse=true
```

Replace the address, port and PSK placeholders with the actual values. Your client must support Snell v6.

- Option **8** reads the current port, PSK and `mode`, preserving an existing valid IPv4 address and node name.
- Public IPv4 lookup uses timeouts and fallback providers. If all providers fail, enter the address manually; leave it empty to cancel and retry with option **8**.
- After editing the server configuration, restart with option **5**, then export with option **8**. Server and client modes must match.

### Common paths

| Path | Purpose |
| :--- | :--- |
| `/usr/local/bin/snell-server` | Server binary |
| `/etc/snell/snell-server.conf` | Server configuration |
| `/etc/snell/snell-client.conf` | Generated Surge proxy entry |

Server configuration permissions are `root:snell 640`; client configuration permissions are `root:root 600`.

## Troubleshooting

<details>
<summary><strong>Debian / Ubuntu · systemd</strong></summary>

```bash
systemctl status snell --no-pager
journalctl -u snell -n 50 --no-pager
```

</details>

<details>
<summary><strong>Alpine · OpenRC</strong></summary>

```sh
rc-service snell status
tail -n 50 /var/log/snell.log
```

Logs are checked hourly and rotated above 1 MiB, retaining up to 3 compressed archives. Settings are stored in `/etc/snell/logrotate.conf`. Logs can grow between checks; `copytruncate` has a small possible loss window between copying and truncation.

</details>

| Symptom | Check first |
| :--- | :--- |
| Connection timeout | Service status, listening port, cloud security group and local firewall |
| Connection fails after editing settings | Address, port, PSK, version and mode; restart and regenerate the client entry |
| Public address lookup fails | Enter the public IPv4 address manually and regenerate with option `8` |

When reporting an issue, include the OS, CPU architecture, server and client versions, and relevant logs. Redact your PSK.

Automated checks run syntax and regression tests in Debian, Ubuntu and Alpine containers. Service commands are mocked; these tests do not replace end-to-end VPS validation.

---

<div align="center">

Snell is developed by the [Surge Team](https://kb.nssurge.com/surge-knowledge-base) · This repository is an independent installation and management script project.

[Official release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) · [Report an issue](https://github.com/passeway/Snell/issues) · [View checks](https://github.com/passeway/Snell/actions)

</div>
