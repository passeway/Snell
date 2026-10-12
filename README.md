<div align="center">

# Snell v6

### One key. A distinct traffic profile.

**Snell** is a lightweight encrypted proxy protocol designed by the Surge team.<br>
**v6** introduces deployment-level protocol diversity: every deployment derives its own traffic profile from its PSK.

![Snell](https://img.shields.io/badge/Snell-v6-635BFF?style=flat-square)
![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20CentOS%20%7C%20Alpine-18181B?style=flat-square)
![Architecture](https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-18181B?style=flat-square)
[![Checks](https://github.com/passeway/Snell/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/passeway/Snell/actions/workflows/check.yml)

**English** · [简体中文](README_zh.md)

[Why v6](#why-snell-v6) · [Quick start](#quick-start) · [Connect with Surge](#connect-with-surge) · [Management menu](#management-menu) · [Configuration](#configuration) · [Advanced](#advanced)

</div>

---

## Why Snell v6

> **v6 does not impersonate TLS or any other protocol. It makes every deployment different.**<br>
> Client and server derive a protocol profile from the PSK. The profile controls observable behavior such as framing, padding, packet-size distribution and traffic normalization. Different PSKs produce different traffic characteristics, so there is no single stable traffic pattern shared by all Snell v6 deployments.

| **42** | **13** | **0** |
| :---: | :---: | :---: |
| profile parameters | padding and traffic-shaping strategy categories, freely combined | parameters to tune by hand: the profile is derived from the PSK |

### A third approach

| Approach | How it works | Limitation |
| :--- | :--- | :--- |
| Pure encryption | Minimize protocol structure and emit a high-entropy random stream | Perfect randomness is itself a recognizable feature |
| Imitate a common protocol | Make traffic resemble TLS or similar | Has to keep up with the details of the imitated protocol |
| **Snell v6** | **Deployment-level protocol diversity** | A classifier faces many deployment-specific behaviors instead of one fixed fingerprint |

v4 added controlled random perturbations to the AES stream and worked well for four years, but every deployment shared the same kind of perturbation, which could become a target once studied. v6 turns "one protocol, one pattern" into "one deployment, one pattern".

**Deriving the profile from the PSK** keeps deployment as simple as before, with no low-level parameters to learn, and prevents profile homogenization: nobody copies the same profile, so deployments naturally diverge.

### Snell's long-standing strengths, kept

| Capability | What you get |
| :--- | :--- |
| **Performance first** | Latency and throughput have been first-class priorities since v1, close to the practical limits of a proxy protocol |
| **Single-binary deployment** | One binary with minimal dependencies |
| **Precise error reporting** | Tells authentication failures from destination timeouts, so Surge, especially Smart policy groups, judges proxy health accurately |
| **Multiplexing + full TCP state machine** | One of the few protocols with both, so applications that rely on half-close keep working |
| **0-RTT** | PSK authentication cuts connection setup round trips |
| **UDP relay** | Carried over TCP, so a single TCP port is enough |

### New network controls in v6

- **`dns-ip-preference`**: address-family preference for DNS results, with five modes: `default`, `prefer-ipv4`, `prefer-ipv6`, `ipv4-only` and `ipv6-only`. Useful on dual-stack, IPv6-preferred or single-stack egress.
- **Multiple listening addresses**: `listen = 0.0.0.0:PORT,[::]:PORT` listens on IPv4 and IPv6 explicitly, without relying on the system's IPv6 socket compatibility behavior. This installer generates it by default.

### Three modes for different needs

| Mode | Encryption | Shaping | Use it for |
| :--- | :---: | :---: | :--- |
| `default` | AES | ✓ | Recommended; the full v6 traffic diversity |
| `unshaped` | AES | — | Encryption without shaping, less padding overhead |
| `unsafe-raw` | — | — | Plaintext; only for an intranet or an existing secure tunnel |

<details>
<summary><strong>Snell version history</strong></summary>

| Version | Main changes |
| :---: | :--- |
| v1 | Structured error reporting, single-binary deployment, performance first |
| v2 | Connection multiplexing with a full TCP state machine |
| v3 | UDP forwarding |
| v4 | Controlled random perturbations in the AES stream, avoiding a "perfectly random" signature |
| v5 | QUIC Proxy Mode (removed in v6: QUIC is hard to proxy well; blocking QUIC so apps fall back to HTTP/2 over TCP works better) |
| **v6** | **PSK-derived deployment-level protocol diversity**, DNS address-family preference, multiple listening addresses |

</details>

Read [Inside Snell v6](https://nssurge.com/blog/snell-v6/) and the [official release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) for the design details.

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

Installation sets up dependencies, a random port, a 48-character random PSK and the system service, then prints a ready-to-use Surge proxy entry. Run the same command again to open the management menu.

> The installer currently uses the official **v6.0.0rc2** release candidate with `mode=default`. Your client must support Snell v6 and use the same `mode` as the server. Until the final v6 release, the protocol may still change incompatibly, so keep both client and server up to date (update the server with option **4**).

> CentOS support covers the maintained **CentOS Stream 9 / 10** (RHEL-compatible systems such as Rocky and AlmaLinux also install with `dnf`, and **Rocky Linux 8** is verified in CI); CentOS 7 (no `dnf`) is not supported, and end-of-life CentOS 8 is not recommended because its official repositories are offline. With firewalld enabled, allow the port with `firewall-cmd --permanent --add-port=PORT/tcp && firewall-cmd --reload`.

### What the installer does

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
| `2` | Uninstall after you type `y`: stop and verify the service, then remove the core, service and `/etc/snell` (including the PSK); also cleans up residues when the core is missing |
| `3` | Start or stop, according to the current state |
| `4` | Update the core and rewrite the service definition, keeping the running or stopped state |
| `5` | Restart and check the result |
| `6` | View service status |
| `7` | Follow logs on Debian / Ubuntu / CentOS; show troubleshooting steps on Alpine |
| `8` | Show the TCP port(s) to open, then regenerate and display the Surge proxy entry |
| `9` | Change configuration: port, mode and DNS |
| `0` | Exit |

If the service manager reports the service running, starting, stopping, restarting after a crash or crashed (OpenRC), but the core process or its listeners are unavailable, the menu shows an abnormal state and option **3** offers stop instead of start.

## Files and configuration

| Path | Purpose |
| :--- | :--- |
| `/usr/local/bin/snell-server` | Snell server binary |
| `/etc/snell/snell-server.conf` | Server settings: listeners, PSK, mode and DNS preference |
| `/etc/snell/snell-client.conf` | Generated Surge proxy entries; regenerated by option **8** |
| `/etc/systemd/system/snell.service` | Service definition on Debian / Ubuntu / CentOS; rewritten by option **4** |
| `/etc/init.d/snell` | OpenRC service definition on Alpine; rewritten by option **4** |

Use option **9** for supported configuration changes. If you edit the server file manually, use **5** to restart and **8** to refresh the client entries. Editing the exported client file does not change the server's port, PSK or mode. To customize the systemd service, use a drop-in (`systemctl edit snell`); direct edits to the service file are overwritten by option **4**.

The server configuration is readable by `root` and the `snell` group (`640`); the exported client file is restricted to `root` (`600`). Both contain credentials—redact them before sharing diagnostics.

## Configuration

Each change under option **9** keeps all other settings. A running service is restarted and checked; a stopped service stays stopped; while the service is starting or stopping, changes are refused until it settles or is stopped with **3**.

### Port · `9 → 1`

Enter a new port in `1–65535`. The script checks that the TCP port is free and updates the client entry; allow the new port in your firewall and update Surge afterwards. Entering the current port with unchanged listening addresses only refreshes the client entry, without a restart.

### Proxy mode · `9 → 2`

Options `1` `default`, `2` `unshaped` and `3` `unsafe-raw`; see [Three modes](#three-modes-for-different-needs) for the differences.

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
<summary><strong>Docker deployment</strong></summary>

On Debian, Ubuntu or Alpine with root, a Docker Compose deployment is also available:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/Snell/main/Snell-docker.sh)
```

- Installs Docker and the Compose plugin when missing, builds a local `snell-server` image from the official core (no third-party image) and runs it with host networking.
- Prints the Surge proxy entry, plus a `-v6` entry when the server has a public IPv6 address. Re-running keeps the existing port and PSK.
- Files live in `/root/snell-docker/`; the configuration is `snell-conf/snell.conf`.
- It is managed with `docker compose`, not this menu. Do not run both deployments on the same port.

Common commands and uninstall steps (in Chinese): [Snell-docker.md](Snell-docker.md).

</details>

<details>
<summary><strong>Updates, recovery and concurrency</strong></summary>

- **Updates** check required server settings and the service file before replacing the core, and are refused while the service is starting or stopping. Installed dependencies are reused and only missing packages are installed; if the new core fails to run (`-v` check), dependencies are repaired and the check retried once. If the restart after an update fails, the new core stays in place (no backup); diagnose with **7**. If the core is updated but the client entry cannot be generated, the unfinished step is reported; fix it and retry with option **8**.
- **Crash restarts**: the service manager restarts a crashed core after 3 s and gives up after 5 restarts within 60 s instead of looping; fix the cause, then restart with **5** (this also clears systemd's start limit).
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
- **Uninstall blocked**: if the service cannot be confirmed stopped, or a foreground Snell process is still running, uninstall keeps all files; stop it first and retry.
- **Reporting a bug**: include your OS, architecture, server and client versions, and relevant logs. Redact the PSK.

</details>

---

<div align="center">

**Continuously checked** · Native AMD64 and ARM64 CI on Debian, Ubuntu, CentOS Stream, Rocky Linux 8 and Alpine

Real dependency installs, all three protocol modes, five DNS preferences, and TCP and UDP payloads over IPv4 / IPv6;<br>
real systemd / OpenRC tests for permissions, repeat installs, configuration changes, failed-start recovery, crash restarts and restart limits, update preflight and service-file refresh, and uninstall.

<sub>Validate your public network path on your own deployment.</sub>

<br>

Protocol by the **Surge team** · This project focuses on Linux installation and management

[Inside Snell v6](https://nssurge.com/blog/snell-v6/) · [Official release notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) · [Report an issue](https://github.com/passeway/Snell/issues)

</div>
