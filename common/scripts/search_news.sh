#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] search_news.sh 必須用 source 載入，不能直接執行"
  exit 1
fi

urlencode() {
  python3 - <<'PY' "$1"
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1]))
PY
}

get_search_queries() {
  case "$PROGRAM_NAME" in
    morning-news)
      cat <<'EOF'
台灣 即時新聞
台灣 政治 最新
台灣 財經 最新
台灣 社會 新聞
國際新聞 最新 中文
international breaking news
EOF
      ;;
    evening-news)
      cat <<'EOF'
台灣 今日新聞 重點
台灣 晚間新聞 焦點
台灣 財經 收盤 新聞
台灣 社會 今日事件
國際新聞 今日重點 中文
world news today
EOF
      ;;
    feature-news)
      cat <<'EOF'
台灣 深度報導 最新
台灣 專題報導 新聞
國際 專題新聞 中文
investigative journalism latest
longform news analysis
EOF
      ;;
    *)
      die "unsupported PROGRAM_NAME: $PROGRAM_NAME"
      ;;
  esac
}

search_news() {
  log INFO "step=search_news start"

  if [[ -z "${BRAVE_API_KEY:-}" ]]; then
    die "BRAVE_API_KEY is empty"
  fi

  if [[ -z "${BRAVE_SEARCH_ENDPOINT:-}" ]]; then
    die "BRAVE_SEARCH_ENDPOINT is empty"
  fi

  mkdir -p "$OUTPUT_DIR" "$COMMON_TMP_DIR"

  RAW_SEARCH_FILE="$OUTPUT_DIR/raw_search_results.json"
  TMP_JSONL="$COMMON_TMP_DIR/${PROGRAM_NAME}_search_results.jsonl"

  : > "$TMP_JSONL"

  local query
  local idx=0

  while IFS= read -r query; do
    [[ -z "$query" ]] && continue
    idx=$((idx + 1))

    log INFO "step=search_news query_$idx start q=$query"

    local encoded_q
    encoded_q="$(urlencode "$query")"

    local url
    url="${BRAVE_SEARCH_ENDPOINT}?q=${encoded_q}&count=${BRAVE_SEARCH_COUNT:-10}&country=${BRAVE_SEARCH_COUNTRY:-TW}&search_lang=${BRAVE_SEARCH_LANG:-zh-hant}&freshness=${BRAVE_SEARCH_FRESHNESS:-pd}"

    local response_file
    response_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_query_${idx}.json"

    local http_code
    http_code="$(curl -sS \
      -H "Accept: application/json" \
      -H "X-Subscription-Token: $BRAVE_API_KEY" \
      -o "$response_file" \
      -w "%{http_code}" \
      "$url")"

    if [[ "$http_code" != "200" ]]; then
      log ERROR "step=search_news query_$idx failed http_code=$http_code"
      if [[ -f "$response_file" ]]; then
        log ERROR "step=search_news query_$idx response=$(tr '\n' ' ' < "$response_file" | head -c 500)"
      fi
      die "brave search failed for query_$idx"
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
    "response": data
}
print(json.dumps(record, ensure_ascii=False))
PY

    log INFO "step=search_news query_$idx done"
  done < <(get_search_queries)

  python3 - <<'PY' "$TMP_JSONL" "$RAW_SEARCH_FILE" "$PROGRAM_NAME"
import json
import sys
from pathlib import Path
from datetime import datetime

jsonl_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])
program_name = sys.argv[3]

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

  log INFO "step=search_news done raw_file=$RAW_SEARCH_FILE size_bytes=$result_size"
}
