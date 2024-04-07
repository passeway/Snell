#!/bin/bash

# 函数：安装 Snell
install_snell() {
    # 更新系统包和升级
    apt-get update && apt-get -y upgrade

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

# 函数：卸载 Snell
uninstall_snell() {
    # 停止并删除 Snell Docker 容器
    echo "正在停止并删除 Docker 容器..."
    cd /root/snelldocker
    docker compose down >/dev/null 2>&1
    echo "Docker 容器已停止并删除。"

    # 删除安装和配置文件
    echo "正在删除安装和配置文件..."
    rm -rf /root/snelldocker

    # 检查 Docker 是否安装，如果安装则卸载
    if [ -x "$(command -v docker)" ]; then
        echo "正在卸载 Docker..."
        apt-get remove --purge -y docker docker-engine docker.io containerd runc >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        echo "Docker 已卸载。"
    else
        echo "Docker 未安装，跳过卸载步骤。"
    fi

    # 检查 Docker Compose 插件是否安装，如果安装则卸载
    if [ -x "$(command -v docker-compose)" ]; then
        echo "正在卸载 Docker Compose 插件..."
        apt-get remove --purge -y docker-compose-plugin >/dev/null 2>&1
        apt-get autoremove -y >/dev/null 2>&1
        echo "Docker Compose 插件已卸载。"
    else
        echo "Docker Compose 插件未安装，跳过卸载步骤。"
    fi

    # 清理未使用的 Docker 资源
    docker system prune -a -f >/dev/null 2>&1

    # 完成
    echo "卸载完成。"
}

# 主程序
echo "请选择操作："
echo "1. 安装 Snell"
echo "2. 卸载 Snell"
read -p "请选择操作的编号： " choice

case $choice in
    1) install_snell;;
    2) uninstall_snell;;
    *) echo "无效选项.";;
esac
