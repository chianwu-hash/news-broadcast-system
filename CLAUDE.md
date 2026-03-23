# Claude Code — 專案指引

## 重要：多 Session 協作

此專案可能同時有多個 Claude Code session 運行（Cursor + Remote Control）。

**每次對話開始時請先讀 `SHARED.md`**，了解：
- 目前任務狀態
- 上一個 session 做了什麼
- 是否有待處理事項

**完成重要工作後請更新 `SHARED.md`**：
- 更新 Current State
- 在 Log 新增一筆記錄（格式：時間 | Session 名稱 | 內容）

Session 識別：
- Cursor 內 → 標記為 **Cursor session**
- `/remote-control` 開啟 → 標記為 **Remote session**

---

## 專案概覽

- 專案路徑：`/home/vboxuser/news-broadcast-system`
- 三個新聞節目：早安新聞、晚安新聞、新聞專題
- nblm-audio：NotebookLM 語音摘要系統（`/home/vboxuser/nblm-audio/`）
- 詳細架構見 `PROJECT_STATUS.md` 與 memory/MEMORY.md

## 常用指令

```bash
# Bot 狀態
systemctl --user status nblm-bot.service

# Bot 重啟
systemctl --user restart nblm-bot.service

# 查看 Bot log
journalctl --user -u nblm-bot.service -f
```
