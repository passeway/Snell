## 终端预览

![preview](image.png)


## 一键脚本

```
bash <(curl -fsSL snell-ten.vercel.app)
```
# Snell

Snell is a lean crypto proxy protocol developed by the Surge team. Here are some highlights:

* Extreme performance.
* Support UDP over TCP relay.
* Single binary with zero dependencies. (except glibc)
* A wizard to help you start.
* Proxy server will report remote errors to the client if an error encounters. Clients may choose countermeasures for different scenarios.

## 常用指令
```
[server_main] <NOTIFY> snell-server v6.0.0b1 (Jun 12 2026)
Usage: /usr/local/bin/snell-server [-v] [--help] [--license] [--wizard] [--systemd] [-l log level] [-c config]
An encrypted proxy service.

  --help                    display this help and exit
  -v, --version             display version info and exit
  --license                 display license info and exit
  --wizard                  use wizard to create a new server config
  --systemd                 use systemd socket activation
  -l, --loglevel=log level  set log level
  -c config                 config file

Config file parameters ([snell-server]):
  listen                    TCP listen address list. Format: host:port or [ipv6]:port. Multiple addresses can be separated by commas.
                            Example: listen = 0.0.0.0:7177,[::]:7177
  psk                       Pre-shared key. Required. Length must be between 16 and 255 bytes.
  dns                       Custom DNS server list separated by commas. Supports IPv4 and IPv6 server addresses.
  dns-ip-preference         DNS result IP preference: default, prefer-ipv4, prefer-ipv6, ipv4-only, ipv6-only.
  ipv-preference            Alias of dns-ip-preference.
  ipv6                      Deprecated compatibility option. false maps to ipv4-only; true maps to default unless dns-ip-preference is set.
  egress-interface          Bind outgoing TCP, UDP, and DNS sockets to the named network interface

```

## 项目地址：[https://kb.nssurge.com](https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell)



