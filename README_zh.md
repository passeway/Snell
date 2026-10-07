<div align="center">

# Snell

### 轻量部署，从容管理。

面向 Debian · Ubuntu · Alpine 的 Snell v6 安装与管理脚本。

[![Checks](https://github.com/passeway/Snell/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/passeway/Snell/actions/workflows/check.yml)
![Platform](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20Alpine-2563eb?style=flat-square)
![Architecture](https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-475569?style=flat-square)
[![License](https://img.shields.io/github/license/passeway/Snell?style=flat-square)](LICENSE)

[English](README.md) · **简体中文**

[快速开始](#快速开始) · [日常管理](#日常管理) · [客户端配置](#客户端配置) · [问题反馈](https://github.com/passeway/Snell/issues)

</div>

---

一个交互菜单，完成 Snell 服务的安装、启停、更新和配置查看。自动适配 systemd 与 OpenRC，为 Surge 生成可直接复制的代理条目。

| 部署 | 管理 | 连接 |
| :--- | :--- | :--- |
| Debian、Ubuntu、Alpine | 服务启停、重启与内核更新 | 自动生成 Surge 代理条目 |
| AMD64、ARM64 | 安装状态、运行状态与版本展示 | 随机端口与 PSK |
| 自动安装所需依赖 | 状态查询与实时日志 | 从当前服务端配置重新导出 |

## 快速开始

以 **root** 身份运行。脚本当前下载版本为 **v6.0.0rc2**，服务端版本输出可能显示为 **v6.0.0**。

### Debian / Ubuntu

在已安装 `bash`、`curl` 的终端执行：

```bash
bash <(curl -fsSL snell-ten.vercel.app)
```

### Alpine

首次运行先安装命令依赖：

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://snell-ten.vercel.app)'
```

**运行脚本 → 选择 `1` 安装 → 放行生成的 TCP 端口 → 复制代理条目至 Surge。**

> [!IMPORTANT]
> 云安全组和服务器防火墙需要放行实际监听的 TCP 端口。Snell 通过 TCP 承载 UDP 转发，无需为此额外开放同端口 UDP。

## 支持环境

| 系统 | 服务管理 | 架构 |
| :--- | :--- | :--- |
| Debian | systemd | AMD64 / ARM64 |
| Ubuntu | systemd | AMD64 / ARM64 |
| Alpine | OpenRC | AMD64 / ARM64 |

Alpine 所需的 `gcompat`、`libstdc++` 等依赖由主脚本安装。上述支持范围针对主安装脚本。

## 日常管理

重新运行安装命令即可打开菜单。安装后，选项 `3` 会根据运行状态显示启动或停止。

| 选项 | 操作 |
| :---: | :--- |
| `1` | 安装 Snell 服务 |
| `2` | 停止并确认服务已停后卸载 |
| `3` | 启动或停止服务 |
| `4` | 更新 Snell 内核，保留原有启停状态 |
| `5` | 重启 Snell 服务 |
| `6` | 查看 Snell 状态 |
| `7` | 查看实时日志，按 `Ctrl+C` 返回菜单 |
| `8` | 根据当前服务端配置重新生成并查看客户端条目 |
| `0` | 退出 |

## 客户端配置

安装完成后，复制脚本输出的代理条目，放入 Surge 配置的 `[Proxy]` 部分：

```ini
[Proxy]
My-Snell = snell, YOUR_SERVER_IP, YOUR_PORT, psk=YOUR_PSK, version=6, mode=default, reuse=true
```

示例中的地址、端口和 PSK 均为占位符，请替换为实际值；客户端需支持 Snell v6。

- 菜单 **8** 同步服务端的端口、PSK 和 `mode`，保留已有有效 IPv4 地址和节点名。
- 公网 IPv4 查询包含超时控制和备用接口；全部失败时可手动输入，留空取消后可从菜单 **8** 重试。
- 修改服务端配置后，先选择 **5** 重启，再选择 **8** 重新导出。服务端与客户端的 `mode` 需保持一致。

### 常用路径

| 路径 | 用途 |
| :--- | :--- |
| `/usr/local/bin/snell-server` | Snell 服务端程序 |
| `/etc/snell/snell-server.conf` | 服务端配置 |
| `/etc/snell/snell-client.conf` | 生成的 Surge 代理条目 |

服务端配置权限为 `root:snell 640`，客户端配置权限为 `root:root 600`。

## 排查问题

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

日志每小时检查一次，超过 1 MiB 时轮转，最多保留 3 份压缩归档。轮转配置位于 `/etc/snell/logrotate.conf`。检查间隔内日志仍可能增长，`copytruncate` 存在短暂的复制与截断丢日志窗口。

</details>

| 现象 | 优先检查 |
| :--- | :--- |
| 客户端连接超时 | 服务状态、监听端口、云安全组和本机防火墙 |
| 更改配置后无法连接 | 地址、端口、PSK、版本和模式是否一致；是否已重启并重新导出 |
| 公网地址获取失败 | 手动输入服务器公网 IPv4，再通过菜单 `8` 生成条目 |

反馈问题时请提供系统、CPU 架构、服务端与客户端版本和相关日志，并隐藏 PSK。

自动检查在 Debian、Ubuntu、Alpine 容器中执行语法、失败场景回归测试，以及官方 Snell v6 内核与独立客户端的真实代理传输测试。服务管理操作使用模拟命令，本地代理测试不替代你的 VPS 端到端验证。

---

<div align="center">

Snell 协议由 [Surge 团队](https://kb.nssurge.com/surge-knowledge-base) 开发 · 本仓库为独立安装与管理脚本项目

[官方发布说明](https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell) · [提交问题](https://github.com/passeway/Snell/issues) · [查看检查结果](https://github.com/passeway/Snell/actions)

</div>

