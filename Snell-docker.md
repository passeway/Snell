## 常用 Docker 指令

安装 Docker
```
curl -fsSL https://get.docker.com | bash -s docker
```
卸载 Docker
```
sudo systemctl stop docker docker.socket
sudo apt-get purge -y docker docker-engine docker.io containerd runc
sudo apt-get autoremove -y
sudo rm -rf /var/lib/docker
sudo rm -rf /etc/docker
sudo rm -rf /var/run/docker.sock
sudo apt-get remove --purge -y docker-compose-plugin
sudo apt-get autoremove -y
sudo docker system prune -a -f
```

常用指令
```
docker ps               # 运行容器

#docker ps -a           # 所有容器

docker rm id            # 删除容器

docker stop id          # 停止容器

docker start id         # 启动容器

docker --help           # Docker 帮助

docker --version        # Docker 版本

docker images           # Docker 镜像
```
卸载 Snell
```
sudo docker stop snell
sudo docker rm snell
sudo docker rmi accors/snell
sudo rm -rf /root/snelldocker
```

安装 Snell
```
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/Snell/refs/heads/main/Snell-docker.sh)
```
