#!/bin/bash

# 获取用户选择
echo "请选择操作:"
echo "1. 安装 Snell Docker 容器"
echo "2. 卸载 Snell Docker 容器"
read -p "输入选项(1或2): " choice

# 安装操作
if [ "$choice" == "1" ]; then
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
    # ... 省略创建 docker-compose.yml 和 snell.conf 的代码

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

# 卸载操作
elif [ "$choice" == "2" ]; then
    # 停止并删除 Snell Docker 容器
    docker stop snell && docker rm snell

    # 删除 Snell Docker 目录
    rm -rf /root/snelldocker

    echo "Snell Docker 容器已成功卸载。"

else
    echo "无效选项,请输入1或2。"
fi
