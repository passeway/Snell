#!/bin/bash
# pqs-test.sh
# 用法: bash pqs-test.sh <目标IP>
# 先在要测试内网的VDS上面开启iperf3

TARGET=$1

if [ -z "$TARGET" ]; then
    echo "用法: $0 <目标IP>"
    exit 1
fi

echo "========================================"
echo " 🚀 PQS 内网链路测试 "
echo " 目标: $TARGET"
echo "========================================"

# --------- 安装依赖 ---------
install_iperf() {
    if ! command -v iperf3 &>/dev/null; then
        echo "[INFO] 未检测到 iperf3，正在安装..."
        if [ -f /etc/debian_version ]; then
            apt update -y && apt install -y iperf3 mtr-traceroute
        elif [ -f /etc/redhat-release ]; then
            yum install -y epel-release && yum install -y iperf3 mtr
        else
            echo "[ERROR] 无法识别系统，请手动安装 iperf3 和 mtr"
            exit 1
        fi
    fi
}

install_iperf

# --------- Ping 测试 ---------
echo -e "\n>>> [1] Ping 延迟测试 (10次)"
ping -c 10 $TARGET

# --------- iPerf3 上下行测试 ---------
echo -e "\n>>> [2] iPerf3 上行带宽测试"
iperf3 -c $TARGET -t 10

echo -e "\n>>> [3] iPerf3 下行带宽测试"
iperf3 -c $TARGET -R -t 10

echo -e "\n>>> [4] iPerf3 并发4线程测试"
iperf3 -c $TARGET -P 4 -t 10

# --------- UDP 带宽测试 ---------
echo -e "\n>>> [5] iPerf3 UDP 测试 (100M)"
iperf3 -c $TARGET -u -b 100M -t 10 --get-server-output

# --------- MTR 测试 ---------
echo -e "\n>>> [6] MTR 链路质量测试 (10次)"
mtr -r -c 10 $TARGET

# --------- Traceroute ---------
echo -e "\n>>> [7] Traceroute 路由路径"
traceroute $TARGET

echo -e "\n✅ 测试完成！"
echo "========================================"
