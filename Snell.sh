#!/bin/bash

VERSION="v6.0.0rc2"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'
unset SNELL_LOCK_FD

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
    local system package repair="${1:-}" status
    local -a packages missing=()
    system=$(get_system_type)
    case "$system" in
        debian|ubuntu)
            packages=(wget unzip curl ca-certificates iproute2 coreutils util-linux)
            ;;
        alpine)
            packages=(bash wget unzip curl ca-certificates coreutils openrc gcompat libstdc++ iproute2 flock)
            ;;
        *) echo -e "${RED}仅支持 Debian、Ubuntu 和 Alpine${RESET}"; return 1 ;;
    esac
    for package in "${packages[@]}"; do
        if [ "$repair" = repair ]; then
            missing+=("$package")
        elif [ "$system" = alpine ]; then
            apk info -e "$package" >/dev/null 2>&1 || missing+=("$package")
        else
            status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null) || status=""
            [[ "$status" == *' ok installed' ]] || missing+=("$package")
        fi
    done
    if [ "${#missing[@]}" -eq 0 ]; then
        echo -e "${GREEN}必要软件包已齐全${RESET}"
        return 0
    fi
    echo -e "${GREEN}安装必要软件包${RESET}"
    if [ "$system" = alpine ]; then
        if [ "$repair" = repair ]; then
            apk fix --no-cache --reinstall --upgrade "${missing[@]}"
        else
            apk add --no-cache "${missing[@]}"
        fi
    else
        local -a options=()
        [ "$repair" != repair ] || options+=(--reinstall)
        apt-get -o DPkg::Lock::Timeout=120 update &&
            apt-get -o DPkg::Lock::Timeout=120 install -y "${options[@]}" "${missing[@]}"
    fi
}

fail() {
    echo -e "${RED}$*${RESET}" >&2
    return 1
}

# 锁由内核随进程退出释放；不删除锁文件，避免两个进程锁住不同的 inode。
with_snell_lock() (
    local previous_umask
    if [ -n "${SNELL_LOCK_FD:-}" ]; then "$@"; return $?; fi
    if ! command -v flock >/dev/null; then
        case "$(get_system_type)" in
            alpine) apk add --no-cache flock || return 1 ;;
            debian|ubuntu)
                apt-get update && apt-get -o DPkg::Lock::Timeout=120 install -y util-linux || return 1 ;;
            *) fail "无法安装操作锁依赖"; return 1 ;;
        esac
    fi
    previous_umask=$(umask)
    umask 077
    exec {SNELL_LOCK_FD}>/run/snell-manager.lock || return 1
    umask "$previous_umask"
    flock -n "$SNELL_LOCK_FD" || {
        fail "另一个 Snell 管理操作正在进行，请完成后重试"; return 1;
    }
    "$@"
)

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

secure_config_directory() {
    mkdir -p /etc/snell && chown root:snell /etc/snell && chmod 750 /etc/snell
}

secure_config_files() {
    secure_config_directory || return 1
    if [ -f /etc/snell/snell-server.conf ]; then
        chown root:snell /etc/snell/snell-server.conf &&
            chmod 640 /etc/snell/snell-server.conf || return 1
    fi
    if [ -f /etc/snell/snell-client.conf ]; then
        chown root:root /etc/snell/snell-client.conf &&
            chmod 600 /etc/snell/snell-client.conf || return 1
    fi
}

remove_snell_log_files() {
    [ "$(get_system_type)" = alpine ] || return 0
    # 只清理 Snell 专用文件；其他程序可能仍在使用 cron 和 logrotate。
    rm -f /etc/periodic/hourly/snell-logrotate /etc/snell/logrotate.conf \
        /var/lib/logrotate/snell.status /var/log/snell.log /var/log/snell.log.[0-9]*
}

write_openrc_service() {
    write_file /etc/init.d/snell 755 root:root << 'OPENRC'
#!/sbin/openrc-run
name="Snell Proxy Service"
command="/usr/local/bin/snell-server"
command_args="-l info -c /etc/snell/snell-server.conf"
command_user="snell:snell"
supervisor="supervise-daemon"
respawn_delay=3
respawn_max=5
respawn_period=60
output_log="/dev/null"
error_log="/dev/null"
rc_ulimit="-n 32768"
capabilities="^cap_net_bind_service,^cap_net_admin,^cap_net_raw"
depend() {
    after net
}
OPENRC
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

# VPS 的公网 IPv6 通常直接配置在网卡上，读取本机地址，不依赖外部查询；
# 排除 ULA（fc00::/7）以及临时、过期或未完成检测的地址。
get_public_ipv6() {
    local address
    ipv6_available || return 1
    address=$(ip -6 -o addr show scope global 2>/dev/null | awk '
        / (temporary|deprecated|tentative|dadfailed) / { next }
        { split($4, parts, "/"); address=tolower(parts[1]) }
        address ~ /^[0-9a-f:]+$/ && address ~ /:/ && address !~ /^f[cd]/ { print address; exit }
    ')
    [ -n "$address" ] && printf '%s\n' "$address"
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

# 读取和修改共用内核的 INI 规则：行内分号注释、字面量 #、冒号分隔符，
# 以及属于上一字段的缩进续行。续行的值覆盖上一值，不与上一行拼接。
parse_snell_config() {
    SNELL_CONFIG_REPLACEMENT="${5:-}" LC_ALL=C awk \
        -v operation="$1" -v key="$2" -v alias="${4:-}" '
        function append_setting() {
            if (operation == "write" && active)
                print key " = " ENVIRON["SNELL_CONFIG_REPLACEMENT"]
        }
        {
            original=$0; line=$0
            if (NR == 1) sub(/^\357\273\277/, "", line)
            sub(/[[:space:]]+$/, "", line)
            indented=(line ~ /^[[:space:]]/)
            sub(/^[[:space:]]+/, "", line)
            if (line == "" || line ~ /^[#;]/) {
                if (operation == "write") print original
                next
            }
            if (previous != "" && indented) {
                # 当前内核的续行保留行内分号，不按普通赋值行处理。
                name=previous; value=line
            } else if (substr(line, 1, 1) == "[") {
                header=line; sub(/[[:space:]];.*$/, "", header)
                if (!match(header, /\]/)) { invalid=1; next }
                append_setting()
                active=(substr(header, 2, RSTART-2) == "snell-server")
                previous=""
                if (active) sections++
                if (operation == "write") print original
                next
            } else {
                assignment=line; sub(/[[:space:]];.*$/, "", assignment)
                if (!match(assignment, /[=:]/)) { invalid=1; next }
                name=substr(assignment, 1, RSTART-1)
                sub(/[[:space:]]+$/, "", name)
                if (name == "") { invalid=1; next }
                value=substr(assignment, RSTART+1)
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
                previous=name
            }
            matched=(active && (name == key || (alias != "" && name == alias)))
            if (matched) { result=value; found=1 }
            if (operation == "write" && !matched) print original
        }
        END {
            if (invalid) exit 2
            if (operation == "write") {
                if (sections != 1) exit 2
                # 放在节末，避免改变原本首个缩进字段的归属。
                append_setting()
            } else if (found) print result
            else exit 1
        }
    ' "$3"
}

config_value() {
    parse_snell_config read "$1" "${2:-/etc/snell/snell-server.conf}" "${3:-}"
}

surge_value() {
    local value="$1"
    if [[ "$value" =~ ^[a-zA-Z0-9_+=./:@%-]+$ ]]; then
        printf '%s' "$value"
    else
        value=${value//\\/\\\\}
        value=${value//\"/\\\"}
        printf '"%s"' "$value"
    fi
}

render_client_config() {
    local LC_ALL=C listen port psk mode server_config endpoint address="" label=""
    local -a endpoints
    [ -f /etc/snell/snell-server.conf ] || { fail "服务端配置不存在"; return 1; }
    if [ "$#" -gt 0 ]; then server_config="$1"; else
        server_config=$(cat /etc/snell/snell-server.conf) || return 1
    fi
    listen=$(config_value listen /dev/stdin <<< "$server_config") &&
        psk=$(config_value psk /dev/stdin <<< "$server_config") || {
        fail "服务端配置缺少 listen 或 psk"; return 1;
    }
    (( ${#psk} >= 12 && ${#psk} <= 255 )) || { fail "服务端 PSK 长度必须为 12-255 字节"; return 1; }
    IFS=, read -r -a endpoints <<< "${listen//[[:space:]]/}"
    for endpoint in "${endpoints[@]}"; do
        valid_port "${endpoint##*:}" || { fail "服务端端口无效"; return 1; }
    done
    mode=$(config_value mode /dev/stdin <<< "$server_config") || mode=default
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
    port=$(client_ipv4_port "$listen" "$address") || return 1
    if [ -z "$label" ] || [[ "$label" == *,* || "$label" == *$'\n'* ]]; then
        label=$(get_country "$address")
    fi
    printf '%s = snell, %s, %s, psk=%s, version=6, mode=%s, reuse=true\n' \
        "$label" "$address" "$port" "$(surge_value "$psk")" "$mode"
    # 服务器有公网 IPv6 且服务监听 IPv6 时，额外导出一条 IPv6 节点。
    if address=$(get_public_ipv6) && port=$(client_ipv6_port "$listen" "$address"); then
        printf '%s-v6 = snell, %s, %s, psk=%s, version=6, mode=%s, reuse=true\n' \
            "$label" "$address" "$port" "$(surge_value "$psk")" "$mode"
    fi
}

refresh_client_config() { with_snell_lock _refresh_client_config "$@"; }

_refresh_client_config() {
    local client_config
    client_config=$(render_client_config) || return 1
    write_file /etc/snell/snell-client.conf 600 root:root <<< "$client_config" || {
        fail "写入客户端配置失败"; return 1;
    }
    printf '%s\n' "$client_config"
}

valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

client_ipv4_port() {
    local listen="${1//[[:space:]]/}" address="$2" endpoint host port fallback="" wildcard="" exact="" ambiguous=0
    local -a endpoints
    IFS=, read -r -a endpoints <<< "$listen"
    for endpoint in "${endpoints[@]}"; do
        [[ "$endpoint" == *:* ]] || { fail "监听地址格式无效"; return 1; }
        host=${endpoint%:*}; port=${endpoint##*:}
        valid_port "$port" || { fail "服务端端口无效"; return 1; }
        [[ "$host" != *:* ]] || continue
        [ "$host" != "$address" ] || exact=${exact:-$port}
        [ "$host" != 0.0.0.0 ] || wildcard=${wildcard:-$port}
        # NAT 部署允许私有绑定地址，但多个不同端口不能静默猜选。
        if valid_ipv4 "$host"; then
            if [ -z "$fallback" ]; then fallback=$port
            elif [ "$fallback" != "$port" ]; then ambiguous=1
            fi
        fi
    done
    if [ -n "$exact" ]; then printf '%s\n' "$exact"; return 0; fi
    if [ -n "$wildcard" ]; then printf '%s\n' "$wildcard"; return 0; fi
    if [ -n "$fallback" ] && (( !ambiguous )); then printf '%s\n' "$fallback"; return 0; fi
    fail "无法确定客户端 IPv4 对应的监听端口，请检查 listen 中的 IPv4 地址和端口"
}

# 只在服务监听 IPv6 时导出 IPv6 节点：优先精确地址，其次 [::]，
# 再次唯一的指定地址端口；无法确定时不导出，不影响 IPv4 节点。
client_ipv6_port() {
    local listen="${1//[[:space:]]/}" address="$2" endpoint host port exact="" wildcard="" fallback="" ambiguous=0
    local -a endpoints
    IFS=, read -r -a endpoints <<< "$listen"
    for endpoint in "${endpoints[@]}"; do
        host=${endpoint%:*}; port=${endpoint##*:}
        [[ "$host" == \[*\] ]] && valid_port "$port" || continue
        port=$((10#$port))
        host=${host#[}; host=${host%]}
        if [ "${host,,}" = "${address,,}" ]; then exact=${exact:-$port}
        elif [ "$host" = :: ]; then wildcard=${wildcard:-$port}
        elif [ -z "$fallback" ]; then fallback=$port
        elif [ "$fallback" != "$port" ]; then ambiguous=1
        fi
    done
    if [ -n "$exact" ]; then printf '%s\n' "$exact"
    elif [ -n "$wildcard" ]; then printf '%s\n' "$wildcard"
    elif [ -n "$fallback" ] && (( !ambiguous )); then printf '%s\n' "$fallback"
    else return 1
    fi
}

ipv6_available() {
    local disabled address
    [ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ] &&
        read -r disabled < /proc/sys/net/ipv6/conf/all/disable_ipv6 &&
        [ "$disabled" = 0 ] &&
        [ -r /proc/net/if_inet6 ] &&
        read -r address < /proc/net/if_inet6 && [ -n "$address" ]
}

auto_listen_address() {
    valid_port "$1" || return 1
    if ipv6_available; then
        printf '0.0.0.0:%s,[::]:%s\n' "$1" "$1"
    else
        printf '0.0.0.0:%s\n' "$1"
    fi
}

listen_with_port() {
    local listen="$1" port="$2" old_port address result=""
    local -a addresses
    valid_port "$port" || return 1
    listen=${listen//[[:space:]]/}
    old_port=${listen%%,*}; old_port=${old_port##*:}
    case "$listen" in
        "0.0.0.0:$old_port"|"[::]:$old_port"|"0.0.0.0:$old_port,[::]:$old_port"|"[::]:$old_port,0.0.0.0:$old_port")
            if [ "$port" = "$old_port" ]; then
                auto_listen_for_existing "$listen"; return $?
            fi
            auto_listen_address "$port"; return $? ;;
    esac
    # 自定义绑定地址保留，只替换每个地址的端口。
    IFS=, read -r -a addresses <<< "$listen"
    for address in "${addresses[@]}"; do
        [[ "$address" == *:* ]] && valid_port "${address##*:}" || return 1
        result+="${result:+,}${address%:*}:$port"
    done
    [ -n "$result" ] || return 1
    printf '%s\n' "$result"
}

render_server_setting() {
    local key="$1" value="$2" alias=""
    case "$key:$value" in
        mode:default|mode:unshaped|mode:unsafe-raw) ;;
        dns-ip-preference:default|dns-ip-preference:prefer-ipv4|dns-ip-preference:prefer-ipv6|dns-ip-preference:ipv4-only|dns-ip-preference:ipv6-only) ;;
        listen:*) [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1 ;;
        *) fail "Snell 配置值无效"; return 1 ;;
    esac
    # 缺失时补上，重复项及其续行一起合并，只修改唯一的 snell-server 节。
    [ "$key" != dns-ip-preference ] || alias=ipv-preference
    parse_snell_config write "$key" /etc/snell/snell-server.conf "$alias" "$value"
}

apply_snell_setting() { with_snell_lock _apply_snell_setting "$@"; }

_apply_snell_setting() (
    local key="$1" value="$2" label="$3" sync_client="${4:-1}" was_running=0
    local old_server old_client="" new_server new_client="" had_client=0
    local server_written=0 client_written=0 restart_attempted=0
    if check_snell_running; then
        was_running=1
    elif ! check_snell_stopped; then
        fail "服务正在切换状态或无法确认状态，请稍后重试"
        return 1
    fi
    secure_config_directory || { fail "设置配置目录权限失败"; return 1; }
    old_server=$(cat /etc/snell/snell-server.conf) || return 1
    new_server=$(render_server_setting "$key" "$value") || {
        fail "配置值无效或服务端缺少唯一的 [snell-server] 节"; return 1;
    }
    if (( sync_client )); then
        if [ -f /etc/snell/snell-client.conf ]; then
            old_client=$(cat /etc/snell/snell-client.conf) || return 1
            had_client=1
        fi
        new_client=$(render_client_config "$new_server") || return 1
    fi
    # 原内容仅暂存在内存中，失败时恢复；不创建备份文件。
    restore_config_on_failure() {
        local failed=0
        (( server_written || client_written )) || return 0
        trap '' HUP INT TERM
        if (( server_written )); then
            write_file /etc/snell/snell-server.conf 640 root:snell <<< "$old_server" || failed=1
        fi
        if (( client_written )); then
            if (( had_client )); then
                write_file /etc/snell/snell-client.conf 600 root:root <<< "$old_client" || failed=1
            else
                rm -f /etc/snell/snell-client.conf || failed=1
            fi
        fi
        if (( was_running && restart_attempted && !failed )); then
            restart_snell || failed=1
        fi
        if (( failed )); then
            fail "修改失败，自动恢复未完成；请检查服务端与客户端配置，并通过菜单 6、7 排查"
        else
            echo -e "${YELLOW}修改未完成，已恢复原配置${RESET}" >&2
        fi
    }
    trap restore_config_on_failure EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    # 写入可能已完成、但函数尚未返回时也会收到信号；先登记恢复责任。
    server_written=1
    write_file /etc/snell/snell-server.conf 640 root:snell <<< "$new_server" || return 1
    if (( sync_client )); then
        client_written=1
        write_file /etc/snell/snell-client.conf 600 root:root <<< "$new_client" || return 1
    fi
    if (( was_running )); then
        restart_attempted=1
        restart_snell || return 1
    fi
    trap - EXIT HUP INT TERM
    if (( was_running )); then
        echo -e "${GREEN}Snell ${label}已更改为 ${value}，服务已重启${RESET}"
    else
        echo -e "${GREEN}Snell ${label}已保存为 ${value}，服务保持停止；通过菜单 3 启动后生效${RESET}"
    fi
    if (( sync_client )); then
        echo -e "${YELLOW}请同步客户端条目：${RESET}"
        printf '%s\n' "$new_client"
    fi
)

require_snell_config() {
    check_snell_installed && [ -f /etc/snell/snell-server.conf ] || {
        fail "Snell 尚未安装或服务端配置不存在，请先安装"; return 1;
    }
}

switch_snell_mode() { with_snell_lock _switch_snell_mode "$@"; }

_switch_snell_mode() {
    local current_mode selection selected_mode
    require_snell_config || return 1
    current_mode=$(config_value mode) || current_mode=default
    echo -e "${GREEN}=== 切换 Snell 模式 ===${RESET}"
    printf '当前配置模式: %s\n' "$current_mode"
    echo "1. default（AES 加密 + 流量整形，默认）"
    echo "2. unshaped（AES 加密，无流量整形）"
    echo "3. unsafe-raw（明文传输，仅适合内网或安全隧道）"
    echo "0. 返回"
    read -r -p "请选择 Snell 模式: " selection || return 0
    case "$selection" in
        1) selected_mode=default ;;
        2) selected_mode=unshaped ;;
        3) selected_mode=unsafe-raw ;;
        0|"") return 0 ;;
        *) fail "无效的选项"; return 1 ;;
    esac
    if [ "$selected_mode" = "$current_mode" ]; then
        echo -e "${YELLOW}当前已配置此模式，无需切换${RESET}"
        refresh_client_config
        return $?
    fi
    apply_snell_setting mode "$selected_mode" "模式"
}

change_snell_port() { with_snell_lock _change_snell_port "$@"; }

# 按地址族判断监听冲突：IPv6 地址只与 IPv6 监听冲突，IPv4 同理；
# ss 显示为 *:端口 的双栈监听与两种地址族都冲突。
port_in_use() {
    local listeners="$1" endpoint="$2" family=any
    case "${endpoint%:*}" in
        \[*\]) family=6 ;;
        *.*) family=4 ;;
    esac
    awk -v port="$((10#${endpoint##*:}))" -v family="$family" '
        $4 ~ (":" port "$") {
            if (family == "any" || $4 ~ /^\*:/ || (family == 6) == ($4 ~ /^\[/)) found=1
        }
        END { exit !found }
    ' <<< "$listeners"
}

_change_snell_port() {
    local listen port listeners new_listen endpoint running=0
    local -a endpoints
    require_snell_config || return 1
    listen=$(config_value listen) || return 1
    printf '当前监听地址: %s\n' "$listen"
    read -r -p "请输入新端口（1-65535，留空返回）: " port || return 0
    [ -n "$port" ] || return 0
    valid_port "$port" || { fail "端口无效，请输入 1-65535 的整数"; return 1; }
    port=$((10#$port))
    new_listen=$(listen_with_port "$listen" "$port") || { fail "监听地址格式无效"; return 1; }
    if [ "$new_listen" = "${listen//[[:space:]]/}" ]; then
        echo -e "${YELLOW}当前监听地址无需更改，服务状态保持不变${RESET}"
        refresh_client_config
        return $?
    fi
    # 逐个检查新监听地址：只有运行中服务已占用的原地址可跳过。
    # IPv4 与 IPv6 原端口不同、改成同一端口时，新出现的地址仍须检查。
    listeners=$(ss -H -ltn) || { fail "无法检查端口占用"; return 1; }
    check_snell_running && running=1
    IFS=, read -r -a endpoints <<< "$new_listen"
    for endpoint in "${endpoints[@]}"; do
        (( running )) && [[ ",${listen//[[:space:]]/}," == *",$endpoint,"* ]] && continue
        if port_in_use "$listeners" "$endpoint"; then
            fail "TCP 端口 ${port} 已被占用，请更换端口"
            return 1
        fi
    done
    apply_snell_setting listen "$new_listen" "监听地址" || return 1
    echo "请在云安全组和系统防火墙中放行 TCP 端口 ${port}。"
}

switch_snell_dns() { with_snell_lock _switch_snell_dns "$@"; }

_switch_snell_dns() {
    local current selection preference
    require_snell_config || return 1
    # 两个名称是同一设置，内核采用文件中最后出现的值。
    if current=$(config_value dns-ip-preference /etc/snell/snell-server.conf ipv-preference); then :
    elif [ "$(config_value ipv6)" = false ]; then current=ipv4-only
    else current=default
    fi
    printf '当前 DNS 模式: %s\n' "$current"
    echo "1. default（默认）"
    echo "2. prefer-ipv4（优先 IPv4）"
    echo "3. prefer-ipv6（优先 IPv6）"
    echo "4. ipv4-only（仅 IPv4）"
    echo "5. ipv6-only（仅 IPv6）"
    echo "0. 返回"
    read -r -p "请选择 DNS 模式: " selection || return 0
    case "$selection" in
        1) preference=default ;;
        2) preference=prefer-ipv4 ;;
        3) preference=prefer-ipv6 ;;
        4) preference=ipv4-only ;;
        5) preference=ipv6-only ;;
        0|"") return 0 ;;
        *) fail "无效的选项"; return 1 ;;
    esac
    if [ "$preference" = "$current" ] && ! config_value ipv-preference >/dev/null; then
        echo "当前已配置此 DNS 模式"
        return 0
    fi
    apply_snell_setting dns-ip-preference "$preference" "DNS 模式" 0
}

change_snell_config() {
    local selection
    require_snell_config || return 1
    echo -e "${GREEN}=== 更改 Snell 配置 ===${RESET}"
    echo "1. 端口"
    echo "2. 模式"
    echo "3. DNS"
    echo "0. 返回"
    read -r -p "请选择配置项: " selection || return 0
    case "$selection" in
        1) change_snell_port ;;
        2) switch_snell_mode ;;
        3) switch_snell_dns ;;
        0|"") return 0 ;;
        *) fail "无效的选项"; return 1 ;;
    esac
}

auto_listen_for_existing() {
    local original="$1" listen port desired
    listen=${original//[[:space:]]/}
    port=${listen%%,*}; port=${port##*:}
    case "$listen" in
        "0.0.0.0:$port"|"[::]:$port"|"0.0.0.0:$port,[::]:$port"|"[::]:$port,0.0.0.0:$port") ;;
        *) printf '%s\n' "$original"; return 0 ;;
    esac
    desired=$(auto_listen_address "$port") || return 1
    # 已有双栈配置的地址顺序保留。
    if [ "$desired" = "0.0.0.0:$port,[::]:$port" ] && [ "$listen" = "[::]:$port,0.0.0.0:$port" ]; then
        printf '%s\n' "$original"
    elif [ "$desired" = "$listen" ]; then
        printf '%s\n' "$original"
    else
        printf '%s\n' "$desired"
    fi
}

choose_port() {
    local port sockets candidates low="" high=""
    # 包含 IPv4/IPv6 的所有 TCP 状态：TIME_WAIT 等非监听套接字同样会让监听绑定失败。
    sockets=$(ss -H -tan) || { fail "无法检查端口占用"; return 1; }
    # 避开内核临时端口范围，出站连接随时可能占用其中的端口；范围覆盖全部候选时不排除。
    [ -r /proc/sys/net/ipv4/ip_local_port_range ] &&
        read -r low high < /proc/sys/net/ipv4/ip_local_port_range
    [[ "$low" =~ ^[0-9]+$ && "$high" =~ ^[0-9]+$ ]] || { low=1; high=0; }
    candidates=$(seq 30000 65000 | awk -v low="$low" -v high="$high" '$1 < low || $1 > high' | shuf -n 100)
    [ -n "$candidates" ] || candidates=$(seq 30000 65000 | shuf -n 100)
    while read -r port; do
        if ! awk -v port="$port" '$4 ~ (":" port "$") {found=1} END {exit !found}' <<< "$sockets"; then
            printf '%s\n' "$port"
            return 0
        fi
    done <<< "$candidates"
    fail "未找到可用的随机 TCP 端口"
}

service_action() (
    # OpenRC 会启动后台监督进程，不让它继承管理操作的锁。
    if [ -n "${SNELL_LOCK_FD:-}" ]; then exec {SNELL_LOCK_FD}>&-; fi
    if [ "$(get_system_type)" = alpine ]; then
        rc-service snell "$1"
    else
        # 修正配置后允许立即重试，避免上一次崩溃触发的启动频率限制阻碍恢复。
        case "$1" in start|restart) systemctl reset-failed snell.service || return 1 ;; esac
        systemctl "$1" snell.service
    fi
)

show_logs() {
    if [ "$(get_system_type)" = alpine ]; then
        echo -e "${YELLOW}Alpine 已关闭 Snell 日志文件输出。${RESET}"
        echo "临时排查时，请先确认服务已停止，再前台运行："
        echo "/usr/local/bin/snell-server -l info -c /etc/snell/snell-server.conf"
        echo "排查结束按 Ctrl+C，再通过菜单 3 启动服务。"
        return 0
    fi
    if [ "$1" = follow ]; then
        # 父进程仅在查看日志期间忽略 Ctrl+C，子进程恢复默认信号处理。
        local result
        trap ':' INT
        (
            trap - INT
            exec journalctl -u snell -f -o cat
        )
        result=$?
        trap 'echo -e "${RED}已取消操作${RESET}"; exit 130' INT
        [ "$result" -eq 130 ] && return 0
        return "$result"
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
    if ! snell_binary_version "$stage/snell-server"; then
        echo -e "${YELLOW}新程序检查失败，修复依赖后重试一次${RESET}"
        install_required_packages repair && snell_binary_version "$stage/snell-server" || {
            echo -e "${RED}新程序无法运行或检查超时，请检查架构和运行依赖${RESET}"; return 1;
        }
    fi
    mv -f "$stage/snell-server" /usr/local/bin/snell-server
)

snell_binary_version() { timeout -k 2 "${2:-10}" "$1" -v; }

restart_snell() { with_snell_lock start_snell_checked restart; }

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}请以 root 权限运行此脚本.${RESET}"
        exit 1
    fi
}


check_snell_installed() {
    [ -f /usr/local/bin/snell-server ] && [ -x /usr/local/bin/snell-server ]
}

snell_service_file_exists() {
    if [ "$(get_system_type)" = alpine ]; then
        [ -f /etc/init.d/snell ]
    else
        [ -f /etc/systemd/system/snell.service ]
    fi
}

snell_service_enabled() {
    if [ "$(get_system_type)" = alpine ]; then
        [ -e /etc/runlevels/default/snell ]
    else
        systemctl is-enabled --quiet snell.service
    fi
}

register_snell_service() {
    if [ "$(get_system_type)" = alpine ]; then
        rc-update add snell default
    else
        systemctl daemon-reload && systemctl enable snell.service
    fi
}

# 服务文件缺失时，仍不能删除正在运行的内核或配置。
snell_process_exists() {
    local entry executable
    for entry in /proc/[0-9]*/exe; do
        executable=$(readlink "$entry" 2>/dev/null) || continue
        case "$executable" in
            /usr/local/bin/snell-server|'/usr/local/bin/snell-server (deleted)') return 0 ;;
            /lib/ld-musl-*.so.1)
                awk -v binary=/usr/local/bin/snell-server '
                    $2 ~ /x/ && $6 == binary { found=1 }
                    END { exit !found }
                ' "${entry%/exe}/maps" 2>/dev/null && return 0
                ;;
        esac
    done
    return 1
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

snell_service_pid() {
    local helper
    if [ "$(get_system_type)" = alpine ]; then
        for helper in /usr/libexec/rc/bin/service_get_value /lib/rc/bin/service_get_value /usr/lib/rc/bin/service_get_value; do
            if [ -x "$helper" ]; then
                RC_SVCNAME=snell "$helper" child_pid
                return $?
            fi
        done
        return 1
    fi
    systemctl show snell.service --property=MainPID --value
}

snell_listener_pid() {
    local pid executable listen endpoint host port sockets4="" sockets6="" sockets
    local -a endpoints
    pid=$(snell_service_pid) || return 1
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
    executable=$(readlink "/proc/$pid/exe") || return 1
    case "$executable" in
        /usr/local/bin/snell-server) ;;
        /lib/ld-musl-*.so.1)
            # Alpine 的 gcompat 通过 musl 加载 glibc 内核，exe 指向加载器。
            # 仍须确认该服务进程实际映射并执行了 Snell，不能只认加载器。
            [ "$(get_system_type)" = alpine ] &&
                awk -v binary=/usr/local/bin/snell-server '
                    $2 ~ /x/ && $6 == binary { found=1 }
                    END { exit !found }
                ' "/proc/$pid/maps" || return 1
            ;;
        *) return 1 ;;
    esac
    listen=$(config_value listen) || return 1
    listen=${listen//[[:space:]]/}
    [ -n "$listen" ] || return 1
    IFS=, read -r -a endpoints <<< "$listen"
    sockets4=$(ss -H -4 -ltnp) && sockets6=$(ss -H -6 -ltnp) || return 1
    for endpoint in "${endpoints[@]}"; do
        host=${endpoint%:*}; port=${endpoint##*:}
        valid_port "$port" || return 1
        case "$host" in
            \[*\]) sockets=$sockets6 ;;
            *.*) sockets=$sockets4 ;;
            *) sockets="$sockets4"$'\n'"$sockets6" ;;
        esac
        # ss 分别查询地址族；同一服务进程必须拥有每个配置端口。
        awk -v port="$((10#$port))" -v pid="$pid" '
            $4 ~ (":" port "$") && $0 ~ ("pid=" pid "[,)]") { found=1 }
            END { exit !found }
        ' <<< "$sockets" || return 1
    done
    printf '%s\n' "$pid"
}

wait_snell_state() {
    local desired="$1" attempt stable=0 pid previous_pid=""
    for ((attempt=0; attempt<8; attempt++)); do
        if [ "$desired" = stopped ]; then
            check_snell_stopped && return 0
        else
            # 同一内核进程连续三次持有监听端口；监督进程存活不算启动成功。
            sleep 1
            if check_snell_running && pid=$(snell_listener_pid); then
                if [ "$pid" = "$previous_pid" ]; then stable=$((stable+1)); else stable=1; fi
                previous_pid=$pid
            else
                stable=0; previous_pid=""
            fi
            (( stable >= 3 )) && return 0
            continue
        fi
        sleep 1
    done
    return 1
}

start_snell_checked() {
    if ! service_action "$1" || ! wait_snell_state running; then
        fail "Snell 启动或重启失败，服务未保持运行，请通过菜单 7 排查"
        show_logs recent >&2
        return 1
    fi
}

start_snell() { with_snell_lock _start_snell "$@"; }

_start_snell() {
    start_snell_checked start || return 1
    echo -e "${GREEN}Snell 启动成功${RESET}"
}

stop_snell() { with_snell_lock _stop_snell "$@"; }

_stop_snell() {
    if ! service_action stop || ! wait_snell_state stopped; then
        fail "Snell 停止失败或无法确认已经停止，保留现有文件"
        show_logs recent >&2
        return 1
    fi
    echo -e "${GREEN}Snell 停止成功${RESET}"
}

install_snell() { with_snell_lock _install_snell "$@"; }

_install_snell() {
    local has_config=0 has_binary=0 has_service=0
    [ ! -f /etc/snell/snell-server.conf ] || has_config=1
    [ ! -x /usr/local/bin/snell-server ] || has_binary=1
    snell_service_file_exists && has_service=1
    if (( has_config && has_binary && has_service )); then
        if snell_service_enabled; then
            echo -e "${YELLOW}Snell 已完整安装，已取消重复安装；现有配置保持不变。${RESET}"
            return 0
        elif check_snell_running; then
            register_snell_service || return 1
            echo "已补齐 Snell 开机启动设置，现有配置和运行状态保持不变。"
            return 0
        fi
    fi
    if (( has_service )); then
        if ! check_snell_stopped; then
            fail "安装文件不完整，且服务尚未停止或状态不明；请先停止服务再重试"
            return 1
        fi
    elif snell_process_exists; then
        fail "服务文件缺失但 Snell 进程仍在运行，请先停止该进程再重试"
        return 1
    fi
    echo -e "${GREEN}正在安装 Snell${RESET}"
    if (( has_config || has_binary || has_service )); then
        echo "检测到未完成的安装，将补齐缺失文件并保留已有配置。"
    fi

    get_architecture >/dev/null || return 1
    install_required_packages || return 1
    if (( !has_binary )); then replace_snell_binary || return 1; fi
    if (( !has_config )); then
        RANDOM_PORT=$(choose_port) || return 1
        LISTEN_ADDRESS=$(auto_listen_address "$RANDOM_PORT") || return 1
        RANDOM_PSK=$(LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 48)
        [ "${#RANDOM_PSK}" -eq 48 ] || { fail "生成 PSK 失败"; return 1; }
    fi

    if ! getent group snell >/dev/null; then
        if [ "$(get_system_type)" = alpine ]; then
            addgroup -S snell || { fail "创建 snell 用户组失败"; return 1; }
        else
            groupadd -r snell || { fail "创建 snell 用户组失败"; return 1; }
        fi
    fi
    if ! id "snell" &>/dev/null; then
        if [ "$(get_system_type)" = alpine ]; then
            adduser -S -D -H -s /sbin/nologin -G snell snell || { fail "创建 snell 用户失败"; return 1; }
        else
            useradd -r -g snell -s /usr/sbin/nologin snell || { fail "创建 snell 用户失败"; return 1; }
        fi
    fi

    secure_config_directory || { fail "创建配置目录或设置权限失败"; return 1; }
    if (( !has_config )); then
        write_file /etc/snell/snell-server.conf 640 root:snell << EOF || return 1
[snell-server]
mode = default
listen = ${LISTEN_ADDRESS}
psk = ${RANDOM_PSK}
dns-ip-preference = default
EOF
    fi
    secure_config_files || { fail "设置配置文件权限失败"; return 1; }

    if (( !has_service )); then
        if [ "$(get_system_type)" = alpine ]; then
            write_openrc_service || return 1
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
        fi
    fi
    register_snell_service || return 1
    restart_snell || { fail "Snell 安装后启动失败"; return 1; }
    remove_snell_log_files || { fail "清理 Snell 旧日志文件失败"; return 1; }
    echo -e "${GREEN}Snell 服务已启动${RESET}"
    if [ "$(get_system_type)" != alpine ]; then show_logs recent; fi
    echo -e "${GREEN}Snell 示例配置，项目地址: https://github.com/passeway/Snell${RESET}"
    refresh_client_config || return 1
    echo -e "${GREEN}🎉Snell 安装成功${RESET}"
}

update_snell() { with_snell_lock _update_snell "$@"; }

# 仅做本地预检；不依赖公网地址或客户端导出，也不启动第二个服务进程。
preflight_snell_update() {
    local LC_ALL=C original="$1" listen="$1" new_listen psk mode preference endpoint
    local -a endpoints
    psk=$(config_value psk) || {
        fail "服务端配置无效或缺少 listen、psk，已取消更新"; return 1;
    }
    (( ${#psk} >= 12 && ${#psk} <= 255 )) || { fail "服务端 PSK 长度必须为 12-255 字节"; return 1; }
    mode=$(config_value mode) || mode=default
    case "$mode" in default|unshaped|unsafe-raw) ;; *) fail "服务端 mode 无效"; return 1 ;; esac
    preference=$(config_value dns-ip-preference /etc/snell/snell-server.conf ipv-preference) || preference=default
    case "$preference" in
        default|prefer-ipv4|prefer-ipv6|ipv4-only|ipv6-only) ;;
        *) fail "服务端 DNS 模式无效"; return 1 ;;
    esac
    listen=${listen//[[:space:]]/}
    [[ -n "$listen" && "$listen" != ,* && "$listen" != *, && "$listen" != *,,* ]] || {
        fail "监听地址格式无效"; return 1;
    }
    IFS=, read -r -a endpoints <<< "$listen"
    for endpoint in "${endpoints[@]}"; do
        [[ "$endpoint" =~ ^(\[[^][,[:space:]]+\]|[^][,:[:space:]]+):([0-9]{1,5})$ ]] &&
            valid_port "${BASH_REMATCH[2]}" || { fail "监听地址或端口无效"; return 1; }
    done
    new_listen=$(auto_listen_for_existing "$original") || { fail "无法生成监听地址"; return 1; }
    if [ "$new_listen" != "$original" ]; then
        render_server_setting listen "$new_listen" >/dev/null || {
            fail "无法修改监听地址，请检查服务端配置节"; return 1;
        }
    fi
    printf '%s\n' "$new_listen"
}

_update_snell() {
    local was_running=0 listen new_listen
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
    listen=$(config_value listen) || { fail "服务端配置无效或缺少 listen，已取消更新"; return 1; }
    new_listen=$(preflight_snell_update "$listen") || return 1
    install_required_packages || return 1
    secure_config_files || { fail "设置配置文件权限失败"; return 1; }
    replace_snell_binary || return 1
    if [ "$(get_system_type)" = alpine ]; then
        write_openrc_service || return 1
    fi
    if [ "$new_listen" != "$listen" ]; then
        apply_snell_setting listen "$new_listen" "监听地址" 0 || return 1
    elif (( was_running )); then
        restart_snell || {
            echo -e "${RED}新程序已替换，但重启失败；请通过菜单 7 排查。未创建备份。${RESET}"
            return 1
        }
    else
        echo -e "${GREEN}服务保持停止状态，可通过菜单 3 启动${RESET}"
    fi
    remove_snell_log_files || { fail "清理 Snell 旧日志文件失败"; return 1; }
    if (( was_running )) && [ "$(get_system_type)" != alpine ]; then show_logs recent; fi
    echo -e "${GREEN}Snell 示例配置，项目地址: https://github.com/passeway/Snell${RESET}"
    refresh_client_config || {
        fail "内核已更新，但客户端配置生成或写入失败；请处理上述错误后通过菜单 8 重试"
        return 1
    }
    echo -e "${GREEN}🎉Snell 更新成功${RESET}"
}

uninstall_snell() { with_snell_lock _uninstall_snell "$@"; }

_uninstall_snell() {
    local has_service=0
    echo -e "${GREEN}正在卸载 Snell${RESET}"
    snell_service_file_exists && has_service=1
    if (( has_service )) || check_snell_running; then
        # 无论当前处于启动、重启还是停止状态，都先执行停止并核实结果。
        stop_snell || return 1
    fi
    # 服务已停不代表前台排错进程也已结束，删除任何文件前再次检查。
    if snell_process_exists; then
        fail "Snell 进程仍在运行，保留现有文件；请先结束前台排错或其他 Snell 进程再卸载"
        return 1
    fi
    if [ "$(get_system_type)" = alpine ]; then
        if (( has_service )); then rc-update del snell default || return 1; fi
        rm -f /etc/runlevels/default/snell || return 1
        rm -f /etc/init.d/snell || return 1
        remove_snell_log_files || return 1
    else
        if (( has_service )); then systemctl disable snell || return 1; fi
        rm -f /etc/systemd/system/multi-user.target.wants/snell.service || return 1
        rm -f /etc/systemd/system/snell.service && systemctl daemon-reload || return 1
    fi
    rm -f /usr/local/bin/snell-server && rm -rf /etc/snell || { fail "清理 Snell 文件失败"; return 1; }
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
            if snell_listener_pid >/dev/null 2>&1; then
                running_status="${GREEN}已启动${RESET}"
            else
                running_status="${RED}异常（内核进程或监听不可用）${RESET}"
            fi
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
    echo "9. 更改 Snell 配置"
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
                uninstall_snell
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
            9)
                change_snell_config
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
