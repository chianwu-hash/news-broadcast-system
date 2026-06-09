# common/scripts — 腳本索引與維護手冊

本目錄是三個新聞節目（早安 / 晚安 / 新聞專題）的共用腳本庫。
所有腳本設計為 **library（用 `source` 載入）**，不能直接執行，除非特別說明。

---

## Pipeline 流程

```
run_{morning,evening,feature}_news.sh
  │
  ├─ load_env.sh          ← 載入 .env，設定節目專屬變數
  ├─ search_news.sh       ← 搜尋新聞（Tavily / Brave）
  ├─ select_candidates.sh ← DeepSeek 篩選候選新聞
  ├─ write_script.sh      ← DeepSeek 撰寫播報稿
  ├─ generate_tts.sh      ← edge-tts 語音合成（含多音字正規化）
  ├─ mix_audio.sh         ← ffmpeg BGM 混音
  └─ send_telegram.sh     ← 傳送音訊 + 來源摘要到 Telegram
```

每個節目的進入點：

| 節目 | 進入點 |
|---|---|
| 早安新聞（Cron 07:00）| `morning-news/run_morning_news.sh` |
| 晚安新聞（Cron 16:00）| `evening-news/run_evening_news.sh` |
| 新聞專題（Telegram /feature）| `common/scripts/run_feature_news.sh` |

---

## 腳本索引

### Library（必須 `source` 載入，不能直接執行）

| 腳本 | 功能 |
|---|---|
| `load_env.sh` | 載入 `.env`，依 `morning / evening / feature` 模式設定節目專屬變數 |
| `common.sh` | `log()` / `die()` 等共用 utility |
| `search_news.sh` | 搜尋新聞，輸出 `raw_search_results.json` |
| `select_candidates.sh` | 篩選候選新聞，輸出 `candidates.json` + `selected.json` |
| `write_script.sh` | 撰寫播報稿，輸出 `script.txt` |
| `generate_tts.sh` | 語音合成（含多音字正規化），輸出 `voice.mp3` |
| `mix_audio.sh` | BGM 混音，輸出 `news.mp3` |
| `send_telegram.sh` | 傳送音訊 + 來源摘要 |

### 可直接執行的腳本

| 腳本 | 功能 | 用法 |
|---|---|---|
| `normalize_tts_text.py` | TTS 前處理（多音字正規化）| `python3 normalize_tts_text.py <input.txt> <output.txt>` |
| `doctor.sh` | 環境健康檢查 | `bash doctor.sh` |
| `openclaw_tts_bridge.sh` | `/ttsfix` / `/ttslist` / `/ttsrm` Telegram 指令橋接 | 由 OpenClaw 呼叫 |
| `openclaw_feature_bridge.sh` | `/feature` 指令橋接 | 由 OpenClaw 呼叫 |
| `source_quality_gate.py` | 新聞專題來源品質驗證 | 由 `select_candidates.sh` 呼叫 |
| `tavily_search.py` | Tavily 搜尋封裝 | 由 `search_news.sh` 呼叫 |
| `fetch_stock_data.py` | 股市資料抓取（早安新聞附加）| 由進入點腳本呼叫 |

---

## .env 變數速查

所有變數集中在 `/home/vboxuser/news-broadcast-system/.env`。

### API 金鑰（必填）

| 變數 | 用途 |
|---|---|
| `BRAVE_API_KEY` | Brave 搜尋 API |
| `TAVILY_API_KEY` | Tavily 搜尋 API |
| `DEEPSEEK_API_KEY` | DeepSeek 撰稿 + 篩選 |
| `TELEGRAM_BOT_TOKEN` | 傳送新聞的 bot（OpenClaw bot）|
| `TELEGRAM_CHAT_ID` | 接收新聞的聊天室 ID |
| `AZURE_SPEECH_KEY` | Azure TTS（目前備用，主要用 edge-tts）|
| `AZURE_SPEECH_REGION` | Azure 語音服務區域（例：`eastasia`）|

### 搜尋設定

| 變數 | 說明 | 預設 |
|---|---|---|
| `MORNING_SEARCH_ENGINE` | `brave` 或 `tavily` | `brave` |
| `EVENING_SEARCH_ENGINE` | `brave` 或 `tavily` | `brave` |
| `FEATURE_SEARCH_ENGINE` | `brave` 或 `tavily` | `tavily` |
| `MORNING_TAVILY_DAYS_BACK` | Tavily 時效（天）| `2` |
| `EVENING_TAVILY_DAYS_BACK` | Tavily 時效（天）| `2` |
| `NEWS_MAX_AGE_DAYS` | 搜尋結果最大天數 | `3` |
| `HISTORY_LOOKBACK_DAYS` | 去重回溯天數 | `3` |

### 節目參數（以 MORNING 為例，EVENING / FEATURE 同規則）

| 變數 | 說明 | morning | evening | feature |
|---|---|---|---|---|
| `*_NEWS_COUNT` | 搜尋目標篇數 | `8` | `8` | `4` |
| `*_CANDIDATE_COUNT` | 送給 DeepSeek 的候選數 | `12` | `15` | `12` |
| `*_SCRIPT_TARGET_CHARS` | 播報稿目標字數 | `2000` | `2200` | `3500` |
| `*_TTS_VOICE` | edge-tts 聲線 | `zh-TW-HsiaoChenNeural` | `zh-TW-YunJheNeural` | `zh-TW-HsiaoYuNeural` |
| `*_RUNS_KEEP` | 保留的歷史 run 數量 | `7` | `7` | `5` |

### 其他

| 變數 | 說明 |
|---|---|
| `FEATURE_SOURCE_QUALITY_ENABLED` | 新聞專題來源品質門檻（`1`=啟用）|
| `HISTORY_MAX_ITEMS` | history.json 保留上限 | 
| `NBLM_BOT_TOKEN` | nblm-audio 的 Telegram bot token（不是新聞 bot）|

---

## TTS 多音字三層架構

`normalize_tts_text.py` 依序套用三層規則：

```
Layer 0：tts_user_corrections.json（用戶自訂，最優先）
    ↓
Layer 1：WORD_OVERRIDES（程式碼內建詞組字典）
    ↓
Layer 2：jieba + pypinyin（自動判斷剩餘多音字）
```

### Layer 0 — 用戶自訂詞典

檔案：`common/config/tts_user_corrections.json`

格式：
```json
[
  {
    "from": "長照",
    "to": "常照",
    "description": "確保發音為 cháng zhào",
    "added_by": "主人",
    "added_date": "2026-03-09"
  }
]
```

管理方式（Telegram 指令）：
- `/ttsfix 原詞 替換詞` — 新增或更新規則
- `/ttslist` — 列出所有規則
- `/ttsrm 原詞` — 刪除規則

也可以直接編輯 JSON 檔案，格式需符合上述結構。

### Layer 1 — 程式碼內建詞組字典

在 `normalize_tts_text.py` 的 `WORD_OVERRIDES` list 中定義。
涵蓋高頻多音字：重（ㄔㄨㄥˊ / ㄓㄨㄥˋ）、行（ㄏㄤˊ / ㄒㄧㄥˊ）、長（ㄓㄤˇ / ㄔㄤˊ）等。
新增規則需修改此 list，替換字與原字須**同音但無歧義**。

### Layer 2 — pypinyin 自動判斷

對 Layer 0 / 1 未處理的字，用 jieba 斷詞 + pypinyin 判斷讀音。
覆蓋率較低，遇到新的錯讀應優先補入 Layer 0 或 Layer 1。

---

## 常見維護操作

### 新增 TTS 發音修正

```bash
# 方法一：Telegram 指令（推薦）
# 在 Telegram 傳送：/ttsfix 重塑 蟲素

# 方法二：直接編輯 JSON
# 編輯 common/config/tts_user_corrections.json，補一筆記錄
```

### 手動觸發一次播報

```bash
# 早安新聞
bash /home/vboxuser/news-broadcast-system/morning-news/run_morning_news.sh

# 晚安新聞
bash /home/vboxuser/news-broadcast-system/evening-news/run_evening_news.sh

# 新聞專題（需帶主題）
FEATURE_TOPIC="台灣AI教育發展" \
bash /home/vboxuser/news-broadcast-system/common/scripts/run_feature_news.sh
```

### 查看 log

```bash
# 早安新聞最新 log
tail -100 /home/vboxuser/news-broadcast-system/morning-news/logs/morning-news.log

# 即時追蹤
tail -f /home/vboxuser/news-broadcast-system/morning-news/logs/morning-news.log
```

---

## 失敗排查

每個步驟都會輸出 `step=<名稱> start / done / failed`，從 log 可以定位失敗點。

### `step=search_news` 失敗

```
常見原因：API 金鑰失效、搜尋結果為空
確認方式：
  grep "step=search_news" <log>
  curl -s "https://api.search.brave.com/..."  # 測試 Brave
  python3 common/scripts/tavily_search.py "測試" # 測試 Tavily
```

### `step=select_candidates` 失敗

```
常見原因：
  - DEEPSEEK_API_KEY 失效
  - 搜尋結果全被歷史去重過濾（material_insufficient）
確認方式：
  grep "step=select_candidates" <log>
  # 若看到 material_insufficient，代表今日新聞全是近日已播過的內容
  # 短期解法：增加 NEWS_MAX_AGE_DAYS 或 HISTORY_LOOKBACK_DAYS
```

### `step=tts` 失敗

```
常見原因：edge-tts 網路問題、script.txt 為空
確認方式：
  cat morning-news/output/script.txt       # 確認有內容
  python3 -m edge_tts --voice zh-TW-HsiaoChenNeural \
    --text "測試" --write-media /tmp/test.mp3
```

### `step=mix_audio` 失敗

```
常見原因：BGM 檔案不存在、ffmpeg 未安裝
確認方式：
  ls common/assets/bgm/
  ffmpeg -version
```

### 整個 pipeline 中途卡住（無 log 輸出）

```
確認方式：
  # 檢查是否有 lock file 殘留
  ls /tmp/news_broadcast_*.lock
  # 若存在且無對應 process，直接刪除
  rm /tmp/news_broadcast_morning.lock
```
