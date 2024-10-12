#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 日志文件路径
LOG_FILE="/var/log/snell_manager.log"

# 服务名称
SERVICE_NAME="snell.service"

# 配置信息变量
IP_COUNTRY=""
HOST_IP=""
RANDOM_PORT=""
RANDOM_PSK=""

# 等待其他 apt 进程完成
wait_for_apt() {
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        echo -e "${YELLOW}等待其他 apt 进程完成${RESET}"
        sleep 1
    done
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请以 root 权限运行此脚本.${RESET}"
        exit 1
    fi
}

# 检查 Snell 是否已安装
check_snell_installed() {
    if command -v snell-server &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 检查 Snell 是否正在运行
check_snell_running() {
    systemctl is-active --quiet "$SERVICE_NAME"
    return $?
}

# 启动 Snell 服务
start_snell() {
    echo -e "${CYAN}正在启动 Snell${RESET}"
    systemctl start "$SERVICE_NAME"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 启动成功${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Snell 启动成功" >> "$LOG_FILE"
    else
        echo -e "${RED}Snell 启动失败${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Snell 启动失败" >> "$LOG_FILE"
    fi
}

# 停止 Snell 服务
stop_snell() {
    echo -e "${CYAN}正在停止 Snell${RESET}"
    systemctl stop "$SERVICE_NAME"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 停止成功${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Snell 停止成功" >> "$LOG_FILE"
    else
        echo -e "${RED}Snell 停止失败${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Snell 停止失败" >> "$LOG_FILE"
    fi
}

# 安装 Snell
install_snell() {
    echo -e "${CYAN}正在安装 Snell${RESET}"

    # 等待其他 apt 进程完成
    wait_for_apt

    # 更新软件包列表
    if ! apt update; then
        echo -e "${RED}更新软件包列表失败，请检查您的网络连接或软件源配置。${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 更新软件包列表失败" >> "$LOG_FILE"
        exit 1
    fi

    # 安装必要的软件包
    if ! apt install -y wget unzip curl; then
        echo -e "${RED}安装必要软件包失败，请检查您的网络连接。${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 安装必要软件包失败" >> "$LOG_FILE"
        exit 1
    fi

    # 下载 Snell 服务器文件
    ARCH=$(arch)
    SNELL_URL=""
    INSTALL_DIR="/usr/local/bin"
    SYSTEMD_SERVICE_FILE="/lib/systemd/system/snell.service"
    CONF_DIR="/etc/snell"
    CONF_FILE="${CONF_DIR}/snell-server.conf"

    if [[ ${ARCH} == "aarch64" ]]; then
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-aarch64.zip"
    else
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip"
    fi

    # 下载 Snell 服务器文件
    if ! wget ${SNELL_URL} -O snell-server.zip; then
        echo -e "${RED}下载 Snell 失败，请检查下载链接或网络连接。${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 下载 Snell 失败" >> "$LOG_FILE"
        exit 1
    fi

    # 解压缩文件到指定目录
    if ! unzip -o snell-server.zip -d ${INSTALL_DIR}; then
        echo -e "${RED}解压缩 Snell 失败。${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 解压缩 Snell 失败" >> "$LOG_FILE"
        exit 1
    fi

    # 删除下载的 zip 文件
    rm snell-server.zip

    # 赋予执行权限
    chmod +x ${INSTALL_DIR}/snell-server

    # 生成随机端口和密码
    RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
    RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

    # 检查 snell 用户是否已存在
    if ! id "snell" &>/dev/null; then
        # 创建 Snell 用户
        sudo useradd -r -s /usr/sbin/nologin snell
    fi

    # 创建配置文件目录
    mkdir -p ${CONF_DIR}

    # 创建配置文件
    cat > ${CONF_FILE} << EOF
[snell-server]
dns = 1.1.1.1, 8.8.8.8, 2001:4860:4860::8888
listen = ::0:${RANDOM_PORT}
psk = ${RANDOM_PSK}
ipv6 = true
EOF

    # 创建 Systemd 服务文件
    cat > ${SYSTEMD_SERVICE_FILE} << EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=snell
Group=snell
LimitNOFILE=32768
ExecStart=${INSTALL_DIR}/snell-server -c ${CONF_FILE}
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF

    # 重载 Systemd 配置
    systemctl daemon-reload
    if [ $? -ne 0 ]; then
        echo -e "${RED}重载 Systemd 配置失败。${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 重载 Systemd 配置失败" >> "$LOG_FILE"
        exit 1
    fi

    # 开机自启动 Snell
    systemctl enable snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}开机自启动 Snell 失败。${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 开机自启动 Snell 失败" >> "$LOG_FILE"
        exit 1
    fi

    # 启动 Snell 服务
    systemctl start snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}启动 Snell 服务失败。${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - 启动 Snell 服务失败" >> "$LOG_FILE"
        exit 1
    fi

    # 获取本机IP地址
    HOST_IP=$(curl -s http://checkip.amazonaws.com)

    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)

    echo -e "${GREEN}Snell 安装成功${RESET}"
    echo "${IP_COUNTRY} = snell, ${HOST_IP}, ${RANDOM_PORT}, psk = ${RANDOM_PSK}, version = 4, reuse = true, tfo = true"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Snell 安装成功: ${IP_COUNTRY}, ${HOST_IP}, ${RANDOM_PORT}, psk=${RANDOM_PSK}" >> "$LOG_FILE"
}

# 主程序
check_root
if ! check_snell_installed; then
    install_snell
else
    echo -e "${YELLOW}Snell 已安装，您可以使用其他功能${RESET}"
fi
