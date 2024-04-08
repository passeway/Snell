#!/bin/bash

# 更新系统包和升级
apt-get update && apt-get -y upgrade

# 安装必要的软件包
apt-get install -y unzip wget curl

# 下载 Snell 服务器文件
SNELL_VERSION="v4.0.1"
ARCH=$(arch)
SNELL_URL=""
INSTALL_DIR="/usr/local/bin"
SYSTEMD_SERVICE_FILE="/lib/systemd/system/snell.service"
CONF_DIR="/etc/snell"
CONF_FILE="$CONF_DIR/snell-server.conf"

if [[ $ARCH == "aarch64" ]]; then
    SNELL_URL="https://dl.nssurge.com/snell/snell-server-$SNELL_VERSION-linux-aarch64.zip"
else
    SNELL_URL="https://dl.nssurge.com/snell/snell-server-$SNELL_VERSION-linux-amd64.zip"
fi

# 下载 Snell 服务器文件
wget $SNELL_URL -O snell-server.zip

# 解压缩文件到指定目录
sudo unzip -o snell-server.zip -d $INSTALL_DIR

# 删除下载的 zip 文件
rm snell-server.zip

# 赋予执行权限
chmod +x $INSTALL_DIR/snell-server

# 生成随机端口和密码
RANDOM_PORT=$(shuf -i 30000-65000 -n 1)
RANDOM_PSK=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

# 创建配置文件目录
mkdir -p $CONF_DIR

# 创建配置文件
cat > $CONF_FILE << EOF
[snell-server]
listen = ::0:$RANDOM_PORT
psk = $RANDOM_PSK
ipv6 = false
EOF

# 创建 Systemd 服务文件
cat > $SYSTEMD_SERVICE_FILE << EOF
[Unit]
Description=Snell Proxy Service
After=network.target

[Service]
Type=simple
User=nobody
Group=nogroup
LimitNOFILE=32768
ExecStart=/usr/local/bin/snell-server -c $CONF_FILE
AmbientCapabilities=CAP_NET_BIND_SERVICE
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=snell-server

[Install]
WantedBy=multi-user.target
EOF

# 重载 Systemd 配置
sudo systemctl daemon-reload

# 开机自启动 Snell
sudo systemctl enable snell

# 启动 Snell 服务
sudo systemctl start snell

# 获取本机IP地址
HOST_IP=$(curl -s http://checkip.amazonaws.com)

# 获取IP所在国家
IP_COUNTRY=$(curl -s http://ipinfo.io/$HOST_IP/country)

# 输出所需信息，包含IP所在国家
echo "$IP_COUNTRY = snell, $HOST_IP, $RANDOM_PORT, psk = $RANDOM_PSK, version = 4, reuse = true, tfo = true"
