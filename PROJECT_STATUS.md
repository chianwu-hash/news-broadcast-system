# 新聞廣播系統 — 專案現況總覽

_最後更新：2026-03-11_

---

## 架構

```
使用者（Telegram）
    ↓
OpenClaw（個人 bot，主要入口）
    ├── /feature → openclaw_feature_bridge.sh → run_feature_news.sh
    ├── /ttsfix  → openclaw_tts_bridge.sh add
    ├── /ttslist → openclaw_tts_bridge.sh list
    └── /ttsrm   → openclaw_tts_bridge.sh remove

Cron（自動排程）
    ├── 07:00 → run_morning_news.sh（早安新聞）
    └── 16:00 → run_evening_news.sh（晚安新聞）
```

---

## 三個節目

| 節目 | 主播 | 聲線 | 觸發方式 | 文章數 |
|---|---|---|---|---|
| 早安新聞 | 小蝦 | zh-TW-HsiaoChenNeural（女）| Cron 07:00 | 8 則 |
| 晚安新聞 | 小鯨 | zh-TW-YunJheNeural（男）| Cron 16:00 | 8 則 |
| 新聞專題 | 小貝 | zh-TW-HsiaoYuNeural（女）| Telegram /feature | 4 則 |

---

## 每集流程

```
search_news（Tavily）
  → select_candidates（DeepSeek 挑選 + 群集）
      → [feature] material_count_gate（< 4 則中止）
      → [feature] source_quality_gate（Tier B 至少 1 個）
  → write_script（DeepSeek 撰稿）
  → generate_tts（edge-tts）
  → mix_audio（BGM 混音）
  → send_telegram_audio
  → send_selected_sources_summary（來源資訊）
  → update_history
  → archive_run_artifacts
```

---

## 搜尋設定

| 節目 | 引擎 | 時效 |
|---|---|---|
| 早安新聞 | Tavily | 最近 2 天（MORNING_TAVILY_DAYS_BACK=2）|
| 晚安新聞 | Tavily | 最近 2 天（EVENING_TAVILY_DAYS_BACK=2）|
| 新聞專題 | Tavily | 不限（Tavily 預設）|

可在 .env 切換：MORNING/EVENING/FEATURE_SEARCH_ENGINE=tavily|brave

---

## 文字稿規則（write_script.sh）

- 數字全部中文化（年份逐字讀、數量口語化）
- 英文縮寫翻譯（AI→人工智慧、NVIDIA→輝達）
- 品牌名無中文者以描述代替，後續用「該公司」代稱
- 播報稿不得含英文字母或阿拉伯數字

---

## TTS 多音字詞典

- 檔案：common/config/tts_user_corrections.json
- 管理：Telegram /ttsfix、/ttslist、/ttsrm
- 套用：normalize_tts_text.py Layer 0（TTS 前處理）
- 目前聲線（edge-tts）不支援 SSML，以詞典替換為主要解法

---

## 歸檔機制

| 節目 | 保留次數 | 目錄 |
|---|---|---|
| 早安新聞 | 7 次 | morning-news/runs/ |
| 晚安新聞 | 7 次 | evening-news/runs/ |
| 新聞專題 | 5 次 | feature-news/runs/ |

每次包含：script.txt、selected.json、candidates.json、音檔、metadata.json

---

## 來源資訊

每次播出後，Telegram 自動附送一則來源訊息：
- 格式：標題 | 媒體域名 | 日期
- 採集時效範圍
- 函數：send_selected_sources_summary()（三支主程式皆已加入）

---

## Telegram 指令（OpenClaw skills）

| 指令 | 功能 |
|---|---|
| /feature <主題> | 觸發新聞專題，主題自由輸入 |
| /ttsfix <原詞> <替換詞> | 新增或更新 TTS 多音字規則 |
| /ttslist | 列出所有 TTS 規則 |
| /ttsrm <原詞> | 移除 TTS 規則 |

---

## 重要檔案

| 檔案 | 說明 |
|---|---|
| .env | 全域設定（聲線、主播名、搜尋引擎、時效等）|
| common/scripts/search_news.sh | 搜尋邏輯，Tavily/Brave 路由 |
| common/scripts/tavily_search.py | Tavily API 呼叫 |
| common/scripts/select_candidates.sh | 候選挑選、群集、gates |
| common/scripts/write_script.sh | AI 撰稿（含中文化規則）|
| common/scripts/normalize_tts_text.py | TTS 前處理（多音字詞典）|
| common/scripts/openclaw_feature_bridge.sh | /feature 橋接腳本 |
| common/scripts/openclaw_tts_bridge.sh | /ttsfix 等橋接腳本 |
| common/config/tts_user_corrections.json | 多音字詞典 |
| common/config/feature_source_quality.json | 新聞專題來源品質設定 |

---

## 待觀察 / 已知限制

| 項目 | 狀態 |
|---|---|
| 晚安新聞偶發候選為空 | 待觀察，是否為持續性問題 |
| 來源日期部分無法解析 | Tavily 部分文章無 published_date |
| OpenClaw SKILL.md 語氣過於自由 | 偶爾加入多餘 AI 分析，待收緊 |
| 多語言 TTS 分支（Azure）| 長期規劃，詳見 tts_multilingual_plan.md（記憶目錄）|

---

## 雙 bot token 規劃（未來）

- Bot A（個人）：OpenClaw，處理所有指令
- Bot B（公開）：telegram_feature_listener.sh，開放給其他使用者
- 目前 listener 未啟動（not running），架構已具備基礎
