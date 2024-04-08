#!/bin/bash

# 检查是否具有 root 权限
if [ "$(id -u)" != "0" ]; then
    echo "请以 root 权限运行此脚本."
    exit 1
fi

install_snell() {
    # 更新系统包和升级
    apt-get update && apt-get -y upgrade

    # 安装必要的软件包
    apt-get install -y unzip wget curl expect

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
    if [ $? -ne 0 ]; then
        echo "下载 Snell 失败."
        exit 1
    fi

    # 解压缩文件到指定目录
    sudo unzip -o snell-server.zip -d $INSTALL_DIR
    if [ $? -ne 0 ]; then
        echo "解压缩 Snell 失败."
        exit 1
    fi

    # 删除下载的 zip 文件
    rm snell-server.zip

    # 赋予执行权限
    chmod +x $INSTALL_DIR/snell-server

    # 创建配置文件目录
    mkdir -p $CONF_DIR

    # 使用 expect 自动化生成配置文件
    expect << EOF
spawn $INSTALL_DIR/snell-server --wizard -c $CONF_FILE
expect "Create new? \[Y/n\]" { send "Y\r" }
expect "Listening address:" { send "\r" }
expect "Listening port:" { send "\r" }
expect "PSK:" { send "\r" }
expect "Use IPv6?" { send "n\r" }
expect eof
EOF

    # 确认配置文件是否存在
    if [ ! -f "$CONF_FILE" ]; then
        echo "配置文件不存在."
        exit 1
    fi

    # 获取配置中的端口和密码
    RANDOM_PORT=$(grep -oP '(?<=listen = ::0:)\d+' $CONF_FILE)
    RANDOM_PSK=$(grep -oP '(?<=psk = )\S+' $CONF_FILE)

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
    systemctl daemon-reload
    if [ $? -ne 0 ]; then
        echo "重载 Systemd 配置失败."
        exit 1
    fi

    # 开机自启动 Snell
    systemctl enable snell
    if [ $? -ne 0 ]; then
        echo "开机自启动 Snell 失败."
        exit 1
    fi

    # 启动 Snell 服务
    systemctl start snell
    if [ $? -ne 0 ]; then
        echo "启动 Snell 服务失败."
        exit 1
    fi

    # 获取本机IP地址
    HOST_IP=$(curl -s http://checkip.amazonaws.com)

    # 输出所需信息，包含IP所在国家、生成的端口和密码
    echo "Snell 安装成功."
    echo "SG = snell, $HOST_IP, $RANDOM_PORT, psk = $RANDOM_PSK, version = 4, reuse = true, tfo = true"
}

uninstall_snell() {
    # 停止 Snell 服务
    systemctl stop snell
    if [ $? -ne 0 ]; then
        echo "停止 Snell 服务失败."
        exit 1
    fi

    # 禁用开机自启动
    systemctl disable snell
    if [ $? -ne 0 ]; then
        echo "禁用开机自启动失败."
        exit 1
    fi

    # 删除 Systemd 服务文件
    rm /lib/systemd/system/snell.service
    if [ $? -ne 0 ]; then
        echo "删除 Systemd 服务文件失败."
        exit 1
    fi

    # 删除安装的文件和目录
    rm /usr/local/bin/snell-server
    rm -rf /etc/snell

    echo "Snell 卸载成功."
}

# 显示菜单选项
echo "选择操作:"
echo "1. 安装 Snell"
echo "2. 卸载 Snell"
read -p "输入选项: " choice

case $choice in
    1) install_snell ;;
    2) uninstall_snell ;;
    *) echo "无效的选项" ;;
esac
