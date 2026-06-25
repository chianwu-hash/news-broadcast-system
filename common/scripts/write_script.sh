#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] write_script.sh 必須用 source 載入，不能直接執行"
  exit 1
fi

write_script() {
  log INFO "step=write_script start"

  if [[ ! -f "$CANDIDATES_FILE" ]]; then
    die "candidates file not found: $CANDIDATES_FILE"
  fi

  if [[ ! -s "$CANDIDATES_FILE" ]]; then
    die "candidates file is empty: $CANDIDATES_FILE"
  fi

  mkdir -p "$OUTPUT_DIR" "$COMMON_TMP_DIR"

  local sys_prompt_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_write_script_sys_prompt.txt"
  local user_prompt_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_write_script_user_prompt.txt"
  local response_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_write_script_response.txt"
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

  python3 - <<'PY' "$CANDIDATES_FILE" "$sys_prompt_file" "$user_prompt_file" "$NEWS_COUNT" "$SCRIPT_TARGET_CHARS" "$PROGRAM_NAME" "$style_name" "$taiwan_count" "$world_count" "$script_tone" "${FEATURE_TOPIC:-}" "${STOCK_DATA_FILE:-}"
import json
import sys
from pathlib import Path

candidates_file = Path(sys.argv[1])
sys_prompt_file = Path(sys.argv[2])
user_prompt_file = Path(sys.argv[3])
news_count = int(sys.argv[4])
script_target_chars = int(sys.argv[5])
program_name = sys.argv[6]
style_name = sys.argv[7]
taiwan_count = int(sys.argv[8])
world_count = int(sys.argv[9])
script_tone = sys.argv[10]
feature_topic = (sys.argv[11] or "").strip()
stock_data_file = (sys.argv[12] if len(sys.argv) > 12 else "").strip()

candidates_data = json.loads(candidates_file.read_text(encoding="utf-8"))
candidates = candidates_data.get("candidates", [])

# 股市資料（晚安新聞專用）
stock_context = ""
if program_name == "evening-news" and stock_data_file:
    from pathlib import Path as _Path
    _sf = _Path(stock_data_file)
    if _sf.exists():
        try:
            stock = json.loads(_sf.read_text(encoding="utf-8"))
            if stock.get("market_open"):
                twii = stock["twii"]
                tsmc = stock["tsmc"]
                volatile_note = ""
                if stock.get("is_volatile"):
                    volatile_note = f"（大盤漲跌幅達 {abs(twii['change_pct']):.2f}%，屬劇烈震盪，請在播報後加一段簡短市場分析，約五十到八十字）"
                stock_context = f"""
18. 今日股市資料（必須納入播報，置於各則新聞之後）：
    - 台股加權指數：{twii['index']:,.2f} 點，{twii['direction']} {abs(twii['change']):.2f} 點（{twii['change_pct']:+.2f}%）{volatile_note}
    - 台積電（二三三零）：收盤價 {tsmc['price']:,.0f} 元，{tsmc['direction']} {abs(tsmc['change']):.0f} 元（{tsmc['change_pct']:+.2f}%）
    - 股市數字同樣以中文口語化書寫（如 33400 點 -> 三萬三千四百點）"""
        except Exception:
            pass

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

from datetime import datetime, timezone, timedelta
_now_tw = datetime.now(timezone.utc) + timedelta(hours=8)
_date_str = f"{_now_tw.month}月{_now_tw.day}日"
if program_name == "morning-news":
    opening_sentence = f"歡迎收聽{_date_str}早安新聞，我是主播{style_name}。"
elif program_name == "evening-news":
    opening_sentence = f"歡迎收聽{_date_str}晚安新聞，我是主播{style_name}。"
elif program_name == "feature-news":
    _topic_display = feature_topic if feature_topic else "新聞專題"
    opening_sentence = f"歡迎收聽{_topic_display}專題新聞，我是主播{style_name}。"
else:
    opening_sentence = ""

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
8. 財經股市新聞（category = economy）：{"早安新聞報美股（NYSE 凌晨收盤結果）、華爾街動態、國際財經。台股留給晚安新聞，早安不報台股。" if program_name == "morning-news" else "晚安新聞報台股收盤、台積電、台灣財經。美股留給早安新聞，晚安不報美股。" if program_name == "evening-news" else "如有財經新聞可適量選入。"}必須選入至少1則財經新聞。
9. 體育新聞（category = sports）：{"早安新聞報 CPBL 中華職棒（昨晚台灣賽事結果），如有 CPBL 新聞必須選入至少2則。早安不報 MLB，MLB 留給晚安新聞。" if program_name == "morning-news" else "晚安新聞報 MLB 美國職棒（美國昨晚賽事結果），特別關注道奇隊與大谷翔平，如有 MLB 新聞必須選入至少1則。晚安不報 CPBL，CPBL 留給早安新聞。" if program_name == "evening-news" else "如有體育新聞可適量選入。"}所有體育新聞必須是近期（3天內）的比賽結果、球員動態，不接受舊聞或花絮。
10. 盡量避免把評論、投書、過度獵奇、過於八卦的內容列入最終稿。同一家公司或同一個主題最多選 2 則，避免過度集中。
11. 播報稿長度目標約 {script_target_chars} 字。
12. 播報稿開頭第一句必須固定為：「{opening_sentence}」，之後各則新聞自然轉場，最後有結尾。
13. 不要使用條列式，不要寫成新聞稿腔，要像主持人在自然播報。
14. 只報導事實，不添加主觀評論。每則新聞只需陳述發生了什麼事，不需要說「值得關注」、「引發討論」、「令人擔憂」、「可以追蹤」、「值得留意」這類帶有判斷的用語。不要使用「有分析指出」、「專家表示」、「市場解讀為」這類空洞來源。
15. 每則新聞必須包含具體事實：人名、數字、金額、比分、時間、地點，不能只寫模糊的概況。**但你只能使用候選素材中明確提供的數據，嚴禁自行編造任何數字、比分、金額、指數點位或統計數據。** 如果素材中沒有提供具體數字，就用定性描述帶過（例如「台股開盤走高」而非編造點位；「該隊取得勝利」而非編造比分）。捏造數據是最嚴重的錯誤，寧可模糊也不可編造。
16. 數字一律以中文書寫。年份讀成逐字（如 2026 -> 二零二六年），數量讀成口語（如 300億 -> 三百億，3.5% -> 百分之三點五）。
17. 英文縮寫若有公認中文名稱，一律使用中文名（如 NVIDIA -> 輝達、Google -> 谷歌、Microsoft -> 微軟、Apple -> 蘋果）。
18. 英文縮寫若可展開翻譯，則翻譯（如 GDP -> 國內生產毛額、AI -> 人工智慧）。
19. 品牌名若無固定中文名（如 OpenAI），首次出現時以描述性中文帶出（如「美國人工智慧新創公司」），後續以「該公司」或「該平台」代稱，避免重複出現英文。
20. 播報稿最終不得包含任何英文字母或阿拉伯數字。
21. 在提及政治人物時，必須使用正確的現任頭銜。例如川普是現任美國總統，不得稱為「前總統」；賴清德是現任台灣總統（或稱台灣總統），不得稱為「副總統」。
22. 只輸出 JSON，不要有任何額外說明文字。{topic_rule}{stock_context}

輸出 JSON 格式如下：
{{
  "selected": [
    {{
      "rank": 1,
      "title": "原文新聞標題",
      "title_zh": "繁體中文新聞標題（若原標題已是中文則照填，英文則翻譯）",
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

sys_prompt_file.write_text(system_prompt, encoding="utf-8")
user_prompt_file.write_text(json.dumps(user_payload, ensure_ascii=False, indent=2), encoding="utf-8")
PY

  local codex_model="${CODEX_WRITE_MODEL:-gpt-5.5}"
  local codex_timeout="${CODEX_WRITE_TIMEOUT:-180}"
  local combined_prompt_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_write_script_combined.txt"

  {
    printf '你的整個回覆必須是一個合法的 JSON 物件，以 { 開始，以 } 結束。不得有任何說明、分析或 markdown。\n\n'
    printf '<INSTRUCTIONS>\n'
    cat "$sys_prompt_file"
    printf '\n</INSTRUCTIONS>\n\n<DATA>\n'
    cat "$user_prompt_file"
    printf '\n</DATA>\n\n'
    printf '只輸出 JSON，不要任何其他文字。\n'
  } > "$combined_prompt_file"

  log INFO "step=write_script calling codex model=$codex_model"

  local _codex_bin="${CODEX_BIN:-}"
  if [[ -z "$_codex_bin" ]]; then
    _codex_bin="$(command -v codex 2>/dev/null || echo "")"
  fi
  if [[ -z "$_codex_bin" && -x "$HOME/.npm-global/bin/codex" ]]; then
    _codex_bin="$HOME/.npm-global/bin/codex"
  fi
  if [[ -z "$_codex_bin" ]]; then
    die "codex CLI not found (set CODEX_BIN in .env or install: npm i -g @openai/codex)"
  fi

  local codex_exit=0
  local codex_stderr_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_write_script_codex_stderr.txt"
  timeout "$codex_timeout" "$_codex_bin" exec \
      --model "$codex_model" \
      -o "$response_file" \
      - < "$combined_prompt_file" \
      > /dev/null 2>"$codex_stderr_file" || codex_exit=$?

  if [[ $codex_exit -ne 0 ]]; then
    local _stderr_head
    _stderr_head="$(head -c 500 "$codex_stderr_file" 2>/dev/null | tr '\n' ' ')"
    log ERROR "step=write_script failed codex exit_code=$codex_exit timeout=${codex_timeout}s stderr=$_stderr_head"
    die "codex write_script failed"
  fi

  if [[ ! -s "$response_file" ]]; then
    log ERROR "step=write_script codex returned empty response"
    die "codex write_script empty response"
  fi

  python3 - <<'PY' "$response_file" "$SELECTED_FILE" "$SCRIPT_FILE"
import json
import re
import sys
from pathlib import Path

response_file = Path(sys.argv[1])
selected_file = Path(sys.argv[2])
script_file = Path(sys.argv[3])

content = response_file.read_text(encoding="utf-8").strip()

match = re.search(r"```json\s*(\{.*\})\s*```", content, re.S)
if match:
    content = match.group(1)

def try_parse_json(txt: str) -> dict | None:
    # 嘗試標準解析
    try:
        return json.loads(txt)
    except json.JSONDecodeError:
        pass
    # 嘗試補上缺少的閉合大括號
    opens = txt.count("{")
    closes = txt.count("}")
    if opens > closes:
        txt_fixed = txt + "\n" * (opens - closes) + "}" * (opens - closes)
        try:
            return json.loads(txt_fixed)
        except json.JSONDecodeError:
            pass
    # 嘗試補上缺少的閉合引號和括號：整段 content 結尾可能只有 " 沒有 }
    if txt.rstrip()[-1:] == '"':
        candidate = txt + "\n}"
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            pass
    # 嘗試從 content 中提取第一個 { 到最後可見的結構
    first_brace = txt.find("{")
    if first_brace >= 0:
        # 從第一個 { 開始嘗試
        remaining = txt[first_brace:]
        # 找最後一個 } 或 ] 或 " 作爲截斷點
        last_close_brace = remaining.rfind("}")
        if last_close_brace >= 0:
            candidate = remaining[:last_close_brace+1]
            try:
                return json.loads(candidate)
            except json.JSONDecodeError:
                pass
        # 結尾是 " 時補 }]
        if remaining.rstrip()[-1:] == '"':
            # 檢查結構剩下幾個層級
            opens_b = remaining.count("{")
            closes_b = remaining.count("}")
            if opens_b > closes_b:
                candidate2 = remaining + "\n}" * (opens_b - closes_b)
                try:
                    return json.loads(candidate2)
                except json.JSONDecodeError:
                    pass
    return None

parsed = try_parse_json(content)
if parsed is None:
    raise ValueError(f"cannot parse JSON from content (len={len(content)}, opens={content.count('{')}, closes={content.count('}')})")

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
  local script_chars
  selected_size=$(stat -c%s "$SELECTED_FILE" 2>/dev/null || echo 0)
  script_size=$(stat -c%s "$SCRIPT_FILE" 2>/dev/null || echo 0)
  script_chars=$(wc -m < "$SCRIPT_FILE" 2>/dev/null || echo 0)
  script_chars=$((script_chars))

  local target_chars="${SCRIPT_TARGET_CHARS:-2000}"
  local min_chars=$(( target_chars * 70 / 100 ))
  if [[ $script_chars -lt $min_chars ]]; then
    log WARN "step=write_script script_too_short chars=$script_chars target=$target_chars min_threshold=$min_chars"
  fi

  log INFO "step=write_script done model=$codex_model script_chars=$script_chars target=$target_chars selected_file=$SELECTED_FILE selected_size_bytes=$selected_size script_file=$SCRIPT_FILE script_size_bytes=$script_size"
}
