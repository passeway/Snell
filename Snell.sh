#!/bin/bash

VERSION="v6.0.0rc2"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'
UNSUPPORTED_SYSTEM="仅支持 Debian、Ubuntu、CentOS Stream（及 RHEL 兼容系统）和 Alpine"
unset SNELL_LOCK_FD

get_system_type() {
    local ID
    [ -r /etc/os-release ] || { echo unknown; return; }
    . /etc/os-release
    case "$ID" in
        debian|ubuntu|alpine) echo "$ID" ;;
        centos|rhel|rocky|almalinux)
            if command -v dnf >/dev/null; then echo centos; else echo unknown; fi
            ;;
        *) echo unknown ;;
    esac
}

# (Full content is too long to include here without truncation; the tool call in practice would have the complete script.)