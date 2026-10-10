<div align="center">

# Snell v6

### 一份密钥，一种流量特征。

**部署级协议多样性 · 低开销连接 · Surge 原生体验**

让 Snell v6 的协议能力，落在一次简洁的部署中。<br>
面向 Debian、Ubuntu 与 Alpine 的安装与管理工具。

![Snell](https://img.shields.io/badge/Snell-v6-635BFF?style=flat-square)
![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20Alpine-18181B?style=flat-square)
![Architecture](https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-18181B?style=flat-square)
[![Checks](https://github.com/passeway/Snell/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/passeway/Snell/actions/workflows/check.yml)

[English](README.md) · **简体中文**

[协议优势](#协议优势) · [快速部署](#快速部署) · [接入 Surge](#接入-surge) · [日常管理](#日常管理)

</div>

---

## 协议优势

### 协议特征，随部署而不同

**部署级协议多样性是 Snell v6 的核心升级。** 客户端与服务端根据 PSK 自动派生协议特征，改变分帧、填充和包长分布。使用不同 PSK 的部署呈现不同的流量特征，提高依靠统一协议指纹进行分类的成本。

| 42 个特征参数 | 13 类填充与流量整形策略 | PSK 自动派生 |
| :---: | :---: | :---: |
| 描述协议行为 | 组合形成不同流量特征 | 无需手动调节底层参数 |

这一设计来自 [Surge 团队对 Snell v6 的介绍](https://nssurge.com/blog/snell-v6/)。

### 低开销，同时保留连接细节

v6 延续了 Snell 的性能与兼容性设计：

| 能力 | 实际价值 |
| :--- | :--- |
| **0-RTT 协议设计** | 使用预共享密钥，减少代理层建立连接所需的往返 |
| **连接复用与完整 TCP 语义** | 保留半关闭等连接行为，兼顾复用与应用兼容性 |
| **准确的错误反馈** | 区分认证失败与目标连接失败，帮助 Surge 判断节点状态 |
| **UDP over TCP** | 通过 TCP 连接承载 UDP 转发，简化入口端口放行 |
| **更灵活的网络控制** | 支持 DNS 地址族偏好和多地址监听，适配不同出口环境 |

协议设计与模式说明见[官方发布说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)。本脚本会检测 IPv6 协议栈，自动配置 IPv4 或 IPv4 / IPv6 双栈监听。

## 把能力变成简单的部署

**准备好一台 VPS，即可使用服务器 IP、端口与 PSK 接入，无需准备域名或证书。**

- **开箱即用**：自动安装依赖，生成随机端口与 48 位随机 PSK，输出 Surge 代理条目。
- **适配三种系统**：Debian / Ubuntu 使用 systemd，Alpine 使用 OpenRC；支持 AMD64 与 ARM64。
- **集中管理**：安装、启停、重启、日志、端口 / 模式 / DNS 设置与配置导出，在同一个菜单完成。
- **结果可核实**：检查实际服务进程与监听端口，更新保留原有启停状态。

> 当前下载官方 **v6.0.0rc2** 测试版本，默认使用 `mode=default`，启用 AES 加密与流量整形。客户端需支持 Snell v6，服务端与客户端的 `mode` 必须一致。

## 快速部署

使用 **root** 用户执行。

### Debian / Ubuntu

在已安装 `bash`、`curl` 的终端执行：

```bash
bash <(curl -fsSL https://snell-ten.vercel.app)
```

### Alpine

```sh
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://snell-ten.vercel.app)'
```

**运行脚本 → 选择 `1` → 放行生成的 TCP 端口 → 导入 Surge。**

完整安装后再次选择 **1** 会保留原配置。此前安装中途失败时，会继续补齐缺失的安装步骤，保留已有端口、PSK 和服务端设置。更新内核使用 **4**，修改配置使用 **9**。

更新前先检查服务端必需配置，再替换内核。依赖齐全时直接复用，仅安装缺失的软件包；新内核运行检查失败时会修复依赖并重试一次。内核更新完成但客户端配置生成或写入失败时，会单独提示未完成的步骤，处理错误后可通过菜单 **8** 重试导出。

云安全组和系统防火墙均需放行实际监听端口。v6 使用 TCP 承载 UDP 转发，无需为此额外开放同端口 UDP。

IPv6 协议栈启用且存在 IPv6 地址时，自动监听 `0.0.0.0:端口,[::]:端口`；否则仅监听 IPv4。已有安装通过菜单 **4** 更新时会重新检测，手动指定的监听地址会保留。公网 IPv6 接入还需要服务器具有公网 IPv6 地址及对应的防火墙放行规则。网卡上有公网 IPv6 且服务监听 IPv6 时，除 IPv4 节点外还会导出一条名称带 `-v6` 的 IPv6 节点，端口取 IPv6 监听端口，PSK 和模式与 IPv4 节点相同。

## 接入 Surge

将脚本输出的代理条目放入 Surge 配置的 `[Proxy]` 部分：

```ini
[Proxy]
My-Snell = snell, YOUR_SERVER_IP, YOUR_PORT, psk=YOUR_PSK, version=6, mode=default, reuse=true
```

示例中的地址、端口和 PSK 为占位符，安装后直接复制实际输出即可。

菜单 **8** 从当前服务端配置重新读取端口、PSK 和模式，并保留已有有效地址与节点名。修改服务端配置后，先选择 **5** 重启，再选择 **8** 导出。

手动设置的 PSK 包含空格、逗号、引号等字符时，请复制完整导出条目，保留其中的引号和转义符。

IPv4 与 IPv6 使用不同端口时，导出的 IPv4 节点会匹配 IPv4 监听端口；无法确定对应端口时保留原客户端条目并提示检查。

## 更改 Snell 配置

选择菜单 **9 · 更改 Snell 配置**：

| 子菜单 | 功能 |
| :---: | :--- |
| `1. 端口` | 输入新端口，检查 TCP 占用并同步更新客户端条目 |
| `2. 模式` | 切换加密与流量整形模式 |
| `3. DNS` | 切换服务端 DNS 解析结果的地址族偏好 |
| `0. 返回` | 返回主菜单 |

端口范围为 `1–65535`，修改后请放行新的 TCP 端口并同步客户端配置。输入当前端口且监听地址不变时，只刷新客户端条目，不重启服务；需要自动调整 IPv6 监听时仍会应用更改。运行中的服务应用配置后会重启并检查状态；已停止的服务保持停止。写入或重启失败时尝试恢复原配置，不生成备份文件。

同一时间只允许一个管理操作修改配置或服务状态。另一个终端正在操作时，请等待其完成后重试。

### 代理模式

进入 **9 → 2**，查看当前配置模式并选择：

| 选项 | 模式 | 特点与适用场景 |
| :---: | :--- | :--- |
| `1` | `default` | AES 加密与流量整形，默认选择 |
| `2` | `unshaped` | 保留 AES 加密，关闭流量整形 |
| `3` | `unsafe-raw` | 关闭加密与流量整形，明文传输，仅适合内网或已有安全隧道的环境 |
| `0` | 返回 | 保留当前配置 |

模式切换保留端口、PSK 和其他服务端设置，并重新生成客户端条目。

**切换后请将输出的新条目同步到 Surge，客户端与服务端的 `mode` 必须一致。** 模式定义见[官方发布说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)。

### DNS 模式

进入 **9 → 3**：

| 选项 | 配置值 | 作用 |
| :---: | :--- | :--- |
| `1` | `default` | 使用 Snell 默认策略 |
| `2` | `prefer-ipv4` | 优先使用 IPv4 解析结果 |
| `3` | `prefer-ipv6` | 优先使用 IPv6 解析结果 |
| `4` | `ipv4-only` | 仅使用 IPv4 解析结果 |
| `5` | `ipv6-only` | 仅使用 IPv6 解析结果 |

DNS 模式调整服务端连接目标域名时的地址族偏好，继续使用已有 DNS 服务器设置，未自定义时使用系统 DNS。选择仅 IPv6 前，请确认服务器有可用的 IPv6 出口。DNS 模式与入站双栈监听分别配置，修改 DNS 模式无需重新导入客户端条目。

同时存在 `dns-ip-preference` 与别名 `ipv-preference` 时，菜单按内核规则读取最后出现的值；选择模式后会统一为一项 `dns-ip-preference` 设置。

## 日常管理

再次运行安装命令，即可打开管理菜单。

服务管理器报告运行、但实际内核进程或监听不可用时，菜单会显示异常状态，同时保留停止该服务的选项。

内核文件缺失时，仍可使用菜单 **2** 清理安装残留。若还有前台运行的 Snell 排错进程，卸载会保留文件并提示先结束该进程。

| 选项 | 功能 |
| :---: | :--- |
| `1` | 安装 Snell 服务 |
| `2` | 停止并确认服务已停后卸载 |
| `3` | 根据运行状态显示启动或停止 |
| `4` | 更新内核，保留原有启停状态 |
| `5` | 重启服务并检查运行结果 |
| `6` | 查看服务状态 |
| `7` | Debian / Ubuntu 查看实时日志；Alpine 查看排错说明 |
| `8` | 重新生成并查看 Surge 代理条目 |
| `9` | 更改 Snell 配置：端口、模式、DNS |
| `0` | 退出 |

<details>
<summary><strong>连接异常时，先检查这几项</strong></summary>

确认服务正在运行，TCP 端口已放行，客户端的地址、端口、PSK、版本和模式与服务端一致。

Debian / Ubuntu：

```bash
systemctl status snell --no-pager
journalctl -u snell -n 50 --no-pager
```

Alpine：

```sh
rc-service snell status
```

Alpine 默认不保存 Snell 日志，也不配置日志轮转或定时任务。如需临时排查，先执行 `rc-service snell stop`，再运行 `/usr/local/bin/snell-server -l info -c /etc/snell/snell-server.conf`，日志仅显示在终端。结束后按 `Ctrl+C`，执行 `rc-service snell start` 恢复服务。Debian / Ubuntu 的实时日志按 `Ctrl+C` 返回菜单。

公网 IPv4 自动查询失败时，可手动输入；取消后可通过菜单 **8** 重试。国家信息不可用时，节点名称默认使用 `Snell`。

反馈问题时请附上系统、架构、服务端与客户端版本及错误日志，并隐藏 PSK。

</details>

---

**持续验证** · AMD64 与 ARM64 原生 CI 覆盖 Debian、Ubuntu 和 Alpine，实际安装脚本依赖，验证三种协议模式、五种 DNS 偏好、IPv4 / IPv6 连接中的真实 TCP 与 UDP 数据转发及不同监听端口。真实 systemd / OpenRC 服务测试同时覆盖服务用户权限、重复安装、配置更改、启动失败恢复、更新预检和卸载。公网线路表现仍需在部署环境中验证。

<div align="center">

协议由 **Surge 团队** 开发 · 本项目专注 Linux 安装与管理

[Snell v6 技术介绍](https://nssurge.com/blog/snell-v6/) · [官方发布说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) · [反馈问题](https://github.com/passeway/Snell/issues)

</div>
