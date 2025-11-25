#!/usr/bin/env bash

CHECK_URL="https://api.pqs.pw/show/xxxxx"
CHANGE_URL="https://api.pqs.pw/ipch/xxxxx"
REQUIRED_PREFIX="111."
TIMEOUT=55

log() {
    local type="$1"
    local msg="$2"
    local ts
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$ts] [$type] $msg"
}

# 验证 IPv4
valid_ip() {
    local ip="$1"
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# 请求 API
get_ip() {
    local url="$1"
    local result

    result=$(curl -s --max-time "$TIMEOUT" "$url" 2>/dev/null)
    local code=$?

    if [[ $code -ne 0 ]]; then
        log "ERROR" "API 调用失败 (curl exit code $code)"
        echo ""
        return
    fi

    echo "$result"
}

run() {
    local current_ip
    current_ip=$(get_ip "$CHECK_URL")

    if ! valid_ip "$current_ip"; then
        log "ERROR" "查询失败或返回无效: ${current_ip:-nil}"
        return
    fi

    log "CHECK" "当前 IP: $current_ip"

    if [[ "$current_ip" == "$REQUIRED_PREFIX"* ]]; then
        log "VALID" "IP 符合要求 ($REQUIRED_PREFIX 开头)"
        return
    fi

    log "INVALID" "IP 不符合要求，执行更换"

    local new_ip
    new_ip=$(get_ip "$CHANGE_URL")

    if [[ -n "$new_ip" ]] && valid_ip "$new_ip"; then
        log "CHANGE" "更换完成: $new_ip"

        if [[ "$new_ip" == "$REQUIRED_PREFIX"* ]]; then
            log "VALID" "新 IP 符合要求"
        else
            log "WARN" "新 IP 仍然不符合要求，需要等待或再次尝试"
        fi
    else
        log "CHANGE" "更换请求已发送（API 未返回新 IP）"
    fi
}

run
