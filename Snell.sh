#!/bin/bash

# 更新系统包和升级
apt-get update && apt-get -y upgrade

# 添加函数以安装 Snell
install_snell() {
    # 安装 Docker
    curl -fsSL https://get.docker.com | bash -s docker

    # 判断并卸载不同版本的 Docker Compose
    if [ -f "/usr/local/bin/docker-compose" ]; then
        sudo rm /usr/local/bin/docker-compose
    fi

    if [ -d "$HOME/.docker/cli-plugins/" ]; then
        rm -rf $HOME/.docker/cli-plugins/
    fi

    # 安装 Docker Compose 插件
    apt-get install docker-compose-plugin -y

    # 创建所需目录
    mkdir -p /root/snelldocker/snell-conf

    # 生成随机端口和密码
    RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
    RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

    # 创建 docker-compose.yml
    cat > /root/snelldocker/docker-compose.yml << EOF
    version: "3.8"
    services:
      snell:
        image: accors/snell:latest
        container_name: snell
        restart: always
        network_mode: host
        volumes:
          - ./snell-conf/snell.conf:/etc/snell-server.conf
        environment:
          - SNELL_URL=https://dl.nssurge.com/snell/snell-server-v4.0.1-linux-amd64.zip
EOF

    # 创建 snell.conf 配置文件
    cat > /root/snelldocker/snell-conf/snell.conf << EOF
    [snell-server]
    listen = ::0:$RANDOM_PORT
    psk = $RANDOM_PSK
    ipv6 = false
EOF

    # 切换目录
    cd /root/snelldocker

    # 拉取并启动 Docker 容器
    docker compose pull && docker compose up -d

    # 获取本机IP地址
    HOST_IP=$(curl -s http://checkip.amazonaws.com)

    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/$HOST_IP/country)

    # 输出所需信息，包含IP所在国家
    echo "$IP_COUNTRY = snell, $HOST_IP, $RANDOM_PORT, psk = $RANDOM_PSK, version = 4, reuse = true, tfo = true"
}

# 添加函数以卸载 Snell 及此项目的 Docker
uninstall_snell() {
    # 停止并删除 Snell 容器
    docker compose down

    # 删除安装目录
    rm -rf /root/snelldocker
}

# 判断用户选择的选项
echo "请选择一个操作："
echo "1. 安装 Snell"
echo "2. 卸载 Snell 和 Docker"
read -p "请输入您的选择（1 或 2）: " choice

case $choice in
    1)
        install_snell
        ;;
    2)
        uninstall_snell
        ;;
    *)
        echo "无效的选择。退出。"
        ;;
esac
