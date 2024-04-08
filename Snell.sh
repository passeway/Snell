#!/bin/bash

install_dependencies() {
    if [ -x "$(command -v apt-get)" ]; then
        # Debian/Ubuntu 系统
        sudo apt-get update && sudo apt-get -y upgrade
        sudo apt-get install -y unzip wget curl
    elif [ -x "$(command -v yum)" ]; then
        # CentOS/RHEL 系统
        sudo yum update -y
        sudo yum install -y unzip wget curl
    elif [ -x "$(command -v dnf)" ]; then
        # Fedora 系统
        sudo dnf upgrade -y
        sudo dnf install -y unzip wget curl
    else
        echo "未知的 Linux 发行版，无法安装依赖。"
        exit 1
    fi
}

install_snell() {
    # 安装依赖
    install_dependencies

    # 更新系统包和升级
    apt-get update && apt-get -y upgrade

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
    if [ $? -ne 0 ]; then
        echo "重载 Systemd 配置失败."
        exit 1
    fi

    # 开机自启动 Snell
    sudo systemctl enable snell
    if [ $? -ne 0 ]; then
        echo "开机自启动 Snell 失败."
        exit 1
    fi

    # 启动 Snell 服务
    sudo systemctl start snell
    if [ $? -ne 0 ]; then
        echo "启动 Snell 服务失败."
        exit 1
    fi

    # 获取本机IP地址
    HOST_IP=$(curl -s http://checkip.amazonaws.com)

    # 获取IP所在国家
    IP_COUNTRY=$(curl -s http://ipinfo.io/$HOST_IP/country)

    # 输出所需信息，包含IP所在国家
    echo "Snell 安装成功."
    echo "$IP_COUNTRY = snell, $HOST_IP, $RANDOM_PORT, psk = $RANDOM_PSK, version = 4, reuse = true, tfo = true"
}

uninstall_snell() {
    # 停止 Snell 服务
    sudo systemctl stop snell
    if [ $? -ne 0 ]; then
        echo "停止 Snell 服务失败."
        exit 1
    fi

    # 禁用开机自启动
    sudo systemctl disable snell
    if [ $? -ne 0 ]; then
        echo "禁用开机自启动失败."
        exit 1
    fi

    # 删除 Systemd 服务文件
    sudo rm /lib/systemd/system/snell.service
    if [ $? -ne 0 ]; then
        echo "删除 Systemd 服务文件失败."
        exit 1
    fi

    # 删除安装的文件和目录
    sudo rm /usr/local/bin/snell-server
    sudo rm -rf /etc/snell

    echo "Snell 卸载成功."
}

restart_snell() {
    # 重启 Snell 服务
    sudo systemctl restart snell
    if [ $? -ne 0 ]; then
        echo "重启 Snell 服务失败."
        exit 1
    fi

    echo "Snell 服务已重启."
}

view_snell_status() {
    # 查看 Snell 服务状态
    sudo systemctl status snell | grep "Active: active" > /dev/null
    if [ $? -eq 0 ]; then
        echo "Snell 服务正在运行."
    else
        echo "Snell 服务未在运行."
    fi
}

view_snell_logs() {
    # 查看 Snell 输出信息
    echo "Snell 安装成功后输出的信息:"
    journalctl -u snell | grep "Snell 安装成功"
}

# 显示菜单选项
echo "选择操作:"
echo "1. 安装 Snell"
echo "2. 卸载 Snell"
echo "3. 重启 Snell"
echo "4. 查看 Snell 服务状态"
echo "5. 查看 Snell 输出信息"
read -p "输入选项: " choice

case $choice in
    1) install_snell ;;
    2) uninstall_snell ;;
    3) restart_snell ;;
    4) view_snell_status ;;
    5) view_snell_logs ;;
    *) echo "无效的选项" ;;
esac
