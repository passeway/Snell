#!/bin/bash

VERSION="v6.0.0rc2"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

get_system_type() {
    local ID
    [ -r /etc/os-release ] || { echo unknown; return; }
    . /etc/os-release
    case "$ID" in
        debian|ubuntu|alpine) echo "$ID" ;;
        *) echo unknown ;;
    esac
}

get_architecture() {
    case "$(uname -m)" in
        x86_64|amd64) echo amd64 ;;
        aarch64|arm64) echo aarch64 ;;
        *) echo "不支持的架构: $(uname -m)" >&2; return 1 ;;
    esac
}

install_required_packages() {
    echo -e "${GREEN}安装必要软件包${RESET}"
    case "$(get_system_type)" in
        debian|ubuntu)
            apt-get update && apt-get -o DPkg::Lock::Timeout=120 install -y wget unzip curl ca-certificates
            ;;
        alpine)
            apk add --no-cache bash wget unzip curl ca-certificates coreutils openrc gcompat libstdc++
            ;;
        *) echo -e "${RED}仅支持 Debian、Ubuntu 和 Alpine${RESET}"; return 1 ;;
    esac
}

service_action() {
    if [ "$(get_system_type)" = alpine ]; then
        rc-service snell "$1"
    else
        systemctl "$1" snell.service
    fi
}

show_logs() {
    if [ "$(get_system_type)" = alpine ]; then
        if [ "$1" = follow ]; then
            tail -n 50 -f /var/log/snell.log
        else
            tail -n 8 /var/log/snell.log
        fi
    elif [ "$1" = follow ]; then
        journalctl -u snell -f -o cat
    else
        journalctl -u snell -n 8 --no-pager
    fi
}

# 在目标文件所在文件系统暂存，验证成功后原子替换；不创建备份。
replace_snell_binary() (
    local architecture stage
    architecture=$(get_architecture) || return 1
    mkdir -p /usr/local/bin || return 1
    stage=$(mktemp -d /usr/local/bin/.snell-install.XXXXXX) || return 1
    trap 'rm -rf "$stage"' EXIT
    trap 'exit 1' INT TERM
    wget "https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-${architecture}.zip" -O "$stage/snell.zip" || {
        echo -e "${RED}下载 Snell 失败${RESET}"; return 1;
    }
    unzip -o "$stage/snell.zip" snell-server -d "$stage" || {
        echo -e "${RED}解压 Snell 失败${RESET}"; return 1;
    }
    chmod 755 "$stage/snell-server" || return 1
    "$stage/snell-server" -v || {
        echo -e "${RED}新程序无法运行，请检查架构和运行依赖${RESET}"; return 1;
    }
    mv -f "$stage/snell-server" /usr/local/bin/snell-server
)

restart_snell() {
    service_action restart || return 1
    sleep 3
    check_snell_running || {
        echo -e "${RED}Snell 启动后未保持运行，请查看日志${RESET}"
        show_logs recent
        return 1
    }
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
    if [ "$(get_system_type)" = alpine ]; then
        rc-service snell status >/dev/null 2>&1
    else
        systemctl is-active --quiet snell.service
    fi
}

start_snell() {
    service_action start
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 启动成功${RESET}"
    else
        echo -e "${RED}Snell 启动失败${RESET}"
    fi
}

stop_snell() {
    service_action stop
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Snell 停止成功${RESET}"
    else
        echo -e "${RED}Snell 停止失败${RESET}"
    fi
}

install_snell() {
    echo -e "${GREEN}正在安装 Snell${RESET}"

    get_architecture >/dev/null || return 1
    install_required_packages || return 1
    replace_snell_binary || return 1
    RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
    RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 48)

    if ! id "snell" &>/dev/null; then
        if [ "$(get_system_type)" = alpine ]; then
            addgroup -S snell && adduser -S -D -H -s /sbin/nologin -G snell snell || return 1
        else
            useradd -r -s /usr/sbin/nologin snell || return 1
        fi
    fi

    mkdir -p /etc/snell
    cat > /etc/snell/snell-server.conf << EOF
[snell-server]
mode = default
listen = 0.0.0.0:${RANDOM_PORT}
psk = ${RANDOM_PSK}
dns-ip-preference = default
EOF

    if [ "$(get_system_type)" = alpine ]; then
        cat > /etc/init.d/snell << 'OPENRC'
#!/sbin/openrc-run
name="Snell Proxy Service"
command="/usr/local/bin/snell-server"
command_args="-l info -c /etc/snell/snell-server.conf"
command_user="snell:snell"
supervisor="supervise-daemon"
respawn_delay=3
respawn_max=5
respawn_period=60
output_log="/var/log/snell.log"
error_log="/var/log/snell.log"
rc_ulimit="-n 32768"
capabilities="^cap_net_bind_service,^cap_net_admin,^cap_net_raw"
depend() {
    after net
}
start_pre() {
    checkpath --file --mode 0640 --owner snell:snell /var/log/snell.log
}
OPENRC
        chmod 755 /etc/init.d/snell || return 1
        rc-update add snell default || return 1
    else
    cat > /etc/systemd/system/snell.service << EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=snell
Group=snell
ExecStart=/usr/local/bin/snell-server -l info -c /etc/snell/snell-server.conf
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


        systemctl daemon-reload && systemctl enable snell || return 1
    fi
    restart_snell || { echo -e "${RED}Snell 安装后启动失败${RESET}"; return 1; }
    echo -e "${GREEN}🎉Snell 安装成功${RESET}"
    show_logs recent
    HOST_IP=$(curl -s http://checkip.amazonaws.com)
    IP_COUNTRY=$(curl -s http://ipinfo.io/${HOST_IP}/country)
    echo -e "${GREEN}Snell 示例配置，项目地址: https://github.com/passeway/Snell${RESET}"
    cat << EOF > /etc/snell/snell-client.conf
${IP_COUNTRY} = snell, ${HOST_IP}, ${RANDOM_PORT}, psk=${RANDOM_PSK}, version=6, mode=default, reuse=true
EOF

    cat /etc/snell/snell-client.conf
}

update_snell() {
    if [ ! -f "/usr/local/bin/snell-server" ]; then
        echo -e "${YELLOW}Snell 未安装，跳过更新${RESET}"
        return
    fi

    echo -e "${GREEN}Snell 正在更新${RESET}"
    get_architecture >/dev/null || return 1
    install_required_packages || return 1
    replace_snell_binary || return 1
    restart_snell || {
        echo -e "${RED}新程序已替换，但重启失败；请查看日志。未创建备份。${RESET}"
        return 1
    }
    echo -e "${GREEN}🎉Snell 更新成功${RESET}"
    show_logs recent
    echo -e "${GREEN}Snell 示例配置，项目地址: https://github.com/passeway/Snell${RESET}"
    cat /etc/snell/snell-client.conf
}

uninstall_snell() {
    echo -e "${GREEN}正在卸载 Snell${RESET}"
    if check_snell_running; then
        service_action stop || return 1
    fi
    if [ "$(get_system_type)" = alpine ]; then
        rc-update del snell default || return 1
        rm -f /etc/init.d/snell
    else
        systemctl disable snell || return 1
        rm -f /etc/systemd/system/snell.service
        systemctl daemon-reload
    fi
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
        if version_output=$(/usr/local/bin/snell-server -v 2>&1); then
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
    echo "4. 更新 Snell 内核"
    echo "5. 重启 Snell 服务"
    echo "6. 查看 Snell 状态"
    echo "7. 查看 Snell 日志"
    echo "8. 查看 Snell 配置"
    echo "0. 退出"
    echo -e "${GREEN}======================${RESET}"
    read -p "请输入选项编号: " choice
    export choice
    echo ""
}

trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

main() {
    check_root
    if [ "$(get_system_type)" = unknown ]; then
        echo -e "${RED}仅支持 Debian、Ubuntu 和 Alpine${RESET}"
        return 1
    fi

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
                restart_snell
                ;;
            6)
                if [ "$(get_system_type)" = alpine ]; then
                    service_action status
                else
                    systemctl status snell --no-pager -l
                fi
                ;;
            7)
                show_logs follow
                ;;
            8)
                if [ -f /etc/snell/snell-client.conf ]; then
                    cat /etc/snell/snell-client.conf
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
