**`OpenClaw 常用指令大全（Markdown 速查版）`**，
**按真实可用（你当前 2026.2.x 版本）+ 实际使用频率整理**

---

# 🦞 OpenClaw 常用指令速查表

> 适用版本：OpenClaw `2026.2.x`
> 说明：只列 **真实存在、你敲了就能用的命令**（不包含设计中/已废弃）

---

## 📌 1. 状态 / 总览（最常用）

### 查看整体运行状态

```bash
openclaw status
```

### 深度状态检查（推荐排障时用）

```bash
openclaw status --deep
```

### 展示所有信息（适合分享/完整诊断）

```bash
openclaw status --all
```

---

## ⚙️ 2. 配置相关

### 进入配置向导（核心命令）

```bash
openclaw configure
```

用途：

* 选择 / 切换模型
* OAuth 登录
* Gateway / Channel / Skills 配置
  ⚠️ 不会重装、不清空

---

### 初始化环境（⚠️ 仅首次使用）

```bash
openclaw onboard
```

> ⚠️ 已部署环境 **不要再跑**

---

## 🤖 3. 模型相关

### 列出当前可用模型（权威）

```bash
openclaw models list
```

可查看：

* default / fallback
* Auth 状态
* 上下文大小

---

### 查看模型命中情况（结合日志）

```bash
openclaw logs --follow
```

---

## 👤 4. Agent 管理

### 查看所有 agent

```bash
openclaw agent list
```

---

### 设置 agent 默认模型（指令式切换）

```bash
openclaw agent set main \
  --model openai/gpt-5.2-codex \
  -m "switch default model"
```

> ⚠️ `-m / --message` **必须有**

---

## 🧵 5. Session 管理

### 查看当前 sessions

```bash
openclaw sessions list
```

---

### 查看某个 session 详情

```bash
openclaw sessions show <session-id>
```

---

### 关闭 session（立即生效新模型）

```bash
openclaw sessions close <session-id>
```

---

## 🌐 6. Gateway / 服务

### 前台运行 Gateway

```bash
openclaw gateway run
```

---

### 安装 systemd 服务

```bash
openclaw daemon install
```

---

### Gateway systemd 日志

```bash
journalctl -u openclaw-gateway -f
```

---

## 📡 7. Channel（如 Telegram）

### 查看 channel 状态

```bash
openclaw channels list
```

---

### 测试某个 channel

```bash
openclaw channels test telegram
```

---

## 🧠 8. Skills

### 查看已加载的 skills

```bash
openclaw skills list
```

---

## 🔍 9. 日志 / 调试

### 查看最近日志

```bash
openclaw logs
```

---

### 实时跟踪日志（推荐）

```bash
openclaw logs --follow
```

---

## 🛡 10. 安全 / 诊断

### 安全审计

```bash
openclaw security audit
```

---

### 深度安全审计

```bash
openclaw security audit --deep
```

---

### 环境体检（部分版本存在）

```bash
openclaw doctor
```

---

## 🔄 11. 更新 / 维护

### 查看是否有更新

```bash
openclaw status
```

### 执行更新

```bash
openclaw update
```

> ⚠️ 建议系统稳定后再更新

---

## ❌ 12. 常见误用（避坑）

### ❌ 已部署环境不要用

```bash
openclaw onboard
```

### ❌ 下面这些在你版本里不存在

```text
openclaw models promote
openclaw models demote
```

---

## 🧠 一句话记忆法

```text
看状态   → openclaw status
改配置   → openclaw configure
看模型   → openclaw models list
切模型   → openclaw agent set
查问题   → openclaw logs --follow
```

---

## ✅ 推荐常用组合（高频）

```bash
openclaw status
openclaw models list
openclaw logs --follow
```

---

### 如果你愿意，下一步我可以帮你：

* 📄 生成 **PDF / README.md** 版本
* 🧠 给你画一张 **OpenClaw CLI 心智图**
* ⚙️ 输出一份 **只保留你当前需要的最小指令集**

你说要哪一个，我就直接给你。
