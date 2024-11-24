#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
RESET='\033[0m'

# 更新系统包
echo -e "${GREEN}更新系统包...${RESET}"
apt-get update && apt-get -y upgrade

# 检测 Docker 安装
if ! command -v docker >/dev/null 2>&1; then
    echo -e "${GREEN}安装 Docker...${RESET}"
    curl -fsSL https://get.docker.com | bash -s docker || { echo "Docker 安装失败！"; exit 1; }
fi

# 安装 Docker Compose 插件
echo -e "${GREEN}安装 Docker Compose 插件...${RESET}"
apt-get install -y docker-compose-plugin

# 准备目录
mkdir -p /root/snelldocker/snell-conf

# 生成随机端口和密码
RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
RANDOM_PSK=$(openssl rand -base64 16 | tr -dc 'A-Za-z0-9')

# 检测架构
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip" ;;
    arm64|aarch64) DOWNLOAD_URL="https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-aarch64.zip" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

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
EOF

# 创建 Snell 配置文件
cat > /root/snelldocker/snell-conf/snell.conf << EOF
[snell-server]
listen = ::0:${RANDOM_PORT}
psk = ${RANDOM_PSK}
ipv6 = true
EOF

# 拉取镜像并启动
cd /root/snelldocker
docker compose pull && docker compose up -d

# 获取 IP 和国家
HOST_IP=$(curl -s http://checkip.amazonaws.com)
IP_COUNTRY=$(curl -s http://ipinfo.io/$HOST_IP/country)

# 输出客户端配置
echo -e "${GREEN}生成的 Snell 客户端配置如下:${RESET}"
cat << EOF > /root/snelldocker/snell-conf/snell.txt
${IP_COUNTRY} = snell, ${HOST_IP}, ${RANDOM_PORT}, psk = ${RANDOM_PSK}, version = 4, reuse = true
EOF
cat /root/snelldocker/snell-conf/snell.txt
