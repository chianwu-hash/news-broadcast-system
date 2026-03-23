# Session 共享溝通板

> 這份文件是兩個 Claude Code session 的共用黑板。
> 任一 session 可讀寫此文件來傳遞任務、狀態、發現。
> 每次更新請在最上方加一筆 Log，格式如下。

---

## 使用規則

- **Cursor session**（主要開發）：在 Cursor 內與用戶對話的 Claude Code
- **Remote session**（遠端/手機操作）：透過 `/remote-control` 開啟的 Claude Code
- 任何 session 完成重要工作後，請更新下方的 **Current State** 與 **Log**
- 讀到此文件時，先看 Current State 了解現況，再看 Log 了解歷史

---

## Current State

_最後更新：2026-03-23 18:47 by Remote session_

| 項目 | 狀態 |
|---|---|
| 進行中任務 | 無 |
| 待處理 | 圖片下載偶發超時（已延長至 180s，待觀察）|
| 上次完成 | 用戶匿名化（用戶#3f2a）+ Gemini 圖片偵測修正 |
| nblm-bot | 運行中 |

---

## 任務佇列

> 任一 session 可在此新增任務，完成後打勾。

- [ ] （空）

---

## Log

| 時間 | Session | 內容 |
|---|---|---|
| 2026-03-23 18:47 | Remote | 圖片下載超時 90s→180s |
| 2026-03-23 18:40 | Remote | 補送飛魚季資訊圖表（下載超時，手動補救） |
| 2026-03-23 13:31 | Remote | /topic 和 /nblm 移除 reply_to，避免引用顯示真實姓名 |
| 2026-03-23 13:23 | Remote | 匿名格式改 SHA256 hash（用戶#3f2a）；清空舊 map 重建 |
| 2026-03-23 12:00 | Remote | 補送 CPBL 資訊圖表到正確群組（NBLM_CHAT_ID） |
| 2026-03-23 11:42 | Remote | Gemini 圖片偵測：超時 240s→300s、放寬 selector（中英文下載按鈕）、加診斷 log |
| 2026-03-23 11:39 | Remote | 用戶匿名化：get_sender_display() 回傳用戶#001、user_id_map.json 持久化、/topic log 記真名 |
| 2026-03-23 | Remote | Claude Code settings.json 設 bypassPermissions |
| 2026-03-23 | Remote | 上線並讀取同步；確認 Cursor session 完成：/intro 指令、nblm_cdp.py 兩項 bug 修正、SHARED.md/CLAUDE.md 建立 |
| 2026-03-23 09:34 | Cursor | 建立此共享文件；修正 nblm_cdp.py before_imgs 錯誤與 Gemini 輸入框重試邏輯 |
