#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] write_script.sh 必須用 source 載入，不能直接執行"
  exit 1
fi

write_script() {
  log INFO "step=write_script start"

  if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
    die "DEEPSEEK_API_KEY is empty"
  fi

  if [[ -z "${DEEPSEEK_API_URL:-}" ]]; then
    die "DEEPSEEK_API_URL is empty"
  fi

  if [[ ! -f "$CANDIDATES_FILE" ]]; then
    die "candidates file not found: $CANDIDATES_FILE"
  fi

  if [[ ! -s "$CANDIDATES_FILE" ]]; then
    die "candidates file is empty: $CANDIDATES_FILE"
  fi

  mkdir -p "$OUTPUT_DIR" "$COMMON_TMP_DIR"

  local request_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_write_script_request.json"
  local response_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_write_script_response.json"
  local style_name=""
  local taiwan_count=""
  local world_count=""
  local script_tone=""

  case "$PROGRAM_NAME" in
    morning-news)
      style_name="${MORNING_STYLE_NAME:-主播}"
      taiwan_count="${MORNING_TAIWAN_NEWS_COUNT:-5}"
      world_count="${MORNING_WORLD_NEWS_COUNT:-3}"
      script_tone="${MORNING_SCRIPT_TONE:-podcast聊天風、清楚、自然、適合口語播報}"
      ;;
    evening-news)
      style_name="${EVENING_STYLE_NAME:-晚安主播}"
      taiwan_count="${EVENING_TAIWAN_NEWS_COUNT:-4}"
      world_count="${EVENING_WORLD_NEWS_COUNT:-4}"
      script_tone="${EVENING_SCRIPT_TONE:-沉穩、清楚、自然、適合晚間新聞播報}"
      ;;
    feature-news)
      style_name="${FEATURE_STYLE_NAME:-深度專題主持}"
      taiwan_count="${FEATURE_TAIWAN_NEWS_COUNT:-2}"
      world_count="${FEATURE_WORLD_NEWS_COUNT:-2}"
      script_tone="${FEATURE_SCRIPT_TONE:-分析型、脈絡清楚、節奏穩定}"
      ;;
    *)
      style_name="主播"
      taiwan_count="$NEWS_COUNT"
      world_count="0"
      script_tone="清楚、自然、適合口語播報"
      ;;
  esac

  python3 - <<'PY' "$CANDIDATES_FILE" "$request_file" "$DEEPSEEK_MODEL" "$NEWS_COUNT" "$SCRIPT_TARGET_CHARS" "$PROGRAM_NAME" "$style_name" "$taiwan_count" "$world_count" "$script_tone" "${FEATURE_TOPIC:-}"
import json
import sys
from pathlib import Path

candidates_file = Path(sys.argv[1])
request_file = Path(sys.argv[2])
model_name = sys.argv[3]
news_count = int(sys.argv[4])
script_target_chars = int(sys.argv[5])
program_name = sys.argv[6]
style_name = sys.argv[7]
taiwan_count = int(sys.argv[8])
world_count = int(sys.argv[9])
script_tone = sys.argv[10]
feature_topic = (sys.argv[11] or "").strip()

candidates_data = json.loads(candidates_file.read_text(encoding="utf-8"))
candidates = candidates_data.get("candidates", [])

topic_rule = ""
if program_name == "feature-news" and feature_topic:
    topic_rule = f"""
13. 所有被選入 selected 和 script 的材料，都必須與主題直接相關：{feature_topic}
14. 若候選材料與主題關聯性不足，請主動剔除，不要勉強填充。
15. script 的主軸與開場，必須明確聚焦在 {feature_topic}。
"""

selection_priority = {
    "morning-news": "優先選擇重要、清楚、有公共性、和台灣聽眾相關的早安新聞。",
    "evening-news": "優先選擇當日重大事件、有總結性、和台灣聽眾相關的晚間新聞。",
    "feature-news": "優先選擇與專題主題直接相關、有分析深度、能形成完整論述的材料。",
}.get(program_name, "優先選擇重要、清楚、有公共性、和台灣聽眾相關的內容。")

system_prompt = f"""你是台灣繁體中文 Podcast 新聞編輯與口播稿撰稿人。
你要為 {program_name} 撰寫一篇可直接拿去 TTS 朗讀的新聞播報稿。

請遵守以下規則：
1. 使用自然、流暢、標準的繁體中文。
2. 語氣風格：{script_tone}
3. 主持角色名稱為：{style_name}
4. 先從候選新聞中選出最終 {news_count} 則。
5. 其中台灣新聞約 {taiwan_count} 則，國際新聞約 {world_count} 則。
6. 避免重複主題，特別是同一國際事件不要選太多相近角度。
7. {selection_priority}
8. 盡量避免把評論、投書、過度獵奇、過於八卦的內容列入最終稿。
9. 播報稿長度目標約 {script_target_chars} 字。
10. 播報稿要有開場、各則新聞之間自然轉場、結尾。
11. 不要使用條列式，不要寫成新聞稿腔，要像主持人在自然播報。
12. 數字一律以中文書寫。年份讀成逐字（如 2026 -> 二零二六年），數量讀成口語（如 300億 -> 三百億，3.5% -> 百分之三點五）。
13. 英文縮寫若有公認中文名稱，一律使用中文名（如 NVIDIA -> 輝達、Google -> 谷歌、Microsoft -> 微軟、Apple -> 蘋果）。
14. 英文縮寫若可展開翻譯，則翻譯（如 GDP -> 國內生產毛額、AI -> 人工智慧）。
15. 品牌名若無固定中文名（如 OpenAI），首次出現時以描述性中文帶出（如「美國人工智慧新創公司」），後續以「該公司」或「該平台」代稱，避免重複出現英文。
16. 播報稿最終不得包含任何英文字母或阿拉伯數字。
17. 只輸出 JSON，不要有任何額外說明文字。{topic_rule}

輸出 JSON 格式如下：
{{
  "selected": [
    {{
      "rank": 1,
      "title": "新聞標題",
      "source": "媒體名稱",
      "url": "https://example.com",
      "category": "politics/economy/society/world/sports/other",
      "region": "taiwan/world",
      "reason": "為什麼最後入選"
    }}
  ],
  "script": "完整播報稿全文"
}}
"""

user_payload = {
    "task": "final_select_and_write_script",
    "program_name": program_name,
    "news_count": news_count,
    "target_chars": script_target_chars,
    "style_name": style_name,
    "tone": script_tone,
    "feature_topic": feature_topic,
    "selection_rules": {
        "taiwan_news_count": taiwan_count,
        "world_news_count": world_count,
        "avoid_duplicate_topics": True,
        "avoid_opinion_heavy_content": True
    },
    "candidates": candidates
}

payload = {
    "model": model_name,
    "temperature": 0.5,
    "messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": json.dumps(user_payload, ensure_ascii=False)}
    ]
}

request_file.write_text(
    json.dumps(payload, ensure_ascii=False, indent=2),
    encoding="utf-8"
)
PY

  local http_code
  http_code="$(curl -sS \
    -o "$response_file" \
    -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
    --max-time "${DEEPSEEK_WRITE_TIMEOUT:-180}" \
    -d @"$request_file" \
    "$DEEPSEEK_API_URL")"

  if [[ "$http_code" != "200" ]]; then
    log ERROR "step=write_script failed http_code=$http_code"
    if [[ -f "$response_file" ]]; then
      log ERROR "step=write_script response=$(tr '\n' ' ' < "$response_file" | head -c 1000)"
    fi
    die "deepseek write_script failed"
  fi

  python3 - <<'PY' "$response_file" "$SELECTED_FILE" "$SCRIPT_FILE"
import json
import re
import sys
from pathlib import Path

response_file = Path(sys.argv[1])
selected_file = Path(sys.argv[2])
script_file = Path(sys.argv[3])

data = json.loads(response_file.read_text(encoding="utf-8"))
content = data["choices"][0]["message"]["content"].strip()

match = re.search(r"```json\s*(\{.*\})\s*```", content, re.S)
if match:
    content = match.group(1)
else:
    match = re.search(r"(\{.*\})", content, re.S)
    if match:
        content = match.group(1)

parsed = json.loads(content)

selected_payload = {
    "selected": parsed.get("selected", [])
}

script_text = (parsed.get("script") or "").strip()

selected_file.write_text(
    json.dumps(selected_payload, ensure_ascii=False, indent=2),
    encoding="utf-8"
)

script_file.write_text(script_text + "\n", encoding="utf-8")
PY

  if [[ ! -f "$SELECTED_FILE" || ! -s "$SELECTED_FILE" ]]; then
    die "selected file not generated: $SELECTED_FILE"
  fi

  if [[ ! -f "$SCRIPT_FILE" || ! -s "$SCRIPT_FILE" ]]; then
    die "script file not generated: $SCRIPT_FILE"
  fi

  local selected_size
  local script_size
  selected_size=$(stat -c%s "$SELECTED_FILE" 2>/dev/null || echo 0)
  script_size=$(stat -c%s "$SCRIPT_FILE" 2>/dev/null || echo 0)

  log INFO "step=write_script done selected_file=$SELECTED_FILE selected_size_bytes=$selected_size script_file=$SCRIPT_FILE script_size_bytes=$script_size"
}
