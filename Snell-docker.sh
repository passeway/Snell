#!/bin/bash
# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
RESET='\033[0m'

# 更新系统包和升级
apt-get update && apt-get -y upgrade

# 检测是否已安装 Docker
if command -v docker >/dev/null 2>&1; then
    echo "Docker 已安装，版本信息如下："
    docker --version
else
    echo "Docker 未安装，正在安装 Docker"
    # 安装 Docker
    curl -fsSL https://get.docker.com | bash -s docker
    if [ $? -ne 0 ]; then
        echo "Docker 安装失败，请检查网络连接或安装脚本"
        exit 1
    fi
    echo "Docker 安装成功！"
fi

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

# 检测系统架构
ARCH=$(uname -m)

if [ "$ARCH" == "x86_64" ]; then
    DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip"
elif [[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]]; then
    DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-aarch64.zip"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# 创建 docker-compose.yml
cat > /root/snelldocker/docker-compose.yml << EOF
services:
  snell:
    image: accors/snell:latest
    container_name: snell
    restart: always
    network_mode: host
    volumes:
      - ./snell-conf/snell.conf:/etc/snell-server.conf
    environment:
      - SNELL_URL=$ARCH
EOF

# 创建 snell.conf 配置文件
cat > /root/snelldocker/snell-conf/snell.conf << EOF
[snell-server]
listen = ::0:$RANDOM_PORT
psk = $RANDOM_PSK
ipv6 = true
EOF

# 切换目录
cd /root/snelldocker

# 拉取并启动 Docker 容器
docker compose pull && docker compose up -d

# 获取本机IP地址
HOST_IP=$(curl -s http://checkip.amazonaws.com)

# 获取IP所在国家
IP_COUNTRY=$(curl -s http://ipinfo.io/$HOST_IP/country)

# 输出客户端信息

echo -e "${GREEN}Snell 示例配置${RESET}"
cat << EOF > /root/snelldocker/snell.txt
${IP_COUNTRY} = snell, ${HOST_IP}, ${RANDOM_PORT}, psk = ${RANDOM_PSK}, version = 4, reuse = true
EOF
cat /root/snelldocker/snell.txt
