# Session 共享溝通板

> 這份文件是多個 Claude Code session 的共用黑板。
> 任一 session 可讀寫此文件來傳遞任務、狀態、發現。
> 每次更新請在最上方加一筆 Log，格式如下。

---

## 使用規則

- **VSCode session**（主要開發）：在 VSCode 側邊欄開啟的 Claude Code
- **Telegram session**：透過 `claude --channels` 從 Telegram 操作的 Claude Code
- **Terminal session**：在 VM terminal 直接跑 `claude` 的 session
- 任何 session 完成重要工作後，請更新下方的 **Current State** 與 **Log**
- 讀到此文件時，先看 Current State 了解現況，再看 Log 了解歷史

---

## Current State

_最後更新：2026-05-03 by VSCode session_

| 項目 | 狀態 |
|---|---|
| 進行中任務 | 無 |
| 待處理 | 舊版 YouTube 影片（er9v-GVWBoI 等）請手動到 YouTube Studio 刪除 |
| 上次完成 | Storyboard pipeline Phase 3 完善（見下方說明） |
| nblm-bot | 運行中 |
| claude-telegram.service | 運行中 |

---

## 重要系統變更（2026-05-03）

### Storyboard Pipeline Phase 3 完善
- **腳本位置**：`/home/vboxuser/nblm-audio/storyboard/`
- **三階段流程**：`run_pipeline.sh`（場景規劃）→ Claude 寫提示詞 → `generate_images.sh`（生圖）→ `compose_video.sh`（合成）→ `upload_storyboard.py`（上傳）
- **影片合成改善**：
  - 轉場改為單一 `fade`（原為隨機 8 種，速度較慢）
  - sequential xfade（兩兩合併）避免 OOM
- **Scene boundary 修正流程確立**：DeepSeek 自動切點後，由 Claude 對照 SRT 信號詞修正，再由 Codex 二次確認
- **scene_planner.py prompt 更新**：加入信號詞對齊說明，改善自動切點品質
- **已知問題**：compose 結尾有時 moov atom not found，手動補跑音訊合併即可（見 memory/project_storyboard_pipeline.md）
- **本集成品**：國二下英文 副詞比較級最高級，YouTube: https://www.youtube.com/watch?v=6BbPSMq4h0A

## 重要系統變更（2026-04-13）

### claude-telegram.service 修復
- **問題**：`script -q -c '...'` PTY 不夠真實，bun 無法啟動
- **解法**：Python PTY wrapper（`/home/vboxuser/.local/bin/claude-channels-wrapper.py`）
  - `os.fork()` + `os.openpty()` 建立真實 PTY
  - 回應 terminal attribute queries（DA1/XTVER）
  - 偵測信任對話框後送 `\r` 確認
- **WorkingDirectory** 設為 `/home/vboxuser/news-broadcast-system`，讓 Telegram session 讀到 CLAUDE.md 和 memory

### 教育版帳號 NotebookLM UI 差異（step_customize_audio）
- **問題**：A2 帳號（thps016@gsuite.ntpc.edu.tw，教育版 Pro）UI 和一般帳號不同
  - 一般版：點 tile → dialog 出現 → 填提示詞
  - 教育版：tile 直接生成（無 dialog），自訂需點 `button[aria-label="自訂語音摘要"]`（chevron 按鈕）
- **解法**：`step_customize_audio` 優先找 chevron 按鈕，找不到才 fallback 到 tile

### 自訂 Subagent（file-executor）
- 位置：`~/.claude/agents/file-executor.md`
- 用途：讀寫檔案、執行 bash，跑 Haiku 節省費用
- **使用方式**：Claude 會依 CLAUDE.md 指示，對單純 I/O 任務主動使用，不需點名
- **限制**：subagent 不能再召喚 subagent

---

## 任務佇列

> 任一 session 可在此新增任務，完成後打勾。

- [ ] （空）

---

## Log

| 時間 | Session | 內容 |
|---|---|---|
| 2026-05-03 09:00 | VSCode | Storyboard pipeline 完善：fade 轉場、sequential xfade、scene boundary 修正流程、DeepSeek prompt 更新 |
| 2026-04-13 14:00 | VSCode | 更新 file-executor 說明：Claude 主動路由，移除「必須點名」誤導描述 |
| 2026-04-13 12:30 | VSCode | 教育版帳號 step_customize_audio 修正（chevron 按鈕優先） |
| 2026-04-13 11:30 | VSCode | 建立 ~/.claude/agents/file-executor.md（Haiku subagent）|
| 2026-04-13 10:00 | VSCode | memory 更新：episode_page、telegram bridge 已完成狀態 |
| 2026-04-12 17:23 | VSCode | claude-telegram.service WorkingDirectory 改為 news-broadcast-system |
| 2026-04-12 17:03 | VSCode | claude-telegram.service PTY wrapper 修復，bun 成功啟動 |
| 2026-04-12 | VSCode | episode_page.py + aitalktoyou-web Vercel 部署完成 |
| 2026-04-12 | VSCode | daily_report.py 修正（import json、DBUS env） |
| 2026-04-12 | VSCode | YouTube OAuth token 更新 |
| 2026-03-23 18:47 | Remote | 圖片下載超時 90s→180s |
| 2026-03-23 18:40 | Remote | 補送飛魚季資訊圖表（下載超時，手動補救） |
| 2026-03-23 13:31 | Remote | /topic 和 /nblm 移除 reply_to，避免引用顯示真實姓名 |
| 2026-03-23 13:23 | Remote | 匿名格式改 SHA256 hash（用戶#3f2a）；清空舊 map 重建 |
| 2026-03-23 12:00 | Remote | 補送 CPBL 資訊圖表到正確群組（NBLM_CHAT_ID） |
| 2026-03-23 11:42 | Remote | Gemini 圖片偵測：超時 240s→300s、放寬 selector（中英文下載按鈕）、加診斷 log |
| 2026-03-23 11:39 | Remote | 用戶匿名化：get_sender_display() 回傳用戶#001、user_id_map.json 持久化、/topic log 記真名 |
| 2026-03-23 | Remote | Claude Code settings.json 設 bypassPermissions |
| 2026-03-23 | Remote | 上線並讀取同步 |
| 2026-03-23 09:34 | Cursor | 建立此共享文件；修正 nblm_cdp.py before_imgs 錯誤與 Gemini 輸入框重試邏輯 |
