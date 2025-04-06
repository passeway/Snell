#!/bin/bash

# 检测是否为纯 IPv6，并设置 DNS64
v4orv6() {
    echo "正在检测 IPv4 出口地址..."
    
    if [ -z "$(curl -s4m5 icanhazip.com -k)" ]; then
        echo
        echo -e "\e[33m检测到纯 IPv6 VPS，正在写入 DNS64 配置到 /etc/resolv.conf...\e[0m"
        
        cat > /etc/resolv.conf <<EOF
nameserver 2a00:1098:2b::1
nameserver 2a00:1098:2c::1
nameserver 2a01:4f8:c2c:123f::1
EOF
    else
        echo -e "\e[32m检测到支持 IPv4，系统为双栈 VPS。\e[0m"
    fi
}

# 执行检测函数
v4orv6
