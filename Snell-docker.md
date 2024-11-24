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
rm -rf /root/snelldocker
```
卸载Docker
```
sudo apt-get remove --purge -y docker docker-engine docker.io containerd runc docker-compose-plugin && \
sudo apt-get autoremove -y && \
sudo docker system prune -a -f
```



