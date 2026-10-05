# 🚀 Snell 代理一键安装脚本

<div align="center">
  <img src="https://img.shields.io/badge/Snell-v6.0.0-blue?style=flat-square" alt="Snell Version" />
  <img src="https://img.shields.io/badge/Platform-Debian%20%7C%20Ubuntu%20%7C%20Alpine-lightgrey?style=flat-square" alt="Supported OS" />
  <img src="https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-orange?style=flat-square" alt="Supported Arch" />
  <img src="https://img.shields.io/github/license/passeway/Snell?style=flat-square" alt="License" />
</div>

<p align="center">
  <b>极简、高性能的 Snell 代理服务器一键部署管理脚本</b>
  <br />
  <a href="README.md">English</a> | <b>简体中文</b>
</p>

---

## ✨ 终端预览

![Terminal Preview](image.png)

## ⚡ 一键安装

只需在终端中运行以下命令即可快速安装：

```bash
bash <(curl -fsSL snell-ten.vercel.app)
```

Alpine 请先安装 Bash 和 curl，再从 Bash 启动脚本：

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://snell-ten.vercel.app)'
```

主脚本会自动安装 Alpine 其余依赖，日志位于 `/var/log/snell.log`。Docker 脚本保持原样。

## 🌟 核心特性

- **🚀 极致性能**：C 语言编写，单文件运行，除 glibc 外零依赖。
- **🛡️ v6 隐匿协议**：不再模仿 TLS 等传统协议，基于 PSK 派生独一无二的部署级流量特征（包含 42 个特征参数及 13 类填充整形策略）。
- **🔁 UDP over TCP**：完美支持 UDP 流量的可靠转发。
- **🛠️ 完善的服务管理**：支持一键安装、卸载、启动、停止、重启、更新及日志查看。
- **🌐 多网络栈控制**：支持 IPv4/IPv6 双栈监听，支持自定义 DNS 偏好及出口网卡绑定。
- **🐳 Docker 支持**：提供 `Snell-docker.sh` 脚本以支持容器化部署。

## 📦 支持环境

主脚本适配以下系统环境（amd64 / aarch64）：

- Debian / Ubuntu：使用 systemd
- Alpine：使用 OpenRC、gcompat 和 libstdc++

## 🛠️ 常用配置

服务端配置文件路径：`/etc/snell/snell-server.conf`

```ini
[snell-server]
listen = 0.0.0.0:7177,[::]:7177    # TCP 监听地址（支持多地址，逗号分隔）
psk = your_pre_shared_key          # 预共享密钥（16 - 255 字节）
# 运行模式，请确保服务端和客户端保持一致：
# - default: 启用混淆和 AES 加密
# - unshaped: 禁用混淆，仅使用 AES 加密，性能提升约 10%
# - unsafe-raw: 禁用加密和混淆，明文转发（仅限内网等安全环境）
mode = default                     
dns-ip-preference = default        # DNS 偏好：default, prefer-ipv4, prefer-ipv6, ipv4-only, ipv6-only
egress-interface = eth0            # (可选) 绑定出口网卡
```

## 📚 项目引用
- 官方发布说明：[Snell V6 Release Notes](https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell)
- Snell 是由 [Surge 团队](https://kb.nssurge.com/surge-knowledge-base) 开发的轻量级代理协议。


