# 🚀 Snell Proxy Installer

<div align="center">
  <img src="https://img.shields.io/badge/Snell-v6.0.0-blue?style=flat-square" alt="Snell Version" />
  <img src="https://img.shields.io/badge/Platform-Debian%20%7C%20CentOS%20%7C%20ArchLinux-lightgrey?style=flat-square" alt="Supported OS" />
  <img src="https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-orange?style=flat-square" alt="Supported Arch" />
  <img src="https://img.shields.io/github/license/passeway/Snell?style=flat-square" alt="License" />
</div>

<p align="center">
  <b>A minimalist, high-performance Snell proxy server one-click deployment script.</b>
  <br />
  <b>English</b> | <a href="README_zh.md">简体中文</a>
</p>

---

## ✨ Terminal Preview

![Terminal Preview](image.png)

## ⚡ Quick Install

Run the following command in your terminal to start the installation:

```bash
bash <(curl -fsSL snell-ten.vercel.app)
```

## 🌟 Key Features

- **🚀 Extreme Performance**: Written in C, single binary with zero dependencies (except glibc).
- **🛡️ v6 Stealth Protocol**: Moves away from TLS impersonation. Generates a deployment-specific protocol profile derived from your PSK (features 42 characteristic parameters and 13 traffic-shaping strategies).
- **🔁 UDP over TCP**: Fully supports UDP traffic relay over TCP connections.
- **🛠️ Service Management**: Built-in wizard for easy installation, uninstallation, starting, stopping, restarting, updating, and log viewing.
- **🌐 Network Stack Control**: Explicitly supports dual-stack listening (IPv4/IPv6), customizable DNS IP preference, and egress interface binding.
- **🐳 Docker Support**: Provides `Snell-docker.sh` for easy containerized deployments.

## 📦 Supported Environments

The script has been tested and supports the following systems (amd64 / aarch64):

- Debian 10+ / Ubuntu 18.04+
- CentOS 7+ / RHEL / AlmaLinux / RockyLinux
- Arch Linux

## 🛠️ Configuration Guide

Server config file path: `/etc/snell/snell-server.conf`

```ini
[snell-server]
listen = 0.0.0.0:7177,[::]:7177    # TCP listen addresses (comma-separated)
psk = your_pre_shared_key          # Pre-shared key (16 - 255 bytes)
# Operating mode. Ensure server and client modes are consistent:
# - default: Enables traffic obfuscation and AES encryption.
# - unshaped: Disables obfuscation, AES only (10% faster).
# - unsafe-raw: No encryption or obfuscation (secure environments only).
mode = default                     
dns-ip-preference = default        # Options: default, prefer-ipv4, prefer-ipv6, ipv4-only, ipv6-only
egress-interface = eth0            # (Optional) Bind outgoing sockets to an interface
```

## 📚 References
- Official Release Notes: [Snell V6 Release Notes](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)
- Snell is a lightweight proxy protocol developed by the [Surge Team](https://kb.nssurge.com/surge-knowledge-base).


