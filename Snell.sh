#!/bin/bash

# Snell Server 管理脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 函数定义
install_dependencies() {
    PKGMGR=""
    if [ -x "$(command -v apt-get)" ]; then
        PKGMGR="apt-get"
    elif [ -x "$(command -v yum)" ]; then
        PKGMGR="yum"
    elif [ -x "$(command -v dnf)" ]; then
        PKGMGR="dnf"
    else
        echo -e "${RED}未知的 Linux 发行版，无法安装依赖。${NC}"
        exit 1
    fi

    sudo "$PKGMGR" update -y
    sudo "$PKGMGR" install -y unzip wget curl
}

install_snell() {
    # 安装依赖
    install_dependencies

    # 更新系统包和升级
    apt-get update && apt-get -y upgrade

    # 下载 Snell 服务器文件
    SNELL_VERSION="v4.0.1"
    ARCH=$(uname -m)
    SNELL_URL=""
    INSTALL_DIR="/usr/local/bin"
    SYSTEMD_SERVICE_FILE="/lib/systemd/system/snell.service"
    CONF_DIR="/etc/snell"
    CONF_FILE="$CONF_DIR/snell-server.conf"

    case "$ARCH" in
        aarch64) SNELL_URL="https://dl.nssurge.com/snell/snell-server-$SNELL_VERSION-linux-aarch64.zip" ;;
        x86_64) SNELL_URL="https://dl.nssurge.com/snell/snell-server-$SNELL_VERSION-linux-amd64.zip" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${NC}"; exit 1 ;;
    esac

    # 下载 Snell 服务器文件
    if ! wget "$SNELL_URL" -O snell-server.zip; then
        echo -e "${RED}下载 Snell 失败.${NC}"
        exit 1
    fi

    # 解压缩文件到指定目录
    if ! sudo unzip -o snell-server.zip -d "$INSTALL_DIR"; then
        echo -e "${RED}解压缩 Snell 失败.${NC}"
        exit 1
    fi

    # 删除下载的 zip 文件
    rm snell-server.zip

    # 赋予执行权限
    sudo chmod +x "$INSTALL_DIR/snell-server"

    # 生成随机端口和密码
    RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
    RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

    # 创建配置文件目录
    sudo mkdir -p "$CONF_DIR"

    # 创建配置文件
    sudo tee "$CONF_FILE" > /dev/null << EOF
[snell-server]
listen = ::0:$RANDOM_PORT
psk = $RANDOM_PSK
ipv6 = false
EOF

    # 创建 Systemd 服务文件
    sudo tee "$SYSTEMD_SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=$INSTALL_DIR/snell-server -c $CONF_FILE
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF

    # 重载 Systemd 配置
    if ! sudo systemctl daemon-reload; then
        echo -e "${RED}重载 Systemd 配置失败.${NC}"
        exit 1
    fi

    # 开机自启动 Snell
    if ! sudo systemctl enable snell; then
        echo -e "${RED}开机自启动 Snell 失败.${NC}"
        exit 1
    fi

    # 启动 Snell 服务
    if ! sudo systemctl start snell; then
        echo -e "${RED}启动 Snell 服务失败.${NC}"
        exit 1
    fi

    # 获取本机IP地址
    HOST_IP=$(curl -s http://checkip.amazonaws.com)

    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/"$HOST_IP"/country)

    # 输出所需信息，包含IP所在国家
    echo -e "${GREEN}Snell 安装成功.${NC}"
    echo "服务配置信息:"
    echo "$IP_COUNTRY = snell, $HOST_IP, $RANDOM_PORT, psk = $RANDOM_PSK, version = 4, reuse = true, tfo = true" | sudo tee /etc/snell_output.txt
}

check_install_status() {
    if [ -f "/usr/local/bin/snell-server" ]; then
        echo -e "${GREEN}Snell 已安装.${NC}"
    else
        echo -e "${YELLOW}Snell 未安装.${NC}"
    fi
}

check_running_status() {
    if sudo systemctl is-active --quiet snell; then
        echo -e "${GREEN}Snell 服务正在运行.${NC}"
    else
        echo -e "${YELLOW}Snell 服务未在运行.${NC}"
    fi
}

uninstall_snell() {
    sudo systemctl stop snell || true
    sudo systemctl disable snell || true
    sudo rm -f /usr/local/bin/snell-server
    sudo rm -f /lib/systemd/system/snell.service
    sudo systemctl daemon-reload
    sudo systemctl reset-failed
    sudo rm -rf /etc/snell
    sudo rm -f /etc/snell_output.txt
    echo -e "${GREEN}Snell 已卸载.${NC}"
    rm -- "$0" # 删除脚本文件
}

restart_snell() {
    sudo systemctl restart snell
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 服务已重启.${NC}"
    else
        echo -e "${RED}重启 Snell 服务失败.${NC}"
    fi
}

# 显示标题
echo -e "${YELLOW}=============================="
echo "Snell Server 管理脚本"
echo "=============================${NC}"

# 显示菜单选项
echo "选择操作:"
echo "1. 安装 Snell"
echo "2. 卸载 Snell"
echo "3. 重启 Snell"
echo "4. 查看 Snell 服务状态"
echo "5. 查看 Snell 输出信息"
echo "输入 0 退出脚本"
echo ""

# 读取用户输入
read -p "输入选项: " choice

case $choice in
    1) install_snell ;;
    2) uninstall_snell ;;
    3) restart_snell ;;
    4) check_install_status && check_running_status ;;
    5) cat /etc/snell_output.txt ;;
    0) exit ;;
