# Claude Code — 專案指引

## Codex / Claude Code 共同協作規則

本專案允許 Codex 與 Claude Code 在同一個 VS Code 專案 / repo 中協作。協作時不要依賴聊天歷史，也不要互相猜測狀態；請以 repo 內文件作為交接來源。

共同交接文件：

- `docs/development/agent-handoff.md`

Claude Code 接手任務前，請先讀：

1. `docs/development/agent-handoff.md`
2. `SHARED.md`
3. `README.md`
4. 任務相關的 SOP、docs、README 或設定檔

若希望 Codex 接手，必須在 `docs/development/agent-handoff.md` 寫清楚下一步，而不是只在聊天裡說明。

若 Codex 的判斷與 Claude Code 不同，請先比對實際檔案、git diff、grep / rg 結果或驗證命令，不要直接否定。

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

## 專案工作原則

- 先讀專案現有 SOP、`README.md`、`SHARED.md`、`docs/` 與任務相關文件。
- 不只仿照畫面或表層結構；修改前要理解既有功能、共用模組、資料流與驗證方式。
- 以實際檔案內容為準，不以聊天摘要或記憶作為唯一依據。
- 若資訊只是推測，必須標記為「待驗證」。
- 若發現目前檔案內容與交接描述不同，先把 evidence 寫入 `docs/development/agent-handoff.md`。

## Claude Code 工作規則

- 回報完成時必須附上實際 evidence。
- Evidence 可以包含：
  - `grep` / `rg` 結果
  - 檔案路徑
  - 關鍵函式名稱
  - 驗證指令與結果
  - git diff 或 git status 摘要
- 不要求 Codex 讀聊天歷史；要交接就寫進 `docs/development/agent-handoff.md`。
- 若兩個 agent 可能同時工作，先在 `docs/development/agent-handoff.md` 登記 File Ownership。
- 不覆蓋 Codex 或使用者的改動；若需要接手同一批檔案，先在 handoff 中說明。

## 完成回報格式

Claude Code 完成任務時，請用以下格式回報：

```text
目標：

改了哪些檔案：

沒碰哪些檔案：

做了哪些驗證：

還有哪些未驗證：

風險或待確認事項：
```

## Subagent 使用規則

**遇到以下情況，主動使用 `file-executor` subagent（不需等用戶點名）：**
- 讀取、寫入、編輯檔案（單純 I/O，不需推理）
- 執行簡單 bash 指令（ls、cat、systemctl status、journalctl 等）
- 跑 Python 腳本或 shell 腳本（不需看輸出來決定下一步）

**不使用 file-executor 的情況：**
- 需要根據執行結果決定下一步（結果會影響後續邏輯）
- 需要編輯多個檔案且彼此有依賴關係
- 任務需要推理、規劃或多輪工具呼叫

目的：節省主 session token 費用，Haiku 處理簡單任務。

---

## 常用指令

```bash
# Bot 狀態
systemctl --user status nblm-bot.service

# Bot 重啟
systemctl --user restart nblm-bot.service

# 查看 Bot log
journalctl --user -u nblm-bot.service -f
```
