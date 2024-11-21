## 终端预览

![preview](image.png)


## 一键脚本

```
bash <(curl -fsSL snell-ten.vercel.app)
```

## 详细说明

- 执行脚本即可自动部署 Snell 代理服务器

- 脚本会生成随机端口和 PSK 并配置在 Snell 服务器中

- 执行完脚本后，你会得到客户端配置 url 方便快速设置

## 常用指令

```
systemctl start snell               # 启动 Snell 服务

systemctl stop snell                # 停止 Snell 服务

systemctl status snell              # 查看 Snell 状态

systemctl restart snell             # 重启 Snell 服务

cat /etc/snell/snell-server.conf    # 查看 Snell 配置

vim /etc/snell/snell-server.conf    # 修改 Snell 配置
```
## 项目地址：https://manual.nssurge.com/others/snell.html


