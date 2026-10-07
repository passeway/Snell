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
            apt-get update && apt-get -o DPkg::Lock::Timeout=120 install -y wget unzip curl ca-certificates iproute2 coreutils
            ;;
        alpine)
            apk add --no-cache bash wget unzip curl ca-certificates coreutils openrc gcompat libstdc++ iproute2 logrotate busybox-initscripts
            ;;
        *) echo -e "${RED}仅支持 Debian、Ubuntu 和 Alpine${RESET}"; return 1 ;;
    esac
}

fail() {
    echo -e "${RED}$*${RESET}" >&2
    return 1
}

# 同目录暂存后替换，避免磁盘满时留下被截断的配置；不保留备份。
write_file() (
    local destination="$1" permissions="$2" owner="$3" temporary
    temporary=$(mktemp "${destination}.tmp.XXXXXX") || return 1
    trap 'rm -f "$temporary"' EXIT
    trap 'exit 1' INT TERM
    if ! { cat > "$temporary" &&
        chown "$owner" "$temporary" &&
        chmod "$permissions" "$temporary" &&
        mv -f "$temporary" "$destination"; }; then
        fail "写入文件或设置权限失败: $destination"
        return 1
    fi
)

secure_config_files() {
    if [ -f /etc/snell/snell-server.conf ]; then
        chown root:snell /etc/snell/snell-server.conf &&
            chmod 640 /etc/snell/snell-server.conf || return 1
    fi
    if [ -f /etc/snell/snell-client.conf ]; then
        chown root:root /etc/snell/snell-client.conf &&
            chmod 600 /etc/snell/snell-client.conf || return 1
    fi
}

configure_log_rotation() {
    [ "$(get_system_type)" = alpine ] || return 0
    mkdir -p /etc/snell /etc/periodic/hourly /var/lib/logrotate || return 1
    # 私有配置和状态文件，避免与发行版每天轮转全部日志的任务重复处理。
    write_file /etc/snell/logrotate.conf 644 root:root <<'ROTATE' || return 1
/var/log/snell.log {
    size 1M
    rotate 3
    compress
    missingok
    notifempty
    copytruncate
    su root snell
}
ROTATE
    write_file /etc/periodic/hourly/snell-logrotate 755 root:root <<'CRON' || return 1
#!/bin/sh
exec /usr/sbin/logrotate -s /var/lib/logrotate/snell.status /etc/snell/logrotate.conf
CRON
    rc-update add crond default || return 1
    if ! rc-service crond status >/dev/null 2>&1; then
        rc-service crond start || return 1
    fi
}

valid_ipv4() {
    local octet
    local -a octets
    [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r -a octets <<< "$1"
    for octet in "${octets[@]}"; do
        (( 10#$octet <= 255 )) || return 1
    done
    # 保留可手动使用的内网地址，排除未指定、回环、链路本地、组播及保留地址。
    (( 10#${octets[0]} > 0 && 10#${octets[0]} != 127 && 10#${octets[0]} < 224 )) || return 1
    ! (( 10#${octets[0]} == 169 && 10#${octets[1]} == 254 ))
}

fetch_text() {
    curl -4fsS --connect-timeout 3 --max-time 8 "$1"
}

get_public_ip() {
    local endpoint address
    for endpoint in https://checkip.amazonaws.com https://api.ipify.org https://ipv4.icanhazip.com; do
        address=$(fetch_text "$endpoint" 2>/dev/null) || continue
        address=${address//$'\r'/}
        address=${address//$'\n'/}
        if valid_ipv4 "$address"; then
            printf '%s\n' "$address"
            return 0
        fi
    done
    echo "自动获取公网 IPv4 失败，请填写客户端连接地址。" >&2
    while read -r -p "公网 IPv4（留空取消）: " address; do
        [ -n "$address" ] || return 1
        if valid_ipv4 "$address"; then
            printf '%s\n' "$address"
            return 0
        fi
        echo "IPv4 地址无效，请重新输入。" >&2
    done
    return 1
}

get_country() {
    local country
    country=$(fetch_text "https://ipinfo.io/$1/country" 2>/dev/null) || country=""
    country=${country//$'\r'/}
    country=${country//$'\n'/}
    if [[ "$country" =~ ^[A-Z]{2}$ ]]; then
        printf '%s\n' "$country"
    else
        echo Snell
    fi
}

config_value() {
    awk -v key="$1" '
        /^[[:space:]]*\[/ {
            section=$0
            sub(/[[:space:]]*[#;].*$/, "", section)
            gsub(/[[:space:]]/, "", section)
            active=(section == "[snell-server]")
            next
        }
        active && /^[[:space:]]*[^#;][^=]*=/ {
            name=$0; sub(/=.*/, "", name)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
            if (name == key) {
                value=$0; sub(/^[^=]*=/, "", value)
                sub(/[[:space:]]+[#;].*$/, "", value)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                found=1
            }
        }
        END { if (found) print value; else exit 1 }
    ' /etc/snell/snell-server.conf
}

refresh_client_config() {
    local listen port psk mode address="" label=""
    [ -f /etc/snell/snell-server.conf ] || { fail "服务端配置不存在"; return 1; }
    listen=$(config_value listen) && psk=$(config_value psk) || {
        fail "服务端配置缺少 listen 或 psk"; return 1;
    }
    listen=${listen%%,*}
    listen=${listen//[[:space:]]/}
    port=${listen##*:}
    [[ "$port" =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 )) &&
        [ -n "$psk" ] || { fail "服务端端口或 PSK 无效"; return 1; }
    mode=$(config_value mode) || mode=default
    case "$mode" in
        default|unshaped|unsafe-raw) ;;
        *) fail "服务端 mode 无效"; return 1 ;;
    esac
    # 已有公网地址和节点名保留；端口、PSK、mode 始终从当前服务端配置读取。
    if [ -f /etc/snell/snell-client.conf ]; then
        address=$(awk -F, 'NR==1 { gsub(/[[:space:]]/, "", $2); print $2 }' /etc/snell/snell-client.conf)
        label=$(awk -F= 'NR==1 { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1 }' /etc/snell/snell-client.conf)
    fi
    if ! valid_ipv4 "$address"; then
        address=$(get_public_ip) || { fail "服务已安装，但客户端地址未填写；可通过菜单 8 重试"; return 1; }
    fi
    if [ -z "$label" ] || [[ "$label" == *,* || "$label" == *$'\n'* ]]; then
        label=$(get_country "$address")
    fi
    write_file /etc/snell/snell-client.conf 600 root:root <<EOF || {
${label} = snell, ${address}, ${port}, psk=${psk}, version=6, mode=${mode}, reuse=true
EOF
        fail "写入客户端配置失败"; return 1;
    }
    cat /etc/snell/snell-client.conf
}

choose_port() {
    local port listeners attempt
    # 包含 IPv4/IPv6 的 TCP 监听端口；监听失败仍由后续服务启动检查处理。
    listeners=$(ss -H -ltn) || { fail "无法检查端口占用"; return 1; }
    for ((attempt=0; attempt<100; attempt++)); do
        port=$(shuf -i 30000-65000 -n 1) || return 1
        if ! awk -v port="$port" '$4 ~ (":" port "$") {found=1} END {exit !found}' <<< "$listeners"; then
            printf '%s\n' "$port"
            return 0
        fi
    done
    fail "未找到可用的随机 TCP 端口"
}

service_action() {
    if [ "$(get_system_type)" = alpine ]; then
        rc-service snell "$1"
    else
        systemctl "$1" snell.service
    fi
}

show_logs() {
    if [ "$1" = follow ]; then
        # 父进程仅在查看日志期间忽略 Ctrl+C，子进程恢复默认信号处理。
        local result
        trap ':' INT
        (
            trap - INT
            if [ "$(get_system_type)" = alpine ]; then
                exec tail -n 50 -F /var/log/snell.log
            else
                exec journalctl -u snell -f -o cat
            fi
        )
        result=$?
        trap 'echo -e "${RED}已取消操作${RESET}"; exit 130' INT
        [ "$result" -eq 130 ] && return 0
        return "$result"
    elif [ "$(get_system_type)" = alpine ]; then
        tail -n 8 /var/log/snell.log
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
    timeout -k 5 180 wget --timeout=15 --tries=3 --waitretry=2 \
        "https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-${architecture}.zip" -O "$stage/snell.zip" || {
        echo -e "${RED}下载 Snell 失败或超时${RESET}"; return 1;
    }
    unzip -o "$stage/snell.zip" snell-server -d "$stage" || {
        echo -e "${RED}解压 Snell 失败${RESET}"; return 1;
    }
    chmod 755 "$stage/snell-server" || return 1
    snell_binary_version "$stage/snell-server" || {
        echo -e "${RED}新程序无法运行或检查超时，请检查架构和运行依赖${RESET}"; return 1;
    }
    mv -f "$stage/snell-server" /usr/local/bin/snell-server
)

snell_binary_version() { timeout -k 2 "${2:-10}" "$1" -v; }

restart_snell() { start_snell_checked restart; }

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

# 与“不是 active”区分：正在启停和查询失败都不算已经停止。
check_snell_stopped() {
    local state result
    if [ "$(get_system_type)" = alpine ]; then
        if rc-service snell status >/dev/null 2>&1; then result=0; else result=$?; fi
        # OpenRC 的 3 表示 stopped；4/8/16/32 等状态不能据此确认停机。
        [ "$result" -eq 3 ]
    else
        state=$(systemctl show snell.service --property=ActiveState --value) || return 1
        case "$state" in inactive|failed) return 0 ;; *) return 1 ;; esac
    fi
}

wait_snell_state() {
    local desired="$1" attempt stable=0
    for ((attempt=0; attempt<8; attempt++)); do
        if [ "$desired" = stopped ]; then
            check_snell_stopped && return 0
        else
            # 连续三次检查，避免把命令成功或短暂启动当成持续运行。
            sleep 1
            if check_snell_running; then stable=$((stable+1)); else stable=0; fi
            (( stable >= 3 )) && return 0
            continue
        fi
        sleep 1
    done
    return 1
}

start_snell_checked() {
    if ! service_action "$1" || ! wait_snell_state running; then
        fail "Snell 启动或重启失败，服务未保持运行，请查看日志"
        show_logs recent >&2
        return 1
    fi
}

start_snell() {
    start_snell_checked start || return 1
    echo -e "${GREEN}Snell 启动成功${RESET}"
}

stop_snell() {
    if ! service_action stop || ! wait_snell_state stopped; then
        fail "Snell 停止失败或无法确认已经停止，保留现有文件"
        show_logs recent >&2
        return 1
    fi
    echo -e "${GREEN}Snell 停止成功${RESET}"
}

install_snell() {
    echo -e "${GREEN}正在安装 Snell${RESET}"

    get_architecture >/dev/null || return 1
    install_required_packages || return 1
    replace_snell_binary || return 1
    RANDOM_PORT=$(choose_port) || return 1
    RANDOM_PSK=$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 48)
    [ "${#RANDOM_PSK}" -eq 48 ] || { fail "生成 PSK 失败"; return 1; }

    if ! id "snell" &>/dev/null; then
        if [ "$(get_system_type)" = alpine ]; then
            if ! getent group snell >/dev/null; then
                addgroup -S snell || { fail "创建 snell 用户组失败"; return 1; }
            fi
            adduser -S -D -H -s /sbin/nologin -G snell snell || { fail "创建 snell 用户失败"; return 1; }
        else
            useradd -r -s /usr/sbin/nologin snell || { fail "创建 snell 用户失败"; return 1; }
        fi
    fi

    mkdir -p /etc/snell || { fail "创建配置目录失败"; return 1; }
    write_file /etc/snell/snell-server.conf 640 root:snell << EOF || return 1
[snell-server]
mode = default
listen = 0.0.0.0:${RANDOM_PORT}
psk = ${RANDOM_PSK}
dns-ip-preference = default
EOF

    if [ "$(get_system_type)" = alpine ]; then
        write_file /etc/init.d/snell 755 root:root << 'OPENRC' || return 1
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
        rc-update add snell default || return 1
    else
    write_file /etc/systemd/system/snell.service 644 root:root << EOF || return 1
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
    configure_log_rotation || { fail "配置日志轮转失败"; return 1; }
    restart_snell || { fail "Snell 安装后启动失败"; return 1; }
    echo -e "${GREEN}Snell 服务已启动${RESET}"
    show_logs recent
    echo -e "${GREEN}Snell 示例配置，项目地址: https://github.com/passeway/Snell${RESET}"
    refresh_client_config || return 1
    echo -e "${GREEN}🎉Snell 安装成功${RESET}"
}

update_snell() {
    local was_running=0
    if [ ! -f "/usr/local/bin/snell-server" ]; then
        echo -e "${YELLOW}Snell 未安装，跳过更新${RESET}"
        return
    fi

    echo -e "${GREEN}Snell 正在更新${RESET}"
    get_architecture >/dev/null || return 1
    if check_snell_running; then
        was_running=1
    elif ! check_snell_stopped; then
        fail "服务正在切换状态或无法确认状态，请稍后重试更新"
        return 1
    fi
    install_required_packages || return 1
    secure_config_files || { fail "设置配置文件权限失败"; return 1; }
    configure_log_rotation || { fail "配置日志轮转失败"; return 1; }
    replace_snell_binary || return 1
    if (( was_running )); then
        restart_snell || {
            echo -e "${RED}新程序已替换，但重启失败；请查看日志。未创建备份。${RESET}"
            return 1
        }
    else
        echo -e "${GREEN}服务保持停止状态，可通过菜单 3 启动${RESET}"
    fi
    echo -e "${GREEN}🎉Snell 更新成功${RESET}"
    if (( was_running )); then show_logs recent; fi
    echo -e "${GREEN}Snell 示例配置，项目地址: https://github.com/passeway/Snell${RESET}"
    refresh_client_config
}

uninstall_snell() {
    echo -e "${GREEN}正在卸载 Snell${RESET}"
    # 无论当前处于启动、重启还是停止状态，都先执行停止并核实结果。
    stop_snell || return 1
    if [ "$(get_system_type)" = alpine ]; then
        rc-update del snell default || return 1
        rm -f /etc/init.d/snell /etc/periodic/hourly/snell-logrotate || return 1
        rm -f /var/lib/logrotate/snell.status || return 1
    else
        systemctl disable snell || return 1
        rm -f /etc/systemd/system/snell.service && systemctl daemon-reload || return 1
    fi
    rm /usr/local/bin/snell-server && rm -rf /etc/snell || { fail "清理 Snell 文件失败"; return 1; }
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
        if version_output=$(snell_binary_version /usr/local/bin/snell-server 3 2>&1); then
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
    read -r -p "请输入选项编号: " choice || return 1
    export choice
    echo ""
}

trap 'echo -e "${RED}已取消操作${RESET}"; exit 130' INT

main() {
    check_root
    if [ "$(get_system_type)" = unknown ]; then
        echo -e "${RED}仅支持 Debian、Ubuntu 和 Alpine${RESET}"
        return 1
    fi

    while true; do
        show_menu || return 0
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
                refresh_client_config
                ;;
            0)
                echo -e "${GREEN}已退出 Snell 管理工具${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效的选项${RESET}"
                ;;
        esac
        read -r -p "按 enter 键继续..." || return 0
    done
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main
fi
