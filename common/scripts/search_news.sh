#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] search_news.sh must be sourced, not executed directly"
  exit 1
fi

urlencode() {
  python3 - <<'PY' "$1"
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
}

detect_feature_scope_and_profile() {
  local topic="$1"
  python3 - <<'PY' "$topic" "${FEATURE_SCOPE:-}"
import sys

topic = (sys.argv[1] or "").strip().lower()
manual_scope = (sys.argv[2] or "").strip().lower()

local_tokens = [
    "\u53f0\u7063", "\u65b0\u5317", "\u53f0\u5317", "\u53f0\u4e2d", "\u9ad8\u96c4", "\u6843\u5712",
    "\u5065\u4fdd", "\u9577\u7167", "\u623f\u5e02", "\u7f3a\u5de5",
]
global_tokens = [
    "gtc", "nvidia", "\u5ddd\u666e", "trump", "\u95dc\u7a05", "\u51fa\u53e3", "\u4f9b\u61c9\u93c8",
    "wbc", "\u68d2\u7403\u7d93\u5178\u8cfd", "\u4e16\u754c\u68d2\u7403\u7d93\u5178\u8cfd",
]
profiles = [
    ("sports_wbc", ["wbc", "\u68d2\u7403\u7d93\u5178\u8cfd", "\u4e16\u754c\u68d2\u7403\u7d93\u5178\u8cfd", "\u4e2d\u83ef\u968a", "\u53f0\u7063\u968a"]),
    ("tech_gtc", ["gtc", "nvidia", "\u8f1d\u9054", "\u6676\u7247", "\u534a\u5c0e\u9ad4", "\u4f9b\u61c9\u93c8"]),
    ("trade_tariff", ["trump", "\u5ddd\u666e", "\u95dc\u7a05", "\u51fa\u53e3", "\u8cbf\u6613", "tariff", "export", "trade"]),
]

if manual_scope:
    scope = manual_scope
elif any(token in topic for token in global_tokens):
    scope = "global"
elif any(token in topic for token in local_tokens):
    scope = "local"
else:
    scope = "local"

profile = "generic"
for name, tokens in profiles:
    if any(token in topic for token in tokens):
        profile = name
        break

print(f"{scope}:{profile}")
PY
}

get_feature_search_queries() {
  local topic="$1"
  local scope="$2"
  local profile="$3"

  if [[ "$scope" == "global" ]]; then
    case "$profile" in
      sports_wbc)
        cat <<EOF
${topic}
${topic} roster analysis
${topic} schedule knockout analysis
${topic} tournament preview
taiwan baseball WBC 2026 latest news
taiwan WBC 2026 game result highlights
EOF
        ;;
      tech_gtc)
        cat <<EOF
${topic}
${topic} keynote announcements
${topic} taiwan supply chain analysis
${topic} semiconductor supply chain analysis
taiwan semiconductor nvidia AI supply chain news
nvidia GTC taiwan chip export latest
EOF
        ;;
      trade_tariff)
        cat <<EOF
${topic}
${topic} tariff export taiwan analysis
${topic} trade policy impact taiwan
${topic} global tariff policy analysis
taiwan export tariff US trade policy latest news
trump tariff taiwan semiconductor impact economy
EOF
        ;;
      *)
        cat <<EOF
${topic}
${topic} analysis
${topic} latest developments
${topic} policy impact
taiwan ${topic} news latest
${topic} impact economy latest
EOF
        ;;
    esac
    return
  fi

  case "$profile" in
    trade_tariff)
      cat <<EOF
${topic}
${topic} 台灣 貿易 出口
${topic} 政策 影響
${topic} 產業 分析
EOF
      ;;
    tech_gtc)
      cat <<EOF
${topic}
${topic} 台積電 供應鏈
${topic} AI 伺服器
${topic} 產業 分析
EOF
      ;;
    *)
      cat <<EOF
${topic}
${topic} 最新
${topic} 分析
${topic} 影響
EOF
      ;;
  esac
}

get_search_queries() {
  case "$PROGRAM_NAME" in
    morning-news)
      cat <<EOF
Taiwan news today
Taiwan politics latest
Taiwan society latest news
US stock market Wall Street overnight closing
S&P 500 Nasdaq Dow Jones results
中華職棒 昨日賽事比分結果
CPBL 2026 baseball game results scores
Asia Pacific news today
international breaking news today
EOF
      ;;
    evening-news)
      cat <<EOF
Taiwan news today
台股 加權指數 收盤
台積電 最新消息
Taiwan government politics latest
Taiwan business technology news
MLB Dodgers Ohtani 大谷翔平 道奇 比分
MLB scores highlights results today 2026
Asia breaking news today
world news today
EOF
      ;;
    feature-news)
      local topic="${FEATURE_TOPIC:-}"
      topic="$(echo "$topic" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
      if [[ -n "$topic" ]]; then
        get_feature_search_queries "$topic" "${FEATURE_SCOPE_DETECTED:-local}" "${FEATURE_PROFILE_DETECTED:-generic}"
      else
        cat <<'EOF'
專題新聞 深度分析 最新
台灣 專題報導 最新
國際 專題新聞 中文
investigative journalism latest
longform news analysis
EOF
      fi
      ;;
    *)
      die "unsupported PROGRAM_NAME: $PROGRAM_NAME"
      ;;
  esac
}

build_brave_url() {
  local encoded_q="$1"
  local count="$2"
  local scope="${FEATURE_SCOPE_DETECTED:-}"
  local country="${BRAVE_SEARCH_COUNTRY:-TW}"
  local search_lang="${BRAVE_SEARCH_LANG:-zh-hant}"

  if [[ "$PROGRAM_NAME" == "feature-news" && "$scope" == "global" ]]; then
    country="${FEATURE_BRAVE_SEARCH_COUNTRY_GLOBAL:-US}"
    search_lang="${FEATURE_BRAVE_SEARCH_LANG_GLOBAL:-en}"
  fi

  printf '%s?q=%s&count=%s&country=%s&search_lang=%s&freshness=%s' \
    "$BRAVE_SEARCH_ENDPOINT" \
    "$encoded_q" \
    "$count" \
    "$country" \
    "$search_lang" \
    "${BRAVE_SEARCH_FRESHNESS:-pd}"
}

_search_news_tavily() {
  log INFO "step=search_news engine=tavily"

  local queries_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_tavily_queries.txt"
  local raw_file="$OUTPUT_DIR/raw_search_results.json"
  local _tavily_days_back=""
  local _days_arg=()

  case "$PROGRAM_NAME" in
    morning-news)
      _tavily_days_back="${MORNING_TAVILY_DAYS_BACK:-2}"
      ;;
    evening-news)
      _tavily_days_back="${EVENING_TAVILY_DAYS_BACK:-2}"
      ;;
    feature-news)
      _tavily_days_back=""
      ;;
    *)
      _tavily_days_back=""
      ;;
  esac

  if [[ -n "$_tavily_days_back" ]]; then
    _days_arg=(--days-back "$_tavily_days_back")
  fi

  get_search_queries > "$queries_file"

  local query_count
  query_count=$(wc -l < "$queries_file")
  log INFO "step=search_news tavily query_count=$query_count days_back=${_tavily_days_back:-none}"

  python3 "$BASE_DIR/common/scripts/tavily_search.py" \
    --queries-file "$queries_file" \
    --output "$raw_file" \
    --api-key "$TAVILY_API_KEY" \
    --program-name "$PROGRAM_NAME" \
    --feature-scope "${FEATURE_SCOPE_DETECTED:-}" \
    --feature-profile "${FEATURE_PROFILE_DETECTED:-}" \
    --max-results "${TAVILY_MAX_RESULTS:-10}" \
    --search-depth "${TAVILY_SEARCH_DEPTH:-basic}" \
    "${_days_arg[@]}" \
    2>&1 | while IFS= read -r line; do log INFO "$line"; done

  if [[ ! -f "$raw_file" || ! -s "$raw_file" ]]; then
    die "step=search_news tavily: raw search file not generated"
  fi

  RAW_SEARCH_FILE="$raw_file"

  local result_size
  result_size=$(stat -c%s "$raw_file" 2>/dev/null || echo 0)
  log INFO "step=search_news done engine=tavily raw_file=$raw_file size_bytes=$result_size"
}

search_news() {
  log INFO "step=search_news start"

  mkdir -p "$OUTPUT_DIR" "$COMMON_TMP_DIR"

  if [[ "$PROGRAM_NAME" == "feature-news" ]]; then
    local _scope_profile
    _scope_profile="$(detect_feature_scope_and_profile "${FEATURE_TOPIC:-}")"
    FEATURE_SCOPE_DETECTED="${_scope_profile%%:*}"
    FEATURE_PROFILE_DETECTED="${_scope_profile##*:}"
    export FEATURE_SCOPE_DETECTED FEATURE_PROFILE_DETECTED
    log INFO "step=search_news feature_scope=$FEATURE_SCOPE_DETECTED feature_profile=$FEATURE_PROFILE_DETECTED topic=${FEATURE_TOPIC:-N/A}"
  else
    FEATURE_SCOPE_DETECTED=""
    FEATURE_PROFILE_DETECTED=""
  fi

  local selected_engine=""
  case "$PROGRAM_NAME" in
    morning-news)
      selected_engine="${MORNING_SEARCH_ENGINE:-brave}"
      ;;
    evening-news)
      selected_engine="${EVENING_SEARCH_ENGINE:-brave}"
      ;;
    feature-news)
      selected_engine="${FEATURE_SEARCH_ENGINE:-tavily}"
      ;;
    *)
      selected_engine="brave"
      ;;
  esac

  selected_engine="$(echo "$selected_engine" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  if [[ "$selected_engine" == "tavily" ]]; then
    if [[ -z "${TAVILY_API_KEY:-}" ]]; then
      log WARN "step=search_news engine=tavily requested but TAVILY_API_KEY is empty; fallback engine=brave"
    else
      _search_news_tavily
      return
    fi
  fi

  if [[ -z "${BRAVE_API_KEY:-}" ]]; then
    die "BRAVE_API_KEY is empty"
  fi

  if [[ -z "${BRAVE_SEARCH_ENDPOINT:-}" ]]; then
    die "BRAVE_SEARCH_ENDPOINT is empty"
  fi

  RAW_SEARCH_FILE="$OUTPUT_DIR/raw_search_results.json"
  TMP_JSONL="$COMMON_TMP_DIR/${PROGRAM_NAME}_search_results.jsonl"

  : > "$TMP_JSONL"

  local query
  local idx=0
  local _brave_failed=0
  local _brave_fail_count=0

  while IFS= read -r query; do
    [[ -z "$query" ]] && continue
    idx=$((idx + 1))

    log INFO "step=search_news query_$idx start q=$query scope=${FEATURE_SCOPE_DETECTED:-n/a}"

    local encoded_q
    encoded_q="$(urlencode "$query")"

    local brave_count="${BRAVE_SEARCH_COUNT:-15}"
    if ! [[ "$brave_count" =~ ^[0-9]+$ ]]; then
      brave_count=15
    fi
    if (( brave_count < 15 )); then
      brave_count=15
    fi

    local url
    local response_file
    local http_code
    url="$(build_brave_url "$encoded_q" "$brave_count")"
    response_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_query_${idx}.json"

    http_code="$(curl -sS \
      -H "Accept: application/json" \
      -H "X-Subscription-Token: $BRAVE_API_KEY" \
      --max-time "${BRAVE_SEARCH_TIMEOUT:-30}" \
      --connect-timeout 10 \
      -o "$response_file" \
      -w "%{http_code}" \
      "$url" || true)"

    if ! [[ "$http_code" =~ ^[0-9]{3}$ ]]; then
      http_code="000"
    fi

    if [[ "$http_code" != "200" ]]; then
      log WARN "step=search_news query_$idx failed http_code=$http_code (skipping)"
      _brave_fail_count=$((_brave_fail_count + 1))
      if [[ $_brave_fail_count -ge 3 ]]; then
        log WARN "step=search_news brave failed ${_brave_fail_count} queries, fallback to tavily"
        _brave_failed=1
        break
      fi
      continue
    fi

    python3 - <<'PY' "$response_file" "$query" "$idx" >> "$TMP_JSONL"
import json
import sys
from pathlib import Path

response_path = Path(sys.argv[1])
query = sys.argv[2]
idx = int(sys.argv[3])

data = json.loads(response_path.read_text(encoding="utf-8"))
record = {
    "query_index": idx,
    "query": query,
    "response": data,
}
print(json.dumps(record, ensure_ascii=False))
PY

    log INFO "step=search_news query_$idx done"
  done < <(get_search_queries)

  if [[ "$_brave_failed" -eq 1 ]]; then
    if [[ -n "${TAVILY_API_KEY:-}" ]]; then
      log WARN "step=search_news brave failed, fallback to tavily"
      _search_news_tavily
      return
    else
      die "brave search failed and TAVILY_API_KEY is empty (no fallback)"
    fi
  fi

  python3 - <<'PY' "$TMP_JSONL" "$RAW_SEARCH_FILE" "$PROGRAM_NAME" "${FEATURE_SCOPE_DETECTED:-}" "${FEATURE_PROFILE_DETECTED:-}"
import json
import sys
from datetime import datetime
from pathlib import Path

jsonl_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
program_name = sys.argv[3]
feature_scope = sys.argv[4]
feature_profile = sys.argv[5]

records = []
for line in jsonl_path.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line:
        continue
    records.append(json.loads(line))

payload = {
    "program_name": program_name,
    "generated_at": datetime.now().astimezone().isoformat(),
    "query_count": len(records),
    "feature_scope": feature_scope,
    "feature_profile": feature_profile,
    "results": records,
}

output_path.write_text(
    json.dumps(payload, ensure_ascii=False, indent=2),
    encoding="utf-8"
)
PY

  if [[ ! -f "$RAW_SEARCH_FILE" || ! -s "$RAW_SEARCH_FILE" ]]; then
    die "raw search file not generated: $RAW_SEARCH_FILE"
  fi

  local result_size
  result_size=$(stat -c%s "$RAW_SEARCH_FILE" 2>/dev/null || echo 0)

  log INFO "step=search_news done raw_file=$RAW_SEARCH_FILE size_bytes=$result_size scope=${FEATURE_SCOPE_DETECTED:-n/a}"
}
