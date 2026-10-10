#!/bin/bash
# 使用 Docker Compose 部署 Snell v6。镜像在本地由官方内核构建，不依赖第三方镜像。

VERSION="v6.0.0rc2"
BASE_DIR="/root/snell-docker"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

CONFIG_FILE="$BASE_DIR/snell-conf/snell.conf"
CLIENT_FILE="$BASE_DIR/snell-conf/snell.txt"

fail() {
    echo -e "${RED}$*${RESET}" >&2
    return 1
}

check_root() {
    [ "$(id -u)" = 0 ] || fail "请以 root 权限运行此脚本"
}

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
        *) fail "不支持的架构: $(uname -m)" ;;
    esac
}

# 只补装缺失的 Docker 组件，不升级系统，也不删除已有的 Compose 插件。
install_docker() {
    local system
    system=$(get_system_type)
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${GREEN}正在安装 Docker${RESET}"
        case "$system" in
            alpine)
                apk add --no-cache docker docker-cli-compose || return 1
                rc-update add docker default || return 1
                ;;
            debian|ubuntu)
                curl -fsSL https://get.docker.com | sh || { fail "Docker 安装失败，请检查网络连接"; return 1; }
                ;;
            *) fail "仅支持 Debian、Ubuntu 和 Alpine"; return 1 ;;
        esac
    fi
    if ! docker compose version >/dev/null 2>&1; then
        echo -e "${GREEN}正在安装 Docker Compose 插件${RESET}"
        case "$system" in
            alpine) apk add --no-cache docker-cli-compose ;;
            debian|ubuntu)
                apt-get update && { apt-get install -y docker-compose-plugin ||
                    apt-get install -y docker-compose-v2; }
                ;;
            *) false ;;
        esac || { fail "无法安装 Docker Compose 插件"; return 1; }
    fi
    if ! docker info >/dev/null 2>&1; then
        if [ "$system" = alpine ]; then rc-service docker start; else systemctl enable --now docker; fi
        local attempt
        for ((attempt=0; attempt<15; attempt++)); do
            docker info >/dev/null 2>&1 && return 0
            sleep 1
        done
        fail "Docker 服务未能启动"
        return 1
    fi
}

valid_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}

valid_ipv4() {
    local octet
    local -a octets
    [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r -a octets <<< "$1"
    for octet in "${octets[@]}"; do
        (( 10#$octet <= 255 )) || return 1
    done
    (( 10#${octets[0]} > 0 && 10#${octets[0]} != 127 && 10#${octets[0]} < 224 )) || return 1
    ! (( 10#${octets[0]} == 169 && 10#${octets[1]} == 254 ))
}

ipv6_available() {
    local disabled address
    [ -r /proc/sys/net/ipv6/conf/all/disable_ipv6 ] &&
        read -r disabled < /proc/sys/net/ipv6/conf/all/disable_ipv6 &&
        [ "$disabled" = 0 ] &&
        [ -r /proc/net/if_inet6 ] &&
        read -r address < /proc/net/if_inet6 && [ -n "$address" ]
}

listen_address() {
    if ipv6_available; then
        printf '0.0.0.0:%s,[::]:%s\n' "$1" "$1"
    else
        printf '0.0.0.0:%s\n' "$1"
    fi
}

choose_port() {
    local port listeners="" attempt
    if command -v ss >/dev/null 2>&1; then listeners=$(ss -H -ltn 2>/dev/null); fi
    for ((attempt=0; attempt<100; attempt++)); do
        port=$(shuf -i 30000-65000 -n 1) || return 1
        if ! awk -v port="$port" '$4 ~ (":" port "$") {found=1} END {exit !found}' <<< "$listeners"; then
            printf '%s\n' "$port"
            return 0
        fi
    done
    fail "未找到可用的随机 TCP 端口"
}

# 读取 [snell-server] 节中的单个字段，忽略注释，后出现的值覆盖前值。
config_value() {
    awk -v key="$1" '
        { line=$0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line) }
        line == "" || line ~ /^[#;]/ { next }
        substr(line, 1, 1) == "[" { active=(line ~ /^\[snell-server\]/); next }
        active && match(line, /[=:]/) {
            name=substr(line, 1, RSTART-1); sub(/[[:space:]]+$/, "", name)
            if (name != key) next
            value=substr(line, RSTART+1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            result=value; found=1
        }
        END { if (found) print result; else exit 1 }
    ' "${2:-$CONFIG_FILE}"
}

write_server_config() {
    local listen="$1" psk="$2"
    (umask 077 && cat > "$CONFIG_FILE.tmp" << EOF && mv -f "$CONFIG_FILE.tmp" "$CONFIG_FILE")
[snell-server]
mode = default
listen = ${listen}
psk = ${psk}
dns-ip-preference = default
EOF
}

# v6 配置原样保留；v5 旧配置（无 mode 字段）迁移为 v6，并保留端口和 PSK。
prepare_server_config() {
    local listen port psk
    mkdir -p "$BASE_DIR/snell-conf" && chmod 700 "$BASE_DIR" "$BASE_DIR/snell-conf" || return 1
    if [ -f "$CONFIG_FILE" ]; then
        if config_value mode >/dev/null; then
            echo "检测到已有 Snell v6 配置，保持不变。"
            chmod 600 "$CONFIG_FILE"
            return
        fi
        listen=$(config_value listen) || listen=""
        port=${listen%%,*}; port=${port##*:}
        psk=$(config_value psk) || psk=""
        if valid_port "$port" && (( ${#psk} >= 12 && ${#psk} <= 255 )); then
            echo "检测到旧版 Snell 配置，已迁移为 v6，保留原端口和 PSK。"
            write_server_config "$(listen_address "$((10#$port))")" "$psk"
            return
        fi
        echo -e "${YELLOW}旧配置缺少有效的端口或 PSK，将重新生成。${RESET}"
    fi
    port=$(choose_port) || return 1
    psk=$(LC_ALL=C tr -dc A-Za-z0-9 < /dev/urandom | head -c 48)
    [ "${#psk}" -eq 48 ] || { fail "生成 PSK 失败"; return 1; }
    write_server_config "$(listen_address "$port")" "$psk"
}

write_compose_files() {
    local architecture
    architecture=$(get_architecture) || return 1
    cat > "$BASE_DIR/Dockerfile" << 'EOF' || return 1
FROM debian:bookworm-slim
ARG SNELL_VERSION
ARG SNELL_ARCH
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates wget unzip \
 && wget --timeout=15 --tries=3 -O /tmp/snell.zip \
      "https://dl.nssurge.com/snell/snell-server-${SNELL_VERSION}-linux-${SNELL_ARCH}.zip" \
 && unzip -o /tmp/snell.zip snell-server -d /usr/local/bin \
 && chmod 755 /usr/local/bin/snell-server \
 && /usr/local/bin/snell-server -v \
 && apt-get purge -y wget unzip && apt-get autoremove -y \
 && rm -rf /var/lib/apt/lists/* /tmp/snell.zip
ENTRYPOINT ["/usr/local/bin/snell-server"]
CMD ["-l", "info", "-c", "/etc/snell/snell.conf"]
EOF
    cat > "$BASE_DIR/docker-compose.yml" << EOF
services:
  snell:
    build:
      context: .
      args:
        SNELL_VERSION: ${VERSION}
        SNELL_ARCH: ${architecture}
    image: snell-server:${VERSION}
    container_name: snell
    restart: unless-stopped
    network_mode: host
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE, NET_ADMIN, NET_RAW]
    security_opt: [no-new-privileges:true]
    ulimits:
      nofile: 32768
    volumes:
      # 挂载目录而非单个文件，配置以新文件替换后容器也能读到。
      - ./snell-conf:/etc/snell:ro
    logging:
      driver: json-file
      options:
        max-size: 1m
        max-file: "3"
EOF
}

# 容器连续保持运行且未重启，才算启动成功。
wait_container() {
    local attempt stable=0 state
    for ((attempt=0; attempt<10; attempt++)); do
        sleep 1
        state=$(docker inspect -f '{{.State.Running}} {{.RestartCount}}' snell 2>/dev/null)
        if [ "$state" = "true 0" ]; then stable=$((stable+1)); else stable=0; fi
        (( stable >= 3 )) && return 0
    done
    return 1
}

get_public_ip() {
    local endpoint address
    for endpoint in https://checkip.amazonaws.com https://api.ipify.org https://ipv4.icanhazip.com; do
        address=$(curl -4fsS --connect-timeout 3 --max-time 8 "$endpoint" 2>/dev/null) || continue
        address=${address//[$'\r\n']/}
        if valid_ipv4 "$address"; then printf '%s\n' "$address"; return 0; fi
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

get_country() {
    local country
    country=$(curl -4fsS --connect-timeout 3 --max-time 8 "https://ipinfo.io/$1/country" 2>/dev/null) || country=""
    country=${country//[$'\r\n']/}
    if [[ "$country" =~ ^[A-Z]{2}$ ]]; then printf '%s\n' "$country"; else echo Snell; fi
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
    local address="$1" label="$2" listen port psk mode
    listen=$(config_value listen) && psk=$(config_value psk) || { fail "服务端配置缺少 listen 或 psk"; return 1; }
    listen=${listen//[[:space:]]/}
    port=${listen%%,*}; port=${port##*:}
    valid_port "$port" || { fail "服务端端口无效"; return 1; }
    mode=$(config_value mode) || mode=default
    printf '%s = snell, %s, %s, psk=%s, version=6, mode=%s, reuse=true\n' \
        "$label" "$address" "$((10#$port))" "$(surge_value "$psk")" "$mode"
    # 服务器有公网 IPv6 且服务监听 IPv6 时，额外导出一条 IPv6 节点。
    if address=$(get_public_ipv6) && port=$(client_ipv6_port "$listen" "$address"); then
        printf '%s-v6 = snell, %s, %s, psk=%s, version=6, mode=%s, reuse=true\n' \
            "$label" "$address" "$port" "$(surge_value "$psk")" "$mode"
    fi
}

main() {
    local address label port
    check_root || return 1
    [ "$(get_system_type)" != unknown ] || { fail "仅支持 Debian、Ubuntu 和 Alpine"; return 1; }
    get_architecture >/dev/null || return 1
    install_docker || return 1
    prepare_server_config || return 1
    write_compose_files || return 1

    echo -e "${GREEN}正在构建并启动 Snell ${VERSION} 容器${RESET}"
    (cd "$BASE_DIR" && docker compose up -d --build --force-recreate --remove-orphans) || { fail "容器构建或启动失败"; return 1; }
    if ! wait_container; then
        docker logs --tail 20 snell >&2
        fail "Snell 容器未保持运行，请检查上方日志和 $CONFIG_FILE"
        return 1
    fi
    docker logs --tail 8 snell

    if address=$(get_public_ip); then
        label=$(get_country "$address")
    else
        echo -e "${YELLOW}自动获取公网 IPv4 失败，请将条目中的 YOUR_SERVER_IP 替换为服务器地址。${RESET}"
        address=YOUR_SERVER_IP
        label=Snell
    fi
    render_client_config "$address" "$label" > "$CLIENT_FILE" && chmod 600 "$CLIENT_FILE" || return 1
    port=$(awk -F', *' 'NR == 1 {print $3}' "$CLIENT_FILE")
    echo -e "${GREEN}Snell 容器已启动，Surge 代理条目：${RESET}"
    cat "$CLIENT_FILE"
    echo "请在云安全组和系统防火墙中放行 TCP 端口 ${port}。"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
