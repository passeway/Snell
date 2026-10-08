<div align="center">

# Snell v6

### One key. A distinct traffic profile.

**Deployment diversity · Low overhead · Built for Surge**

Bring Snell v6 to your server with a simple deployment.<br>
Installation and management for Debian, Ubuntu and Alpine.

![Snell](https://img.shields.io/badge/Snell-v6-635BFF?style=flat-square)
![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20Alpine-18181B?style=flat-square)
![Architecture](https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-18181B?style=flat-square)
[![Checks](https://github.com/passeway/Snell/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/passeway/Snell/actions/workflows/check.yml)

**English** · [简体中文](README_zh.md)

[Protocol advantages](#protocol-advantages) · [Quick start](#quick-start) · [Connect with Surge](#connect-with-surge) · [Service management](#service-management)

</div>

---

## Protocol advantages

### Traffic profiles that vary by deployment

**Deployment-level protocol diversity is the defining change in Snell v6.** The PSK determines framing, padding and packet-size behavior automatically. Different keys produce different traffic profiles, making classification by a shared fingerprint harder.

| 42 profile parameters | 13 shaping strategy categories | Derived from your PSK |
| :---: | :---: | :---: |
| Define protocol behavior | Combine into distinct profiles | No manual profile tuning |

Explore the design in the [Surge team's Snell v6 introduction](https://nssurge.com/blog/snell-v6/).

### Less overhead. More connection detail.

v6 retains Snell's focus on performance and compatibility:

| Capability | Practical value |
| :--- | :--- |
| **0-RTT design** | PSK authentication reduces proxy connection setup round trips |
| **Connection reuse and full TCP semantics** | Preserves behavior such as half-close for application compatibility |
| **Precise error reporting** | Helps Surge distinguish authentication problems from destination failures |
| **UDP over TCP** | Relays UDP through the TCP connection, simplifying inbound firewall rules |
| **Flexible network controls** | DNS address-family preferences and multiple listening addresses |

See the [official release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) for protocol and mode details. Multiple listening addresses are configurable in the core; this installer listens on IPv4 by default.

## From protocol to deployment

**Connect using your server IP, port and PSK. No domain or certificate setup is required.**

- **Ready after installation**: dependencies, a random port, a 48-character random PSK and a Surge proxy entry are prepared for you.
- **Three Linux systems**: systemd on Debian / Ubuntu and OpenRC on Alpine, with AMD64 and ARM64 support.
- **One management menu**: installation, service controls, logs, mode switching and client configuration export.
- **Verified outcomes**: binary execution and service-state checks, with the running or stopped state preserved during updates.

> The installer currently downloads the official **v6.0.0rc2** test release. It uses `mode=default` with AES encryption and traffic shaping. Your client must support Snell v6 and use the same mode as the server.

## Quick start

Run as **root**.

### Debian / Ubuntu

With `bash` and `curl` installed:

```bash
bash <(curl -fsSL snell-ten.vercel.app)
```

### Alpine

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://snell-ten.vercel.app)'
```

**Run the script → Choose `1` → Allow the generated TCP port → Connect with Surge.**

Allow the actual listening port in both your cloud security group and server firewall. v6 relays UDP over TCP; no additional inbound UDP port is required for that relay.

## Connect with Surge

Copy the generated proxy entry into the `[Proxy]` section of your Surge configuration:

```ini
[Proxy]
My-Snell = snell, YOUR_SERVER_IP, YOUR_PORT, psk=YOUR_PSK, version=6, mode=default, reuse=true
```

The address, port and PSK above are placeholders. Use the actual entry printed after installation.

Option **8** reads the current server port, PSK and mode while preserving the existing valid address and node name. After editing the server configuration, restart with **5**, then export with **8**.

## Switch Snell modes

Choose **9 · Switch Snell mode** to view the configured mode and select:

| Option | Mode | Behavior and use |
| :---: | :--- | :--- |
| `1` | `default` | AES encryption with traffic shaping; the default choice |
| `2` | `unshaped` | Keeps AES encryption and disables traffic shaping |
| `3` | `unsafe-raw` | Disables encryption and shaping; plaintext transport for an intranet or an existing secure tunnel only |
| `0` | Return | Keep the current configuration |

Switching preserves the port, PSK and other server settings and regenerates the client entry. A running service is restarted and checked; a stopped service stays stopped until you start it. Failed writes or restarts trigger an attempt to restore the previous configuration without creating backup files.

**Copy the new entry to Surge after switching: the client and server must use the same `mode`.** See the [official release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) for mode definitions.

## Service management

Run the installation command again to open the menu.

| Option | Action |
| :---: | :--- |
| `1` | Install Snell |
| `2` | Stop and verify the service, then uninstall |
| `3` | Start or stop, according to the current state |
| `4` | Update the binary, preserving the running or stopped state |
| `5` | Restart and check the result |
| `6` | View service status |
| `7` | Follow logs on Debian / Ubuntu; show troubleshooting instructions on Alpine |
| `8` | Regenerate and display the Surge proxy entry |
| `9` | Switch Snell mode |
| `0` | Exit |

<details>
<summary><strong>Connection problems? Check these first.</strong></summary>

Confirm that the service is running, its TCP port is allowed, and the client address, port, PSK, version and mode match the server.

Debian / Ubuntu:

```bash
systemctl status snell --no-pager
journalctl -u snell -n 50 --no-pager
```

Alpine:

```sh
rc-service snell status
```

Alpine does not save Snell logs or configure log rotation or scheduled tasks. For temporary diagnostics, run `rc-service snell stop`, then `/usr/local/bin/snell-server -l info -c /etc/snell/snell-server.conf` to display output in the terminal. Press `Ctrl+C` when finished and run `rc-service snell start` to restore the service. On Debian / Ubuntu, `Ctrl+C` exits live logs and returns to the menu.

If automatic public IPv4 lookup fails, enter it manually or cancel and retry with option **8**. If country lookup fails, the default node name is `Snell`.

For bug reports, include your OS, architecture, server and client versions, and relevant logs. Redact the PSK.

</details>

---

**Continuously checked** · Three-system CI installs the script's actual dependencies and covers failure-path regressions, mode switching and recovery, Alpine log suppression and cleanup, and real proxy traffic in all three modes through the official Snell v6 server. Service manager commands are mocked; validate your actual network path on your own deployment.

<div align="center">

Protocol by the **Surge team** · This project focuses on Linux installation and management

[Inside Snell v6](https://nssurge.com/blog/snell-v6/) · [Official release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) · [Report an issue](https://github.com/passeway/Snell/issues)

</div>
