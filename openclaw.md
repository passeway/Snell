# OpenClaw / OpenCode 运维与使用手册（完整版）

## A) OpenClaw：日常查看与控制

```bash
openclaw status
# 看总状态（最常用）：Gateway、模型、通道、session、安全摘要
```

```bash
openclaw status --deep
# 深度检查：包含更多探测与诊断信息
```

```bash
openclaw gateway status
# 只看 Gateway 服务状态（是否可连、是否在运行）
```

```bash
openclaw gateway start
# 启动 Gateway 服务
```

```bash
openclaw gateway stop
# 停止 Gateway 服务
```

```bash
openclaw gateway restart
# 重启 Gateway（改配置后常用）
```

```bash
openclaw logs --follow
# 实时追踪日志（等价 tail -f 的体验）
```

---

## B) OpenClaw：配置、安全、修复

```bash
openclaw configure
# 进入交互式配置流程（首次部署或调整设置）
```

```bash
openclaw configure --section gateway
# 只配置 gateway 区块（token、bind 等）
```

```bash
openclaw configure --section web
# 只配置 web_search 区块（例如 Brave API key）
```

```bash
openclaw security audit
# 安全检查（快速版）
```

```bash
openclaw security audit --deep
# 安全检查（深入版）
```

```bash
openclaw doctor
# 检查安装/服务异常并给出建议
```

```bash
openclaw doctor --repair
# 自动修复常见问题（服务文件、环境等）
```

```bash
openclaw doctor --fix
# 与 --repair 同义
```

```bash
openclaw update
# 升级到新版本
```

---

## C) OpenClaw：Gateway 相关补充

```bash
openclaw gateway install
# 安装/确保 user-level systemd 服务（openclaw-gateway.service）
```

```bash
openclaw gateway install --force
# 强制重装 Gateway 服务
```

```bash
openclaw gateway uninstall
# 卸载 Gateway 服务
```

```bash
openclaw gateway probe
# 网关可达性与健康探测（本地/远程）
```

```bash
openclaw gateway health
# 拉取 Gateway health 信息
```

---

## D) systemd（你这台 VPS 常用）

```bash
systemctl --user enable openclaw-gateway.service
# 设为用户层开机自启
```

```bash
systemctl --user start openclaw-gateway.service
# 启动服务
```

```bash
systemctl --user restart openclaw-gateway.service
# 重启服务
```

```bash
systemctl --user stop openclaw-gateway.service
# 停止服务
```

```bash
systemctl --user status openclaw-gateway.service --no-pager
# 查看服务状态（不分页）
```

```bash
journalctl --user -u openclaw-gateway.service -n 200 --no-pager
# 查看最近 200 行服务日志
```

```bash
journalctl --user -u openclaw-gateway.service -f
# 实时追踪服务日志
```

```bash
systemctl --user is-enabled openclaw-gateway.service
# 检查是否开机自启
```

```bash
systemctl --user is-active openclaw-gateway.service
# 检查是否正在运行
```

---

## E) OpenCode：安装与维护

```bash
curl -fsSL https://opencode.ai/install | bash
# 安装 OpenCode（官方脚本）
```

```bash
opencode --version
# 查看版本，确认可用
```

```bash
opencode upgrade
# 升级 OpenCode
```

```bash
opencode uninstall
# 卸载 OpenCode
```

---

## F) OpenCode：登录与模型管理

```bash
opencode auth list
# 查看已登录的供应商凭证
```

```bash
opencode auth login
# 新增供应商登录（OpenAI/Anthropic/...）
```

```bash
opencode auth logout
# 登出已配置供应商
```

```bash
opencode models
# 列出可用模型
```

```bash
opencode models openai
# 只列 OpenAI 提供商模型（若支持）
```

---

## G) OpenCode：执行任务

```bash
opencode
# 进入交互式 TUI
```

```bash
opencode run "你的任务描述"
# 一次性执行任务（CLI 模式）
```

```bash
opencode run "只回复当前使用的模型ID"
# 快速检查当前默认模型
```

```bash
opencode -m openai/gpt-5.3-codex
# 临时指定模型启动
```

```bash
opencode serve
# 启动 headless opencode server
```

```bash
opencode web
# 启动服务并打开 Web 界面
```

---

## H) OpenCode：会话与数据

```bash
opencode session list
# 查看现有会话列表
```

```bash
opencode session delete <sessionID>
# 删除指定会话
```

```bash
opencode stats
# 查看 token/cost 统计
```

```bash
opencode export
# 导出 session 数据（JSON）
```

```bash
opencode export <sessionID>
# 导出指定会话
```

```bash
opencode import <file_or_url>
# 导入 session 数据
```
