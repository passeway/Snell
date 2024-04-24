#!/bin/bash

# 等待其他 apt 进程完成
wait_for_apt() {
    while fuser /var/lib/dpkg/lock >/dev/null 2>&1 ; do
        echo "等待其他 apt 进程完成..."
        sleep 1
    done
}

# 提示用户需要 root 权限运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "请以 root 权限运行此脚本."
    exit 1
fi

install_snell() {
    # 调用等待其他 apt 进程完成函数
    wait_for_apt

    # 判断系统及定义系统安装依赖方式
    REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora")
    RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora")
    PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update")
    PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install")
    PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove" "yum -y remove")
    PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove")

    # 安装必要的软件包
    apt update && sudo apt install -y wget unzip

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
ipv6 = true
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
    echo "Snell 安装成功"
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

# 显示菜单选项
echo "选择操作:"
echo "1. 安装 Snell"
echo "2. 卸载 Snell"
read -p "请输入选项编号: " choice

case $choice in
    1) install_snell ;;
    2) uninstall_snell ;;
    *) echo "无效的选项" ;;
esac
