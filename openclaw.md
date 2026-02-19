############################
# A) OpenClaw：日常查看與控制
############################

openclaw status
# 看總狀態（最常用）：Gateway、模型、通道、session、安全摘要

openclaw status --deep
# 深度檢查：包含更多探測與診斷資訊

openclaw gateway status
# 只看 Gateway 服務狀態（是否可連、是否在跑）

openclaw gateway start
# 啟動 Gateway

openclaw gateway stop
# 停止 Gateway

openclaw gateway restart
# 重啟 Gateway（改配置後常用）

openclaw logs --follow
# 即時追蹤日誌（像 tail -f）


################################
# B) OpenClaw：配置、安全、修復
################################

openclaw configure
# 進入配置流程（首次部署或調整設定）

openclaw configure --section gateway
# 只配置 gateway 區塊（token、bind 等）

openclaw configure --section web
# 配 web_search 相關（例如 Brave API key）

openclaw security audit
# 安全檢查（快速版）

openclaw security audit --deep
# 安全檢查（深入版）

openclaw doctor
# 檢查安裝/服務異常

openclaw doctor --repair
# 自動修復常見問題（服務檔、環境等）


#######################
# C) OpenClaw：更新
#######################

openclaw update
# 升級到新版本


#########################################
# D) systemd（你這台 VPS 很常用）
#########################################

openclaw gateway install
# 安裝 user-level systemd 服務（openclaw-gateway.service）

systemctl --user enable openclaw-gateway.service
# 設成開機（用戶層）自啟動

systemctl --user start openclaw-gateway.service
# 啟動服務

systemctl --user restart openclaw-gateway.service
# 重啟服務

systemctl --user status openclaw-gateway.service --no-pager
# 查看服務狀態（不分頁）

journalctl --user -u openclaw-gateway.service -n 200 --no-pager
# 看最近 200 行服務日誌

journalctl --user -u openclaw-gateway.service -f
# 即時追服務日誌


############################
# E) OpenCode：安裝與維護
############################

curl -fsSL https://opencode.ai/install | bash
# 安裝 OpenCode（官方安裝腳本）

opencode --version
# 看版本，確認可用

opencode upgrade
# 升級 OpenCode

opencode uninstall
# 卸載 OpenCode


################################
# F) OpenCode：登入與模型管理
################################

opencode auth list
# 查看已登入的供應商憑證

opencode auth login
# 新增供應商登入（OpenAI/Anthropic/...）

opencode auth logout
# 登出已配置供應商

opencode models
# 列出可用模型

opencode models openai
# 只列 OpenAI 供應商模型（若支援）


############################
# G) OpenCode：實際執行任務
############################

opencode
# 進入互動式 TUI

opencode run "你的任务描述"
# 一次性執行任務（CLI 模式）

opencode run "只回复当前使用的模型ID"
# 快速檢查目前預設模型

opencode -m openai/gpt-5.3-codex
# 指定模型啟動（臨時覆蓋）


############################
# H) OpenCode：會話與資料
############################

opencode session list
# 查看現有會話列表

opencode stats
# 查看 token/cost 統計

opencode export
# 導出 session 資料（JSON）

opencode import <file_or_url>
# 匯入 session 資料


#############################################
# I) 你現在最實用的三連（每天都用得到）
#############################################

openclaw status
# 先確認 OpenClaw 全局健康

opencode run "请只回复当前使用的模型ID"
# 確認 OpenCode 正在用哪個模型

openclaw logs --follow
# 有異常時立刻追日誌

如果你要，我下一則幫你做「極簡版 10 條」（只留最必要指令，給手機看超快）。