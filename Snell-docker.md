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
sudo docker stop snell
sudo docker rm snell
rm -rf /root/snelldocker
```

安装 Snell
```
bash <(curl -fsSL https://raw.githubusercontent.com/passeway/Snell/refs/heads/main/Snell-docker.sh)
```
