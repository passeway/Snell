<div align="center">

# Snell v6

### One key. A distinct traffic profile.

Deploy the Surge team's Snell v6 proxy protocol on Debian, Ubuntu, CentOS and Alpine with a single command.

![Snell](https://img.shields.io/badge/Snell-v6-635BFF?style=flat-square)
![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20CentOS%20%7C%20Alpine-18181B?style=flat-square)
![Architecture](https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-18181B?style=flat-square)
[![Checks](https://github.com/passeway/Snell/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/passeway/Snell/actions/workflows/check.yml)

**English** · [简体中文](README_zh.md)

[Quick start](#quick-start) · [Connect with Surge](#connect-with-surge) · [Management menu](#management-menu) · [Configuration](#configuration) · [Advanced](#advanced)

</div>

---

## Quick start

Run as **root**. No domain or certificate is required.

```bash
# Debian / Ubuntu / CentOS
bash <(curl -fsSL https://snell-ten.vercel.app)
```

```sh
# Alpine
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://snell-ten.vercel.app)'
```

**① Choose `1` to install → ② Allow the printed TCP port in your security group and firewall → ③ Import the proxy entry into Surge**

> CentOS support covers the maintained **CentOS Stream 9 / 10** (RHEL-compatible systems such as Rocky and AlmaLinux also install with `dnf`, and **Rocky Linux 8** is verified in CI); CentOS 7 (no `dnf`) is not supported, and end-of-life CentOS 8 is not recommended because its official repositories are offline. With firewalld enabled, allow the port with `firewall-cmd --permanent --add-port=PORT/tcp && firewall-cmd --reload`.

Installation sets up dependencies, a random port, a 48-character random PSK and the system service, then prints a ready-to-use Surge proxy entry. Run the same command again to open the management menu.

> The installer currently uses the official **v6.0.0rc2** test release with `mode=default` (AES encryption and traffic shaping). Your client must support Snell v6 and use the same `mode` as the server.

---

## Why Snell v6

**Deployment-level protocol diversity is the defining change in v6.** Client and server derive framing, padding and packet-size behavior from the PSK, so deployments with different keys present different traffic profiles, making classification by a shared fingerprint harder.

| 42 profile parameters | 13 shaping strategy categories | Derived from your PSK |
| :---: | :---: | :---: |
| Define protocol behavior | Combine into distinct profiles | No manual tuning |

| Capability | Practical value |
| :--- | :--- |
| **0-RTT** | PSK authentication cuts connection setup round trips |
| **Connection reuse and full TCP semantics** | Preserves behavior such as half-close for application compatibility |
| **Precise error reporting** | Helps Surge tell authentication problems from destination failures |
| **UDP over TCP** | Relays UDP over the TCP connection, so a single TCP port is enough |
| **Flexible network controls** | DNS address-family preferences and multiple listening addresses |

Read [Inside Snell v6](https://nssurge.com/blog/snell-v6/) and the [official release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) for the design details.

## What the installer does

- **Several systems, one experience**: systemd on Debian / Ubuntu / CentOS, OpenRC on Alpine, on AMD64 and ARM64.
- **Automatic dual stack**: listens on `0.0.0.0:PORT,[::]:PORT` when IPv6 is available and exports an extra IPv6 entry when a public IPv6 address is found.
- **Verified outcomes**: after a start or restart it checks the real core process and its listening ports, not just the service manager's state.
- **Safe changes**: failed or interrupted configuration changes restore the previous configuration; updates keep the running or stopped state; only one management operation runs at a time.

---

## Connect with Surge

Copy the printed entry into the `[Proxy]` section of your Surge configuration:

```ini
[Proxy]
My-Snell = snell, YOUR_SERVER_IP, YOUR_PORT, psk=YOUR_PSK, version=6, mode=default, reuse=true
```

The address, port and PSK above are placeholders. Copy the actual output.

- **Export again**: option **8** reads the current port, PSK and mode, and keeps the existing address and node names (including a renamed IPv6 entry).
- **After editing the server configuration by hand**: restart with **5**, then export with **8**.
- **PSK with spaces, commas or quotes**: copy the complete entry, including its quotes and escapes.

## Management menu

| Option | Action |
| :---: | :--- |
| `1` | Install; after a failed attempt, complete the missing steps while keeping the port, PSK and settings |
| `2` | Stop and verify the service, then uninstall; also cleans up residues when the core is missing |
| `3` | Start or stop, according to the current state |
| `4` | Update the core, keeping the running or stopped state |
| `5` | Restart and check the result |
| `6` | View service status |
| `7` | Follow logs on Debian / Ubuntu / CentOS; show troubleshooting steps on Alpine |
| `8` | Regenerate and display the Surge proxy entry |
| `9` | Change configuration: port, mode and DNS |
| `0` | Exit |

If the service manager reports running but the core process or its listeners are unavailable, the menu shows an abnormal state and keeps the stop option available.

## Configuration

Each change under option **9** keeps all other settings. A running service is restarted and checked; a stopped service stays stopped.

### Port · `9 → 1`

Enter a new port in `1–65535`. The script checks that the TCP port is free and updates the client entry; allow the new port in your firewall and update Surge afterwards. Entering the current port with unchanged listening addresses only refreshes the client entry, without a restart.

### Proxy mode · `9 → 2`

| Option | Mode | Behavior |
| :---: | :--- | :--- |
| `1` | `default` | AES encryption with traffic shaping; the default |
| `2` | `unshaped` | AES encryption without traffic shaping |
| `3` | `unsafe-raw` | Plaintext; only for an intranet or an existing secure tunnel |

**Copy the new entry to Surge after switching**: client and server must use the same `mode`.

### DNS preference · `9 → 3`

| Option | Value | Behavior |
| :---: | :--- | :--- |
| `1` | `default` | Snell's default policy |
| `2` | `prefer-ipv4` | Prefer IPv4 results |
| `3` | `prefer-ipv6` | Prefer IPv6 results |
| `4` | `ipv4-only` | IPv4 results only |
| `5` | `ipv6-only` | IPv6 results only; requires working IPv6 egress |

DNS preference only affects the address family the server uses when connecting to hostnames. Existing DNS servers are kept (system DNS when none is set), and no new client entry is needed.

---

## Advanced

<details>
<summary><strong>IPv4 / IPv6 dual stack and the IPv6 entry</strong></summary>

- With the IPv6 stack enabled and an IPv6 address present, the installer listens on `0.0.0.0:PORT,[::]:PORT`; otherwise on IPv4 only. Option **4** checks again on update; manually bound addresses are preserved.
- When Snell listens on IPv6 and is reachable from outside, an extra entry with a `-v6` suffix is exported alongside the IPv4 entry:
  - with `[::]`, it uses the public address on the interface of the default IPv6 route, skipping outbound-only tunnels such as WARP;
  - with a specific public IPv6 bind, it uses that address;
  - loopback, link-local and private binds are not exported.
- The IPv6 entry uses the IPv6 listener's port and the same PSK and mode as the IPv4 entry.
- When IPv4 and IPv6 use different ports, the IPv4 entry matches the IPv4 listener; if that cannot be determined, the existing entry is kept and the script reports the problem.
- Public IPv6 access also needs the port allowed in your firewall. v6 relays UDP over TCP, so no extra inbound UDP port is needed.

</details>

<details>
<summary><strong>Updates, recovery and concurrency</strong></summary>

- **Updates** check required server settings before replacing the core. Installed dependencies are reused and only missing packages are installed; if the new core fails its startup probe, dependencies are repaired and the probe retried once. If the core is updated but the client entry cannot be generated, the unfinished step is reported; fix it and retry with option **8**.
- **Configuration changes** that fail to write or restart, or are interrupted, restore the previous configuration without creating backup files.
- **Concurrency**: only one management operation can change files or service state at a time; another terminal is asked to retry later.
- **DNS alias**: when both `dns-ip-preference` and its alias `ipv-preference` exist, the last value wins, matching the core; choosing a value in the menu normalizes them to one `dns-ip-preference`.

</details>

<details>
<summary><strong>Connection problems? Check these first.</strong></summary>

Confirm that the service is running, its TCP port is allowed, and the client address, port, PSK, version and mode match the server.

```bash
# Debian / Ubuntu / CentOS
systemctl status snell --no-pager
journalctl -u snell -n 50 --no-pager
```

```sh
# Alpine
rc-service snell status
```

- **Alpine logs**: Snell logs are not saved and no log rotation or scheduled task is configured. For temporary diagnostics, run `rc-service snell stop`, then `/usr/local/bin/snell-server -l info -c /etc/snell/snell-server.conf` to see output in the terminal; press `Ctrl+C` when done and run `rc-service snell start`.
- **Live logs**: on Debian / Ubuntu / CentOS, press `Ctrl+C` in option **7** to return to the menu.
- **Public IPv4 lookup fails**: enter it manually, or cancel and retry with option **8**. If the country lookup fails, the node name defaults to `Snell`.
- **Uninstall blocked**: if a foreground Snell diagnostic process is still running, uninstall keeps the files and asks you to end that process first.
- **Reporting a bug**: include your OS, architecture, server and client versions, and relevant logs. Redact the PSK.

</details>

---

<div align="center">

**Continuously checked** · Native AMD64 and ARM64 CI on Debian, Ubuntu, CentOS Stream, Rocky Linux 8 and Alpine

Real dependency installs, all three protocol modes, five DNS preferences, and TCP and UDP payloads over IPv4 / IPv6;<br>
real systemd / OpenRC tests for permissions, repeat installs, configuration changes, failed-start recovery, update preflight and uninstall.

<sub>Validate your public network path on your own deployment.</sub>

<br>

Protocol by the **Surge team** · This project focuses on Linux installation and management

[Inside Snell v6](https://nssurge.com/blog/snell-v6/) · [Official release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) · [Report an issue](https://github.com/passeway/Snell/issues)

</div>
