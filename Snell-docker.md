## 常用 Docker 指令

安装 Docker
```
curl -fsSL https://get.docker.com | bash -s docker
```
卸载 Docker
```
sudo systemctl stop docker docker.socket
sudo apt-get purge -y docker-engine docker docker.io docker-ce docker-ce-cli containerd.io
sudo apt-get purge -y docker-compose-plugin docker-ce-rootless-extras
sudo apt-get autoremove -y --purge
```

常用指令
```
sudo docker ps                 # 运行容器

sudo docker ps -a              # 所有容器

sudo docker rm id              # 删除容器

sudo docker stop id            # 停止容器

sudo docker start id           # 启动容器

sudo docker --help             # Docker 帮助

sudo docker images             # Docker 镜像

sudo docker --version          # Docker 版本

sudo journalctl -u docker      # Docker 日志

sudo systemctl stop docker     # Docker 停止

sudo systemctl start docker    # Docker 启动

sudo systemctl restart docker  # Docker 重启

sudo systemctl status docker   # Docker 状态

sudo docker compose version    # compose版本
```
卸载 Snell
```
sudo docker stop snell
sudo docker rm snell
sudo docker rmi accors/snell
sudo rm -rf /root/snell-docker
```

安装 Snell
```
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/Snell/refs/heads/main/Snell-docker.sh)
```
