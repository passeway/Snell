## 常用 Docker 指令

安装 Docker
```
curl -fsSL https://get.docker.com | bash -s docker
```
查看 Docker 帮助
```
docker --help
```
查看 Docker 版本
```
docker --version
```

正在运行容器
```
docker ps
```
列出所有容器
```
docker ps -a
```
停止容器
```
docker stop id
```
启动容器
```
docker start id
```
删除容器
```
docker rm id
```
卸载 Snell
```
cd /root/snelldocker && \
docker compose down && \
rm -rf /root/snelldocker && \
cd /root
```
卸载Docker
```
sudo docker stop $(sudo docker ps -aq) && \
sudo docker rm $(sudo docker ps -aq) && \
sudo docker rmi $(sudo docker images -q) --force && \
sudo docker network prune -f && \
sudo docker volume prune -f && \
sudo docker system prune -a -f
```
安装 Snell
```
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/Snell/refs/heads/main/Snell-docker.sh)
```
