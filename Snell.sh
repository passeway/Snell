#!/bin/bash

# 函数：安装 Snell
install_snell() {
    # 更新系统包和升级
    echo "正在更新系统包..."
    apt-get update && apt-get -y upgrade || { echo "更新失败。退出..." ; exit 1; }
    echo "系统包更新完成。"

    # 安装 Docker
    echo "正在安装 Docker..."
    apt-get install -y docker.io || { echo "安装 Docker 失败。退出..." ; exit 1; }
    echo "Docker 安装完成。"

    # 安装 Docker Compose
    echo "正在安装 Docker Compose..."
    curl -fsSL https://get.docker.com -o /usr/local/bin/docker-compose || { echo "下载 Docker Compose 失败。退出..." ; exit 1; }
    chmod +x /usr/local/bin/docker-compose || { echo "设置 Docker Compose 可执行权限失败。退出..." ; exit 1; }
    echo "Docker Compose 安装完成。"

    # 创建所需目录
    echo "正在创建目录..."
    mkdir -p /root/snelldocker/snell-conf || { echo "创建目录失败。退出..." ; exit 1; }
    echo "目录创建完成。"

    # 生成随机端口和密码
    RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
    RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

    # 获取机器架构信息
    MACHINE_ARCH=$(uname -m)

    # 根据机器架构选择 Docker 映像和 Snell 二进制文件
    case $MACHINE_ARCH in
        x86_64)
            DOCKER_IMAGE="accors/snell:latest"
            SNELL_BINARY_URL="https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-amd64.zip"
            ;;
        aarch64)
            DOCKER_IMAGE="accors/snell-arm:latest"
            SNELL_BINARY_URL="https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-arm.zip"
            ;;
        *)
            echo "不支持的架构类型: $MACHINE_ARCH。退出..."
            exit 1
            ;;
    esac

    # 创建 docker-compose.yml
    echo "正在创建 docker-compose.yml 文件..."
    cat > /root/snelldocker/docker-compose.yml << EOF || { echo "创建 docker-compose.yml 文件失败。退出..." ; exit 1; }
    version: "3.8"
    services:
      snell:
        image: $DOCKER_IMAGE
        container_name: snell
        restart: always
        network_mode: host
        volumes:
          - ./snell-conf/snell.conf:/etc/snell-server.conf
        environment:
          - SNELL_URL=$SNELL_BINARY_URL
EOF
    echo "docker-compose.yml 文件创建完成。"

    # 创建 snell.conf 配置文件
    echo "正在创建 snell.conf 配置文件..."
    cat > /root/snelldocker/snell-conf/snell.conf << EOF || { echo "创建 snell.conf 配置文件失败。退出..." ; exit 1; }
    [snell-server]
    listen = ::0:$RANDOM_PORT
    psk = $RANDOM_PSK
    ipv6 = false
EOF
    echo "snell.conf 配置文件创建完成。"

    # 切换目录
    cd /root/snelldocker || { echo "切换目录失败。退出..." ; exit 1; }

    # 拉取并启动 Docker 容器
    echo "正在拉取并启动 Docker 容器..."
    docker compose pull && docker compose up -d || { echo "拉取并启动 Docker 容器失败。退出..." ; exit 1; }
    echo "Docker 容器拉取并启动完成。"

    # 获取本机IP地址
    HOST_IP=$(curl -s http://checkip.amazonaws.com)

    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/$HOST_IP/country)

    # 输出所需信息，包含IP所在国家
    echo "$IP_COUNTRY = snell, $HOST_IP, $RANDOM_PORT, psk = $RANDOM_PSK, version = 4, reuse = true, tfo = true"
    echo "安装完成。"

    # 删除脚本
    echo "正在删除脚本..."
    rm -- "$0"
    echo "脚本已删除。"
    exit 0
}

# 函数：卸载 Snell
uninstall_snell() {
    echo "正在停止并删除 Docker 容器..."
    cd /root/snelldocker && docker-compose down >/dev/null 2>&1
    echo "Docker 容器已停止并删除。"

    echo "正在删除安装和配置文件..."
    rm -rf /root/snelldocker

    if [ -x "$(command -v docker)" ]; then
        echo "正在卸载 Docker..."
        apt-get remove --purge -y docker docker-engine docker.io containerd runc >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        echo "Docker 已卸载。"
    else
        echo "Docker 未安装，跳过卸载步骤。"
    fi

    if [ -x "$(command -v docker-compose)" ]; then
        echo "正在卸载 Docker Compose..."
        rm /usr/local/bin/docker-compose >/dev/null 2>&1
        echo "Docker Compose 已卸载。"
    else
        echo "Docker Compose 未安装，跳过卸载步骤。"
    fi

    docker system prune -a -f >/dev/null 2>&1

    echo "卸载完成。"
    # 删除脚本
    echo "正在删除脚本..."
    rm -- "$0"
    echo "脚本已删除。"
    exit 0
}

# 函数：输出 Snell 信息
output_snell_info() {
    echo "正在获取 Snell 信息..."

    # 这里可以添加输出 Snell 信息的相关命令

    echo "获取 Snell 信息完成。"
    # 删除脚本
    echo "正在删除脚本..."
    rm -- "$0"
    echo "脚本已删除。"
    exit 0
}

# 主函数
main() {
    echo "请选择操作："
    echo "1. 安装 Snell"
    echo "2. 卸载 Snell"
    echo "3. 输出 Snell 信息"
    read -p "请输入选项编号： " option

    case $option in
        1)
            install_snell
            ;;
        2)
            uninstall_snell
            ;;
        3)
            output_snell_info
            ;;
        *)
            echo "无效选项。退出..."
            exit 1
            ;;
    esac
}

# 调用主函数
main
