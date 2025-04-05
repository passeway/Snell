#!/bin/bash

# 定义函数：检测 IP 类型并设置 DNS64（如果是纯 IPv6）
v4orv6() {
    echo "正在检测 IPv4 出口地址"
    
    # 判断 curl 是否能获取 IPv4 地址（使用 -s 静默，-4 强制 IPv4，-m5 超时5秒，-k 忽略证书）
    if [ -z "$(curl -s4m5 icanhazip.com -k)" ]; then
        echo
        echo -e "\e[33m检测到 纯 IPV6 VPS，正在写入 DNS64 配置到 /etc/resolv.conf...\e[0m"
        
        # 写入 DNS64 服务器
        cat > /etc/resolv.conf <<EOF
nameserver 2a00:1098:2b::1
nameserver 2a00:1098:2c::1
nameserver 2a01:4f8:c2c:123f::1
EOF

        # 设置 NAT64 Cloudflare DNS 对应的 IPv6 地址
        endip="2606:4700:d0::a29f:c101"
        ipv="prefer_ipv6"
    else
        echo -e "\e[32m检测到支持 IPv4，系统为双栈 VPS。\e[0m"
        endip="162.159.192.1"
        ipv="prefer_ipv4"
    fi

    # 输出结果
    echo -e "\n当前使用的出口地址：\e[36m$endip\e[0m"
    echo -e "IP 协议优先级设定：\e[35m$ipv\e[0m"
}

# 执行检测函数
v4orv6
