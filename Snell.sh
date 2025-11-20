#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'


ARCH=$(arch)
SNELL_URL=""
VERSION="v5.0.1"
CONF_DIR="/etc/snell"
SERVICE_NAME="snell.service"
INSTALL_DIR="/usr/local/bin"

get_system_type() {
    if [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    else
        echo "unknown"
    fi
}

wait_for_package_manager() {
    local system_type=$(get_system_type)
    if [ "$system_type" = "debian" ]; then
        while fuser /var/lib/dpkg/lock >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
            echo -e "${YELLOW}等待其他 apt 进程完成${RESET}"
            sleep 1
        done
    fi
}

install_required_packages() {
    local system_type=$(get_system_type)
    echo -e "${GREEN}安装必要软件包${RESET}"
    
    if [ "$system_type" = "debian" ]; then
        apt update
        apt install -y wget unzip curl
    elif [ "$system_type" = "centos" ]; then
        yum -y update
        yum -y install wget unzip curl
    else
        echo -e "${RED}不支持的系统类型${RESET}"
        exit 1
    fi
}

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请以 root 权限运行此脚本.${RESET}"
        exit 1
    fi
}

check_snell_installed() {
    if command -v snell-server &> /dev/null; then
        return 0
    else
        return 1
    fi
}

check_snell_running() {
    systemctl is-active --quiet "$SERVICE_NAME"
    return $?
}

start_snell() {
    systemctl start "$SERVICE_NAME"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 启动成功${RESET}"
    else
        echo -e "${RED}Snell 启动失败${RESET}"
    fi
}

stop_snell() {
    systemctl stop "$SERVICE_NAME"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 停止成功${RESET}"
    else
        echo -e "${RED}Snell 停止失败${RESET}"
    fi
}

install_snell() {
    echo -e "${GREEN}正在安装 Snell${RESET}"

    wait_for_package_manager
    if ! install_required_packages; then
        echo -e "${RED}安装必要软件包失败，请检查您的网络连接。${RESET}"
        exit 1
    fi

    if [[ ${ARCH} == "aarch64" ]]; then
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip"
    else
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"
    fi
    wget ${SNELL_URL} -O snell-server.zip
    if [ $? -ne 0 ]; then
        echo -e "${RED}下载 Snell 失败。${RESET}"
        exit 1
    fi
    unzip -o snell-server.zip -d ${INSTALL_DIR}
    if [ $? -ne 0 ]; then
        echo -e "${RED}解压缩 Snell 失败。${RESET}"
        exit 1
    fi
    rm snell-server.zip
    chmod +x ${INSTALL_DIR}/snell-server
    RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
    RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

    if ! id "snell" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin snell
    fi

    mkdir -p ${CONF_DIR}
    cat > /etc/snell/snell-server.conf << EOF
[snell-server]
listen = ::0:${RANDOM_PORT}
psk = ${RANDOM_PSK}
ipv6 = true
EOF

    cat > /lib/systemd/system/snell.service << EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=snell
Group=snell
ExecStart=${INSTALL_DIR}/snell-server -c /etc/snell/snell-server.conf
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_ADMIN CAP_NET_RAW
LimitNOFILE=32768
Restart=on-failure
StandardOutput=journal
StandardError=journal
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    if [ $? -ne 0 ]; then
        echo -e "${RED}重载 Systemd 配置失败。${RESET}"
        exit 1
    fi
    systemctl enable snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}开机自启动 Snell 失败。${RESET}"
        exit 1
    fi
    systemctl start snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}启动 Snell 服务失败。${RESET}"
        exit 1
    fi
    echo -e "${GREEN}Snell 安装成功${RESET}"
    sleep 3 && journalctl -u snell.service -n 8 --no-pager
    HOST_IP=$(curl -s http://checkip.amazonaws.com)
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)
    echo -e "${GREEN}Snell 示例配置，项目地址: https://github.com/passeway/Snell${RESET}"
    cat << EOF > /etc/snell/config.txt
${IP_COUNTRY} = snell, ${HOST_IP}, ${RANDOM_PORT}, psk = ${RANDOM_PSK}, version = 5, reuse = true
EOF
    cat /etc/snell/config.txt
}

update_snell() {
    INSTALL_DIR="/usr/local/bin"
    SNELL_BIN="${INSTALL_DIR}/snell-server"
    if [ ! -f "${SNELL_BIN}" ]; then
        echo -e "${YELLOW}Snell 未安装，跳过更新${RESET}"
        return
    fi

    echo -e "${GREEN}Snell 正在更新${RESET}"
    if ! systemctl stop snell; then
        echo -e "${RED}停止 Snell 失败。${RESET}"
        exit 1
    fi
    wait_for_package_manager
    if ! install_required_packages; then
        echo -e "${RED}安装必要软件包失败，请检查您的网络连接。${RESET}"
        exit 1
    fi

    if [[ ${ARCH} == "aarch64" ]]; then
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip"
    else
        SNELL_URL="https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"
    fi
    if ! wget ${SNELL_URL} -O snell-server.zip; then
        echo -e "${RED}下载 Snell 失败。${RESET}"
        exit 1
    fi
    if ! unzip -o snell-server.zip -d ${INSTALL_DIR}; then
        echo -e "${RED}解压缩 Snell 失败。${RESET}"
        exit 1
    fi
    rm snell-server.zip
    chmod +x ${SNELL_BIN}
    if ! systemctl restart snell; then
        echo -e "${RED}重启 Snell 失败。${RESET}"
        exit 1
    fi

    echo -e "${GREEN}Snell 更新成功${RESET}"
	sleep 3 && journalctl -u snell.service -n 8 --no-pager
	echo -e "${GREEN}Snell 示例配置，项目地址: https://github.com/passeway/Snell${RESET}"
    cat /etc/snell/config.txt
}

uninstall_snell() {
    echo -e "${GREEN}正在卸载 Snell${RESET}"
    systemctl stop snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}停止 Snell 服务失败。${RESET}"
        exit 1
    fi
    systemctl disable snell
    if [ $? -ne 0 ]; then
        echo -e "${RED}禁用开机自启动失败。${RESET}"
        exit 1
    fi
    rm /lib/systemd/system/snell.service
    if [ $? -ne 0 ]; then
        echo -e "${RED}删除 Systemd 服务文件失败。${RESET}"
        exit 1
    fi
    systemctl daemon-reload
    rm /usr/local/bin/snell-server
    rm -rf /etc/snell
    echo -e "${GREEN}Snell 卸载成功${RESET}"
}
show_menu() {
    clear
    check_snell_installed
    snell_installed=$?
    check_snell_running
    snell_running=$?

    if [ $snell_installed -eq 0 ]; then
        installation_status="${GREEN}已安装${RESET}"
        if version_output=$(/usr/local/bin/snell-server -version 2>&1); then
            snell_version=$(echo "$version_output" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
            if [ -n "$snell_version" ]; then
                version_status="${GREEN}${snell_version}${RESET}"
            else
                version_status="${RED}未知版本${RESET}"
            fi
        else
            version_status="${RED}未知版本${RESET}"
        fi

        if [ $snell_running -eq 0 ]; then
            running_status="${GREEN}已启动${RESET}"
        else
            running_status="${RED}未启动${RESET}"
        fi
    else
        installation_status="${RED}未安装${RESET}"
        running_status="${RED}未启动${RESET}"
        version_status="—"
    fi

    echo -e "${GREEN}=== Snell 管理工具 ===${RESET}"
    echo -e "安装状态: ${installation_status}"
    echo -e "运行状态: ${running_status}"
    echo -e "运行版本: ${version_status}"
    echo ""
    echo "1. 安装 Snell 服务"
    echo "2. 卸载 Snell 服务"
    if [ $snell_installed -eq 0 ]; then
        if [ $snell_running -eq 0 ]; then
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

trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

main() {
    check_root

    while true; do
        show_menu
        case "${choice}" in
            1)
                install_snell
                ;;
            2)
                if [ $snell_installed -eq 0 ]; then
                    uninstall_snell
                else
                    echo -e "${RED}Snell 尚未安装${RESET}"
                fi
                ;;
            3)
                if [ $snell_installed -eq 0 ]; then
                    if [ $snell_running -eq 0 ]; then
                        stop_snell
                    else
                        start_snell
                    fi
                else
                    echo -e "${RED}Snell 尚未安装${RESET}"
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
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选项${RESET}"
                ;;
        esac
        read -p "按 enter 键继续..."
    done
}

main
