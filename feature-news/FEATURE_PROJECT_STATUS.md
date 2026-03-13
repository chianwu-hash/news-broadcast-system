# Feature News Project Status

_Last updated: 2026-03-09_

---

## 1. 定位

Feature News 目前是「主題驅動」的深度新聞流程，透過 Telegram 觸發，輸入主題後自動完成搜尋、候選挑選、品質把關與文字稿生成。

---

## 2. 目前架構

```
使用者 Telegram → run_feature_news.sh
  → search_news        (feature-news 使用 Tavily，morning/evening 使用 Brave，各 6 個 query)
  → select_candidates  (DeepSeek API 挑選 + 群集，feature-news 使用 loose dedup)
      material_count_gate → 材料不足時 Telegram 通知 + 歸檔 + 結束
  → source_quality_gate (來源品質把關)
      gate_ok=false → Telegram 通知 + 歸檔 + 結束
      gate_ok=true  → 繼續
  → write_script       (DeepSeek API 撰稿)
  → update_history
  → archive_run_artifacts
  → [FEATURE_TEXT_ONLY_MODE=1] send_telegram_text
  → [FEATURE_TEXT_ONLY_MODE=0] generate_tts + mix_audio + send_telegram_audio
```

---

## 3. 已完成功能

| 功能 | 狀態 | 備註 |
|---|---|---|
| Telegram 觸發執行 | ✅ | 透過 OpenClaw 轉發主題 |
| `FEATURE_TOPIC` 主題傳入 | ✅ | 支援中英文主題 |
| 本地/全球搜尋模式自動偵測 | ✅ | `feature_scope`: local / global |
| 搜尋 profile 自動偵測 | ✅ | trade_tariff / tech_gtc / sports_wbc / generic |
| Global scope 搜尋 query 擴充 | ✅ | 從 4 增至 6，新增純英文 query |
| 來源品質把關（source_quality_gate） | ✅ | 整合進 pipeline |
| 品質不足時 Telegram 通知 | ✅ | 含 A/B 級來源數量說明 |
| 每次執行結果歸檔（runs/） | ✅ | 保留最近 5 次 |
| 文字模式（FEATURE_TEXT_ONLY_MODE=1） | ✅ | 預設開啟 |
| write_script 主題相關規則（rules 13-15） | ✅ | 已修復主題偏移問題 |
| 多音字正規化（TTS 前處理） | ✅ | 與早晚安新聞共用 |
| 歷史記錄更新 | ✅ | 避免重複播報同一主題 |
| Tavily 取代 Brave（feature-news 專用）| ✅ | search_engine=tavily，output 含 tavily marker，已驗證 |
| NEWS_COUNT 從 1 提升至 4 | ✅ | 同步更新 FEATURE_NEWS_COUNT=4 in .env |
| CANDIDATE_COUNT 從 6 提升至 12 | ✅ | 同步更新 FEATURE_CANDIDATE_COUNT=12 in .env |
| Clustering 調鬆（feature-news 專用）| ✅ | loose dedup，保留不同角度材料 |
| 材料不足更早中止（material_count_gate）| ✅ | item_count < 4 時 Telegram 通知並歸檔 |
| 完整模式（FEATURE_TEXT_ONLY_MODE=0）| ✅ | 語音 + 混音 + Telegram 音頻，已驗證 |

---

## 4. 來源品質設定（2026-03-08 更新）

### 閾值

| 參數 | 值 | 說明 |
|---|---|---|
| `min_tier_a`（config JSON） | 0 | 不強制要求政府/機構來源（Tavily 覆蓋率仍有限）|
| `min_tier_b`（config JSON） | 1 | 至少 1 個主流媒體來源 |

### Tier A / Tier B

實際來源清單與規則由 `common/config/feature_source_quality.json` 維護，並由 `source_quality_gate.py` 執行評分與門檻判斷。

---

## 5. 搜尋 Query 策略（2026-03-08 更新）

Global scope 每個 profile 會使用 6 條查詢，其中至少 2 條為純英文 query 以提高國際來源覆蓋率。

| Profile | 代表 query |
|---|---|
| trade_tariff | `taiwan export tariff US trade policy latest news` / `trump tariff taiwan semiconductor impact economy` |
| tech_gtc | `taiwan semiconductor nvidia AI supply chain news` / `nvidia GTC taiwan chip export latest` |
| sports_wbc | `taiwan baseball WBC 2026 latest news` |
| generic | `taiwan {topic} news latest` / `{topic} impact economy latest` |

---

## 6. 已知限制

### 搜尋來源覆蓋率

Tavily（feature-news 使用）比 Brave 能更穩定地找到 Reuters、Bloomberg、NYT 等 tier_b 媒體文章，tier_b 命中數從 1 提升至 8+（以「川普關稅台灣出口」為例）。

> 注意：Tavily 免費額度 1000 credits/月，每次搜尋 6 個 query 約消耗 6 credits。

### 群集（clustering）偶發失敗

`cluster_events_ai` 偶爾 `parse_or_validation_failed`，會觸發 fallback，但整體 pipeline 可持續。

### ~~主題 slug 顯示為 adhoc~~

已修復（2026-03-09）：`archive_run_artifacts` 的 regex 改用非 raw string 處理 Unicode 範圍，中文主題現可正確顯示於歸檔目錄名稱。

---

## 7. 下一步（依優先序）

### 短期可做

1. **改善本地主題搜尋**（local generic profile 的 query 品質仍偏弱）
2. ~~**修復 topic_slug 中文解析**~~ ✅ 已完成（2026-03-09）

### 中期規劃

~~3. **完整模式（FEATURE_TEXT_ONLY_MODE=0）測試**~~ ✅ 已完成（2026-03-09）
~~4. **clustering 強度針對 feature-news 調鬆**~~ ✅ 已完成（2026-03-09）
~~5. **材料不足時的更早中止**~~ ✅ 已完成（2026-03-09）

---

## 8. 參考檔案

| 檔案 | 說明 |
|---|---|
| `common/scripts/tavily_search.py` | Tavily API 搜尋腳本（feature-news 專用，含格式轉換） |
| `feature-news/run_feature_news.sh` | 主流程腳本 |
| `common/scripts/search_news.sh` | 搜尋 query 與 API 呼叫 |
| `common/scripts/select_candidates.sh` | 候選挑選 + 群集 |
| `common/scripts/write_script.sh` | AI 撰稿（含主題相關規則） |
| `common/scripts/source_quality_gate.py` | 來源品質評分與把關 |
| `common/config/feature_source_quality.json` | Tier A/B 域名清單與閾值 |
| `feature-news/FEATURE_SOURCE_QUALITY_V1.md` | 來源品質設計文件 |
