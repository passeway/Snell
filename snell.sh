#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 日志文件路径和服务名称
LOG_FILE="/var/log/snell_manager.log"
SERVICE_NAME="snell.service"

# 检测系统类型
get_system_type() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    else
        echo "unknown"
    fi
}

# 等待包管理器锁
wait_for_package_manager() {
    local SYSTEM_TYPE=$(get_system_type)
    if [ "$SYSTEM_TYPE" = "debian" ]; then
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
            echo -e "${YELLOW}等待其它 apt 进程完成...${RESET}"
            sleep 1
        done
    fi
}

# 安装必要的软件包
install_required_packages() {
    local SYSTEM_TYPE=$(get_system_type)
    echo -e "${GREEN}安装必要的软件包${RESET}"
    
    if [ "$SYSTEM_TYPE" = "debian" ]; then
        apt update && apt install -y wget unzip curl || return 1
    elif [ "$SYSTEM_TYPE" = "centos" ]; then
        yum -y update && yum -y install wget unzip curl || return 1
    else
        echo -e "${RED}不支持的系统类型${RESET}"
        return 1
    fi
    return 0
}

# 检查是否以 root 权限运行
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请以 root 权限运行此脚本.${RESET}"
        exit 1
    fi
}

# 检查 Snell 的安装和运行状态
check_snell_status() {
    if command -v snell-server &>/dev/null; then
        if systemctl is-active --quiet "$SERVICE_NAME"; then
            echo "installed_and_running"
        else
            echo "installed_but_not_running"
        fi
    else
        echo "not_installed"
    fi
}

# 统一的下载和安装 Snell
download_and_install_snell() {
    local SNELL_URL=$1
    local ARCH=$(arch)
    local VERSION="v4.1.1"
    local INSTALL_DIR="/usr/local/bin"
    
    # 下载
    wget "$SNELL_URL" -O snell-server.zip || return 1
    
    # 解压
    unzip -o snell-server.zip -d "$INSTALL_DIR" || return 1
    
    # 清理
    rm snell-server.zip
    chmod +x "$INSTALL_DIR/snell-server"
    return 0
}

# 启动 Snell 服务
start_snell() {
    systemctl start "$SERVICE_NAME" && {
        echo -e "${GREEN}Snell 启动成功${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] Snell 启动成功" >> "$LOG_FILE"
    } || {
        echo -e "${RED}Snell 启动失败${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [ERROR] Snell 启动失败" >> "$LOG_FILE"
    }
}

# 停止 Snell 服务
stop_snell() {
    systemctl stop "$SERVICE_NAME" && {
        echo -e "${GREEN}Snell 停止成功${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] Snell 停止成功" >> "$LOG_FILE"
    } || {
        echo -e "${RED}Snell 停止失败${RESET}"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - [ERROR] Snell 停止失败" >> "$LOG_FILE"
    }
}

# 安装 Snell
install_snell() {
    echo -e "${GREEN}正在安装 Snell${RESET}"

    # 等待包管理器
    wait_for_package_manager

    # 安装必要的软件包
    install_required_packages || return 1

    local ARCH=$(arch)
    local VERSION="v4.1.1"
    local SNELL_URL=""
    local INSTALL_DIR="/usr/local/bin"
    local SYSTEMD_SERVICE_FILE="/lib/systemd/system/snell.service"
    local CONF_DIR="/etc/snell"
    local CONF_FILE="${CONF_DIR}/snell-server.conf"

    if [[ ${ARCH} == "aarch64" ]]; then
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip"
    else
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"
    fi

    # 下载并安装 Snell
    download_and_install_snell "$SNELL_URL" || return 1

    # 确保 snell 用户存在
    if ! id "snell" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin snell
    fi

    # 创建配置文件目录
    mkdir -p ${CONF_DIR}

    # 生成随机端口和密码
    RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
    RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

    # 创建配置文件
    cat << EOF > ${CONF_FILE}
[snell-server]
listen = ::0:${RANDOM_PORT}
psk = ${RANDOM_PSK}
ipv6 = true
EOF

    # 创建 Systemd 服务文件
    cat << EOF > ${SYSTEMD_SERVICE_FILE}
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
    systemctl daemon-reload || return 1

    # 开机自启动 Snell
    systemctl enable snell || return 1

    # 启动 Snell 服务
    start_snell || return 1

    # 查看 Snell 日志
    echo -e "${GREEN}Snell 安装成功${RESET}"
    sleep 3 && journalctl -u snell.service -n 5 --no-pager

    # 获取本机IP地址和国家
    HOST_IP=$(curl -s http://checkip.amazonaws.com)
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)

    # 写入配置文件
    echo "${IP_COUNTRY} = snell, ${HOST_IP}, ${RANDOM_PORT}, psk = ${RANDOM_PSK}, version = 4, reuse = true" > /etc/snell/config.txt
    cat /etc/snell/config.txt
}

# 更新 Snell
update_snell() {
    local INSTALL_DIR="/usr/local/bin"
    local SNELL_BIN="${INSTALL_DIR}/snell-server"
    
    if [ ! -f "${SNELL_BIN}" ]; then
        echo -e "${YELLOW}Snell 未安装，跳过更新${RESET}"
        return
    fi

    echo -e "${GREEN}Snell 正在更新${RESET}"

    # 停止 Snell
    stop_snell || return 1

    # 等待包管理器
    wait_for_package_manager

    # 安装必要的软件包
    install_required_packages || return 1

    local ARCH=$(arch)
    local VERSION="v4.1.1"
    local SNELL_URL=""

    if [[ ${ARCH} == "aarch64" ]]; then
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip"
    else
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"
    fi

    # 下载并安装 Snell
    download_and_install_snell "$SNELL_URL" || return 1

    # 重启 Snell
    start_snell || return 1

    echo -e "${GREEN}Snell 更新成功${RESET}"
    cat /etc/snell/config.txt
}

# 卸载 Snell
uninstall_snell() {
    echo -e "${GREEN}正在卸载 Snell${RESET}"

    # 停止 Snell 服务
    stop_snell || return 1

    # 禁用开机自启动
    systemctl disable snell || return 1

    # 删除 Systemd 服务文件
    rm "$SYSTEMD_SERVICE_FILE" || return 1

    # 重载 Systemd 配置
    systemctl daemon-reload

    # 删除安装的文件和目录
    rm "$INSTALL_DIR/snell-server"
    rm -rf "$CONF_DIR"

    echo -e "${GREEN}Snell 卸载成功${RESET}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] Snell 卸载成功" >> "$LOG_FILE"
}

# 显示菜单
show_menu() {
    clear
    local STATUS=$(check_snell_status)

    if [ "$STATUS" = "installed_and_running" ]; then
        installation_status="${GREEN}已安装${RESET}"
        running_status="${GREEN}已启动${RESET}"
    elif [ "$STATUS" = "installed_but_not_running" ]; then
        installation_status="${GREEN}已安装${RESET}"
        running_status="${RED}未启动${RESET}"
    else
        installation_status="${RED}未安装${RESET}"
        running_status="${RED}未启动${RESET}"
    fi

    echo -e "${GREEN}=== Snell 管理工具 ===${RESET}"
    echo -e "安装状态: ${installation_status}"
    echo -e "运行状态: ${running_status}"
    echo ""
    echo "1. 安装 Snell 服务"
    echo "2. 卸载 Snell 服务"
    if [ "$STATUS" != "not_installed" ]; then
        if [ "$STATUS" = "installed_and_running" ]; then
            echo "3. 停止 Snell 服务"
        else
            echo "3. 启动 Snell 服务"
        fi
    fi
    echo "4. 更新 Snell 服务"
    echo "5. 查看 Snell 配置"
    echo "0. 退出"
    echo -e "${GREEN}======================${RESET}"
    read -p "请输入选项编号: " choice
    echo ""
}

# 捕获 Ctrl+C 信号
trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

# 主循环
main() {
    check_root

    while true; do
        show_menu
        case "${choice}" in
            1)
                install_snell
                ;;
            2)
                if [ "$(check_snell_status)" != "not_installed" ]; then
                    uninstall_snell
                else
                    echo -e "${RED}Snell 尚未安装${RESET}"
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARN] 尝试卸载但 Snell 尚未安装" >> "$LOG_FILE"
                fi
                ;;
            3)
                if [ "$(check_snell_status)" != "not_installed" ]; then
                    if [ "$(check_snell_status)" = "installed_and_running" ]; then
                        stop_snell
                    else
                        start_snell
                    fi
                else
                    echo -e "${RED}Snell 尚未安装${RESET}"
                    echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARN] 尝试管理服务但 Snell 尚未安装" >> "$LOG_FILE"
                fi
                ;;
            4)
                update_snell
                ;;
            5)
                if [ -f /etc/snell/config.txt ]; then
                    cat /etc/snell/config.txt
                else
                    echo -e "${RED}配置文件不存在${RESET}"
                fi
                ;;
            0)
                echo -e "${GREEN}已退出 Snell 管理工具${RESET}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] 用户退出管理工具" >> "$LOG_FILE"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选项${RESET}"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARN] 用户输入无效选项: $choice" >> "$LOG_FILE"
                ;;
        esac
        read -p "按 enter 键继续..."
    done
}

# 执行主函数
main