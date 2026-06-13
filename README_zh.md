# Snell 一键安装脚本

[English](README.md) | [简体中文](README_zh.md)

## 终端预览

![preview](image.png)

## 一键安装

```bash
bash <(curl -fsSL snell-ten.vercel.app)
```

# Snell

Snell 是由 Surge 团队开发的轻量级加密代理协议。主要特点：

* 极致性能
* 支持 UDP over TCP 转发
* 单一二进制文件，零依赖（除 glibc 外）
* 内置向导帮助快速启动
* 代理服务器遇到错误时会向客户端报告远程错误，客户端可根据不同场景选择应对措施

# Snell v6

对于加密代理协议，通常有两种方法来降低协议可识别性。

第一种方法是最小化协议特定结构，暴露尽可能少的可识别元数据。传统加密代理协议通常属于这一类。

如上所述，纯加密协议会产生高熵随机数据流。讽刺的是，缺乏明显结构本身可能成为一种结构。这种特征已被发现是可检测的，这就是为什么加密代理协议的设计空间持续演进。

第二种方法是使协议与常见协议（如 TLS）高度相似。许多新型代理协议已经探索了这个方向，并且已经有一些优秀的项目。

Snell v6 采取了不同的路径。

它不试图模仿 TLS 或任何其他现有协议。相反，Snell v6 从单一的协议级流量模式转向基于 PSK 派生的部署级多样性。

在 Snell v4 中，所有部署共享相同的一般协议行为，包括相同类别的随机扰动。Snell v6 通过生成特定于部署的协议配置文件来改变这一模型。

更具体地说，Snell v6 基于协议配置文件运行。此配置文件包含 42 个特征参数和 13 类填充及流量整形策略，可以不同的方式组合。这些参数控制加密流的多个可观察方面，包括帧行为、填充行为、数据包大小分布和流量规范化。

配置文件示例如下：

```c
static const sn_shape_profile_t sample_profile = {
    .profile_id = 0x6a31c4d2,

    .pre_salt_min = 37,
    .pre_salt_max = 91,
    .salt_permutation_rounds = 5,
    .salt_mask_stride = 11,

    .header_prefix_min = 12,
    .header_prefix_max = 44,

    .padding_generator = SN_SHAPE_PAD_GEN_BLOCK_MIXTURE,
    .padding_min = 48,
    .padding_max = 220,
    .padding_chunk_count = 4,
    .padding_interval = 3,
    .padding_small_payload_limit = 384,

    .bit_ratio_min = 86,
    .bit_ratio_max = 132,

    .histogram_low_weight = 38,
    .histogram_mid_weight = 146,
    .histogram_high_weight = 73,
    .nibble_low_mask = 0x5b,
    .block_motif_count = 5,
    .block_repeat_window = 17,

    .mix_mode = SN_SHAPE_MIX_OFFSET_STRIDE_SWAP,
    .mix_rounds = 3,
    .mix_stride = 19,
    .mix_offset = 7,
    .mix_block_size = 11,

    .chunk_policy = SN_SHAPE_CHUNK_BUCKETED,
    .chunk_initial_size = 612,
    .chunk_max_size = 4096,
    .chunk_growth_step = 431,
    .chunk_jitter = 96,
    .chunk_bucket_count = 5,
    .chunk_buckets = {
        517, 863, 1291, 2047, 3079
    },
    .idle_reset_seconds = 8,

    .write_policy = SN_SHAPE_WRITE_FIXED_SEQUENCE,
    .first_write_count = 5,
    .write_bucket_count = 5,
    .write_buckets = {
        233, 377, 610, 987, 1597
    },
    .write_sequence_count = 6,
    .write_sequence = {
        233, 610, 377, 987, 610, 1597
    },
    .write_jitter = 64,
    .write_payload_factor = 3,
};
```

不同的配置文件导致不同的可观察流量特征。只要不同的服务器使用不同的配置文件，就不再有所有 Snell v6 部署共享的单一稳定流量模式。

这显著增加了协议分类的成本。分类器不需要匹配一个固定的协议指纹，而是需要考虑大量特定于部署的行为。

## 自动配置

同时，用户不需要手动配置或调整这些复杂的配置文件。Snell v6 客户端和服务器会从配置的 PSK 自动派生协议配置文件。

换句话说，只要 PSK 不同，产生的协议特性也会不同。

这种设计有两个重要优点：

首先，它保持部署简单。用户可以继续以熟悉的方式配置 Snell，无需学习或维护大量底层协议参数。

其次，它防止配置文件同质化。如果用户必须手动选择或复制协议配置文件，许多部署最终不可避免地会共享相同的配置，这将违背指纹多样性的目的。通过从 PSK 自动派生配置文件，Snell v6 确保部署自然地彼此分化。

通过 Snell v6，我们的目标不是模仿特定的现有协议。相反，Snell v6 在部署级别引入受控的协议多样性，同时保持 Snell 长期以来的优先事项：性能、部署简单性、准确的错误报告和完整的 TCP 语义。

## 更多功能

此版本为服务器添加了更灵活的网络栈控制能力。首先，新增了 `dns-ip-preference` 配置项，允许在使用 DNS 解析结果时指定 IP 地址族偏好。它支持五种模式：`default`、`prefer-ipv4`、`prefer-ipv6`、`ipv4-only` 和 `ipv6-only`，使得在双栈网络、IPv6 优先网络或仅具有 IPv4/IPv6 出口的环境中更容易稳定地控制连接行为。

其次，`listen` 现在支持同时配置多个监听地址，例如 `listen = 0.0.0.0:7177,[::]:7177`，这样服务器可以同时显式监听 IPv4 和 IPv6 地址，而无需依赖系统对 IPv6 套接字的兼容性行为。新的 `--help` 也已更新相关配置说明。

## 使用方法

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

## 项目地址

[https://kb.nssurge.com](https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell)
