<div align="center">

# Snell v6

### 一份密钥，一种流量特征

**Snell** 是 Surge 团队设计的轻量加密代理协议。<br>
**v6** 引入部署级协议多样性：每个部署由自己的 PSK 派生独有的流量特征。

![Snell](https://img.shields.io/badge/Snell-v6-635BFF?style=flat-square)
![Linux](https://img.shields.io/badge/Linux-Debian%20%7C%20Ubuntu%20%7C%20CentOS%20%7C%20Alpine-18181B?style=flat-square)
![Architecture](https://img.shields.io/badge/Arch-AMD64%20%7C%20ARM64-18181B?style=flat-square)
[![Checks](https://github.com/passeway/Snell/actions/workflows/check.yml/badge.svg?branch=main)](https://github.com/passeway/Snell/actions/workflows/check.yml)

[English](README.md) · **简体中文**

[v6 的优势](#snell-v6-的优势) · [快速开始](#快速开始) · [接入 Surge](#接入-surge) · [管理菜单](#管理菜单) · [调整配置](#调整配置) · [进阶说明](#进阶说明)

</div>

---

## Snell v6 的优势

> **v6 不伪装 TLS，也不模仿任何现有协议，而是让每个部署各不相同。**<br>
> 客户端与服务端根据 PSK 自动派生一份协议画像（protocol profile），决定分帧、填充、包长分布与流量归一化等可观测行为。只要 PSK 不同，流量特征就不同，不再存在所有 Snell v6 部署共用的稳定流量模式。

| **42** | **13** | **0** |
| :---: | :---: | :---: |
| 个特征参数 | 类填充与流量整形策略，可自由组合 | 个需要手动调节的参数，画像全部由 PSK 派生 |

### 为什么走第三条路

| 思路 | 做法 | 局限 |
| :--- | :--- | :--- |
| 纯加密 | 尽量减少协议结构，输出高熵随机流 | “完全随机”本身就是可识别的特征 |
| 模仿常见协议 | 让流量看起来像 TLS 等协议 | 需要持续追随被模仿协议的细节 |
| **Snell v6** | **部署级协议多样性** | 分类器面对的不再是一个固定指纹，而是大量各不相同的部署特征 |

v4 曾在 AES 加密流中加入受控随机扰动，四年来效果良好；但所有部署共享同一类扰动，一旦被针对性研究就会成为特征。v6 把“一种协议、一种特征”变成“一个部署、一种特征”。

**画像由 PSK 自动派生**有两个好处：部署方式和以前一样简单，无需学习任何底层参数；同时避免大家复制同一份配置导致特征趋同，让各部署自然地彼此不同。

### 延续 Snell 一贯的优势

| 能力 | 带来什么 |
| :--- | :--- |
| **性能优先** | 从 v1 起以延迟和吞吐为首要目标，性能接近代理协议的实际上限 |
| **单文件部署** | 单个二进制、依赖极少，安装与维护简单 |
| **准确的错误反馈** | 区分认证失败与目标连接超时，Surge（尤其是 Smart 策略组）据此准确判断节点健康 |
| **连接复用 + 完整 TCP 状态机** | 少数同时支持复用与完整 TCP 语义的协议，依赖半关闭的应用也能正常工作 |
| **0-RTT** | 预共享密钥认证，减少建立代理连接所需的往返 |
| **UDP 转发** | 由 TCP 承载，只需放行一个 TCP 端口 |

### v6 新增的网络控制

- **`dns-ip-preference`**：解析目标域名时的地址族偏好，支持 `default`、`prefer-ipv4`、`prefer-ipv6`、`ipv4-only`、`ipv6-only` 五种模式，适配双栈、IPv6 优先或单栈出口环境。
- **多地址监听**：`listen = 0.0.0.0:端口,[::]:端口` 同时显式监听 IPv4 与 IPv6，不依赖系统对 IPv6 套接字的兼容行为。本脚本默认即按此方式生成。

### 三种模式，按场景取舍

| 模式 | 加密 | 流量整形 | 适用场景 |
| :--- | :---: | :---: | :--- |
| `default` | AES | ✓ | 默认推荐，完整发挥 v6 的流量特征多样性 |
| `unshaped` | AES | — | 保留加密、关闭整形，减少填充带来的额外流量 |
| `unsafe-raw` | — | — | 明文传输，仅适合内网或已有安全隧道的环境 |

<details>
<summary><strong>Snell 版本演进</strong></summary>

| 版本 | 主要变化 |
| :---: | :--- |
| v1 | 结构化错误反馈、单文件部署、性能优先 |
| v2 | 连接复用，同时保留完整 TCP 状态机 |
| v3 | UDP 转发 |
| v4 | 在 AES 加密流中加入受控随机扰动，避免“完全随机”的特征 |
| v5 | QUIC 代理模式（v6 已移除：QUIC 难以有效代理，更好的做法是屏蔽 QUIC，让应用回退到基于 TCP 的 HTTP/2） |
| **v6** | **由 PSK 派生的部署级协议多样性**、DNS 地址族偏好、多地址监听 |

</details>

设计细节见 [Snell v6 技术介绍](https://nssurge.com/blog/snell-v6/) 与 [官方发布说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell)。

---

## 快速开始

使用 **root** 用户执行，无需域名或证书。

```bash
# Debian / Ubuntu / CentOS
bash <(curl -fsSL https://snell-ten.vercel.app)
```

```sh
# Alpine
apk add --no-cache bash curl ca-certificates
bash -c 'bash <(curl -fsSL https://snell-ten.vercel.app)'
```

**① 选择 `1` 安装 → ② 在云安全组和防火墙放行输出的 TCP 端口 → ③ 将代理条目导入 Surge**

安装会自动完成依赖、随机端口、48 位随机 PSK 与服务注册，并在最后输出可直接使用的 Surge 代理条目。再次运行同一命令即可打开管理菜单。

> 当前安装官方 **v6.0.0rc2** 测试版本，默认 `mode=default`。客户端需支持 Snell v6，且 `mode` 与服务端一致。测试期间协议可能出现不兼容变更，请让客户端与服务端都保持最新版本（服务端用菜单 **4** 更新）。

> CentOS 支持仍在维护的 **CentOS Stream 9 / 10**（Rocky、AlmaLinux 等 RHEL 兼容系统同样使用 `dnf` 安装，**Rocky Linux 8** 已在 CI 中验证）；不带 `dnf` 的 CentOS 7 不受支持；CentOS 8 已停止维护、官方软件源已下线，不建议使用。启用了 firewalld 时，放行端口可执行 `firewall-cmd --permanent --add-port=端口/tcp && firewall-cmd --reload`。

### 这个脚本做了什么

- **多系统，一致体验**：Debian / Ubuntu / CentOS 使用 systemd，Alpine 使用 OpenRC，支持 AMD64 与 ARM64。
- **自动双栈**：检测到 IPv6 时监听 `0.0.0.0:端口,[::]:端口`，找到公网 IPv6 地址时额外导出 IPv6 节点。
- **结果可核实**：启动、重启后检查真实的内核进程与监听端口，而不只是服务管理器的状态。
- **安全的变更**：修改配置失败或被中断时自动恢复原配置；更新保留原有启停状态；同一时间只允许一个管理操作。

---

## 接入 Surge

将安装输出的条目放入 Surge 配置的 `[Proxy]` 部分：

```ini
[Proxy]
My-Snell = snell, YOUR_SERVER_IP, YOUR_PORT, psk=YOUR_PSK, version=6, mode=default, reuse=true
```

示例中的地址、端口和 PSK 为占位符，请直接复制实际输出。

- **重新导出**：菜单 **8** 从当前服务端配置读取端口、PSK 和模式，保留已有地址与节点名（包括改过名的 IPv6 节点）。
- **手动改过服务端配置**：先用 **5** 重启，再用 **8** 导出。
- **PSK 含空格、逗号或引号**：请复制完整条目，保留其中的引号和转义符。

## 管理菜单

| 选项 | 功能 |
| :---: | :--- |
| `1` | 安装；上次中途失败时补齐缺失步骤，保留已有端口、PSK 与设置 |
| `2` | 直接卸载（无二次确认）：停止并确认服务已停后，删除内核、服务与 `/etc/snell`（含 PSK）；内核缺失时也可清理残留 |
| `3` | 按当前状态启动或停止 |
| `4` | 更新内核并重写服务定义，保留原有启停状态 |
| `5` | 重启并检查运行结果 |
| `6` | 查看服务状态 |
| `7` | Debian / Ubuntu / CentOS 查看实时日志；Alpine 显示排错说明 |
| `8` | 重新生成并查看 Surge 代理条目 |
| `9` | 调整配置：端口、模式、DNS |
| `0` | 退出 |

服务管理器报告运行、启动中、停止中、崩溃后重启中或已崩溃（OpenRC），但内核进程或监听实际不可用时，菜单显示“异常”，选项 **3** 提供停止而非启动。

## 文件与配置位置

| 路径 | 用途 |
| :--- | :--- |
| `/usr/local/bin/snell-server` | Snell 服务端程序 |
| `/etc/snell/snell-server.conf` | 服务端监听地址、PSK、模式与 DNS 偏好 |
| `/etc/snell/snell-client.conf` | 导出的 Surge 代理条目，菜单 **8** 会重新生成 |
| `/etc/systemd/system/snell.service` | Debian / Ubuntu / CentOS 的服务定义；菜单 **4** 会重写 |
| `/etc/init.d/snell` | Alpine 的 OpenRC 服务定义；菜单 **4** 会重写 |

常规配置调整使用菜单 **9**。手动编辑服务端文件后，使用 **5** 重启，再使用 **8** 刷新客户端条目。修改导出的客户端文件，不会改变服务端端口、PSK 或模式。如需自定义 systemd 服务，请使用 drop-in（`systemctl edit snell`），直接修改服务文件会被菜单 **4** 覆盖。

服务端配置允许 `root` 与 `snell` 组读取（权限 `640`）；客户端导出文件仅允许 `root` 读写（权限 `600`）。两者均包含连接凭据，分享排错信息前请隐藏这些内容。

## 调整配置

菜单 **9** 下的三项调整都会保留其余设置。运行中的服务会自动重启并检查；已停止的服务保持停止；服务正在启动或停止时拒绝修改，请稍后重试或先用 **3** 停止。

### 端口 · `9 → 1`

输入 `1–65535` 的新端口。脚本会检查 TCP 占用并同步更新客户端条目，修改后请放行新端口并更新 Surge。输入当前端口且监听地址不变时，只刷新客户端条目、不重启服务。

### 代理模式 · `9 → 2`

选项 `1` `default`、`2` `unshaped`、`3` `unsafe-raw`，区别见 [三种模式](#三种模式按场景取舍)。

**切换后请把新条目同步到 Surge**：客户端与服务端的 `mode` 必须一致。

### DNS 偏好 · `9 → 3`

| 选项 | 配置值 | 作用 |
| :---: | :--- | :--- |
| `1` | `default` | Snell 默认策略 |
| `2` | `prefer-ipv4` | 优先 IPv4 解析结果 |
| `3` | `prefer-ipv6` | 优先 IPv6 解析结果 |
| `4` | `ipv4-only` | 仅 IPv4 解析结果 |
| `5` | `ipv6-only` | 仅 IPv6 解析结果，需可用的 IPv6 出口 |

DNS 偏好只影响服务端连接目标域名时的地址族，继续使用已有 DNS 服务器（未设置时使用系统 DNS），无需重新导入客户端条目。

---

## 进阶说明

<details>
<summary><strong>IPv4 / IPv6 双栈与 IPv6 节点</strong></summary>

- IPv6 协议栈启用且存在 IPv6 地址时，自动监听 `0.0.0.0:端口,[::]:端口`，否则仅监听 IPv4。菜单 **4** 更新时会重新检测；手动指定的监听地址会保留。
- 服务监听 IPv6 且可从外部连接时，除 IPv4 节点外还会导出一条名称带 `-v6` 的 IPv6 节点：
  - 监听 `[::]` 时，使用默认 IPv6 路由所在网卡上的公网地址，WARP 等仅出站隧道的地址除外；
  - 监听指定公网 IPv6 时，直接使用该地址；
  - 回环、链路本地和内网地址不导出。
- IPv6 节点的端口取 IPv6 监听端口，PSK 与模式和 IPv4 节点相同。
- IPv4 与 IPv6 使用不同端口时，IPv4 节点匹配 IPv4 监听端口；无法确定时保留原客户端条目并提示检查。
- 公网 IPv6 接入同样需要在防火墙中放行端口。v6 用 TCP 承载 UDP 转发，无需额外开放同端口 UDP。

</details>

<details>
<summary><strong>更新、恢复与并发</strong></summary>

- **更新**：先检查服务端必需配置与服务文件，再替换内核；服务正在启动或停止时拒绝更新。依赖齐全时直接复用，只安装缺失的软件包；新内核无法运行（`-v` 检查）时修复依赖并重试一次。更新后重启失败时保留新内核（不保留旧版备份），请用 **7** 排查。内核已更新但客户端条目生成失败时，会单独提示未完成的步骤，处理后可用菜单 **8** 重试。
- **崩溃重启**：内核异常退出后，服务管理器 3 秒后自动重启，60 秒内重启 5 次后停止重试，不会无限循环；排除原因后用 **5** 重启（同时清除 systemd 的启动频率限制）。
- **配置变更**：写入或重启失败、或被中断时，自动恢复原配置，不生成备份文件。
- **并发**：同一时间只允许一个管理操作修改配置或服务状态，另一个终端会提示稍后重试。
- **DNS 别名**：同时存在 `dns-ip-preference` 与别名 `ipv-preference` 时，按内核规则读取最后出现的值；在菜单中选择后会统一为一项 `dns-ip-preference`。

</details>

<details>
<summary><strong>连接异常时，先检查这几项</strong></summary>

确认服务正在运行、TCP 端口已放行，客户端的地址、端口、PSK、版本和模式与服务端一致。

```bash
# Debian / Ubuntu / CentOS
systemctl status snell --no-pager
journalctl -u snell -n 50 --no-pager
```

```sh
# Alpine
rc-service snell status
```

- **Alpine 日志**：默认不保存 Snell 日志，也不配置日志轮转或定时任务。临时排查时先执行 `rc-service snell stop`，再运行 `/usr/local/bin/snell-server -l info -c /etc/snell/snell-server.conf` 在终端查看输出；结束后按 `Ctrl+C`，执行 `rc-service snell start` 恢复服务。
- **实时日志**：Debian / Ubuntu / CentOS 的菜单 **7** 中按 `Ctrl+C` 返回菜单。
- **公网 IPv4 查询失败**：可手动输入；取消后可用菜单 **8** 重试。国家信息不可用时，节点名默认为 `Snell`。
- **卸载被阻止**：服务无法确认已停止，或仍有前台运行的 Snell 进程时，卸载会保留全部文件；请先停止后重试。
- **反馈问题**：请附上系统、架构、服务端与客户端版本及错误日志，并隐藏 PSK。

</details>

---

<div align="center">

**持续验证** · AMD64 与 ARM64 原生 CI 覆盖 Debian、Ubuntu、CentOS Stream、Rocky Linux 8 与 Alpine

真实安装依赖，验证三种协议模式、五种 DNS 偏好与 IPv4 / IPv6 下的 TCP、UDP 转发；<br>
在真实 systemd / OpenRC 中测试权限、重复安装、配置变更、启动失败恢复、崩溃重启与次数上限、更新预检与服务文件刷新以及卸载。

<sub>公网线路表现仍需在你的部署环境中验证。</sub>

<br>

协议由 **Surge 团队** 开发 · 本项目专注 Linux 安装与管理

[Snell v6 技术介绍](https://nssurge.com/blog/snell-v6/) · [官方发布说明](https://kb.nssurge.com/surge-knowledge-base/release-notes/snell) · [反馈问题](https://github.com/passeway/Snell/issues)

</div>
