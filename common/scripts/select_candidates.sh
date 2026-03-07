#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] select_candidates.sh 必須用 source 載入，不能直接執行"
  exit 1
fi

prepare_candidate_input() {
  local raw_file="$1"
  local prepared_file="$2"

  python3 - <<'PY' "$raw_file" "$prepared_file" "${NEWS_URL_BLACKLIST_PATTERNS:-}" "${NEWS_SOURCE_BLACKLIST:-}" "${MIN_NEWS_TITLE_LENGTH:-12}" "${NEWS_EXACT_URL_BLACKLIST_PATTERNS:-}" "${HISTORY_FILE:-}" "${HISTORY_LOOKBACK_DAYS:-3}" "${NEWS_MAX_AGE_DAYS:-3}"
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

raw_file = Path(sys.argv[1])
prepared_file = Path(sys.argv[2])
url_blacklist_patterns = sys.argv[3]
source_blacklist_raw = sys.argv[4]
min_title_length = int(sys.argv[5])
exact_url_blacklist_raw = sys.argv[6]
history_file_raw = sys.argv[7]
history_lookback_days = int(sys.argv[8])
news_max_age_days = int(sys.argv[9])

data = json.loads(raw_file.read_text(encoding="utf-8"))
results = data.get("results", [])

items = []
seen = set()

url_blacklist_re = re.compile(url_blacklist_patterns, re.I) if url_blacklist_patterns else None
source_blacklist = {
    x.strip().lower()
    for x in source_blacklist_raw.split(",")
    if x.strip()
}
exact_url_blacklist = {
    x.strip().rstrip("/")
    for x in exact_url_blacklist_raw.split("|")
    if x.strip()
}

stats = {
    "raw_count": 0,
    "kept_count": 0,
    "filtered_short_title": 0,
    "filtered_bad_url": 0,
    "filtered_bad_source": 0,
    "filtered_non_article": 0,
    "filtered_stale": 0,
    "filtered_duplicate": 0,
    "filtered_history": 0,
}

def normalize_title(title: str) -> str:
    t = (title or "").strip().lower()
    t = re.sub(r"\s+", "", t)
    t = re.sub(r"[^\w\u4e00-\u9fff]+", "", t)
    return t

def normalize_url(url: str) -> str:
    return (url or "").strip().rstrip("/")

def is_bad_url(url: str) -> bool:
    if not url:
        return True
    if not url.startswith("http"):
        return True

    normalized = normalize_url(url)
    if normalized in exact_url_blacklist:
        return True

    if url_blacklist_re and url_blacklist_re.search(url):
        return True

    return False

def is_bad_source(source: str) -> bool:
    s = (source or "").strip().lower()
    if not s:
        return False
    return s in source_blacklist

def parse_iso_datetime(value: str):
    if not value:
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        dt = datetime.fromisoformat(text)
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def parse_age_datetime(value: str):
    raw = (value or "").strip()
    if not raw:
        return None

    lower = raw.lower()
    now = datetime.now(timezone.utc)

    specs = [
        (r"(\d+)\s*(minute|minutes|min|mins)\s*ago", "minutes"),
        (r"(\d+)\s*(hour|hours|hr|hrs)\s*ago", "hours"),
        (r"(\d+)\s*(day|days)\s*ago", "days"),
        (r"(\d+)\s*(week|weeks)\s*ago", "weeks"),
        (r"(\d+)\s*(month|months)\s*ago", "months"),
        (r"(\d+)\s*(year|years)\s*ago", "years"),
        (r"(\d+)\s*(\u5206\u9418)\s*\u524d", "minutes"),
        (r"(\d+)\s*(\u5c0f\u6642)\s*\u524d", "hours"),
        (r"(\d+)\s*(\u5929|\u65e5)\s*\u524d", "days"),
        (r"(\d+)\s*(\u9031|\u5468)\s*\u524d", "weeks"),
        (r"(\d+)\s*(\u500b\u6708|\u6708)\s*\u524d", "months"),
        (r"(\d+)\s*(\u5e74)\s*\u524d", "years"),
    ]
    for pat, unit in specs:
        m = re.search(pat, lower, re.I)
        if not m:
            continue
        n = int(m.group(1))
        if unit == "minutes":
            return now - timedelta(minutes=n)
        if unit == "hours":
            return now - timedelta(hours=n)
        if unit == "days":
            return now - timedelta(days=n)
        if unit == "weeks":
            return now - timedelta(weeks=n)
        if unit == "months":
            return now - timedelta(days=30 * n)
        if unit == "years":
            return now - timedelta(days=365 * n)

    if "yesterday" in lower or "\u6628\u5929" in raw:
        return now - timedelta(days=1)

    normalized = re.sub(r"[\u5e74\u6708]", "-", raw)
    normalized = re.sub(r"[\u65e5]", "", normalized)
    normalized = normalized.replace("/", "-")
    normalized = re.sub(r"\s+", " ", normalized).strip()

    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M", "%Y-%m-%d", "%b %d, %Y", "%B %d, %Y"):
        try:
            dt = datetime.strptime(normalized, fmt)
            if "%H" in fmt:
                return dt.replace(tzinfo=timezone.utc)
            return datetime(dt.year, dt.month, dt.day, tzinfo=timezone.utc)
        except ValueError:
            pass

    return parse_iso_datetime(raw)

history_entries = []
history_file = Path(history_file_raw) if history_file_raw else None
if history_file and history_file.exists():
    try:
        loaded = json.loads(history_file.read_text(encoding="utf-8"))
        if isinstance(loaded, list):
            history_entries = loaded
    except Exception:
        history_entries = []

history_cutoff = datetime.now(timezone.utc) - timedelta(days=max(0, history_lookback_days))
freshness_cutoff = datetime.now(timezone.utc) - timedelta(days=max(0, news_max_age_days))
current_year = datetime.now(timezone.utc).year
history_urls = set()
history_titles = set()
for entry in history_entries:
    if not isinstance(entry, dict):
        continue
    published_at = parse_iso_datetime(str(entry.get("published_at", "")))
    if published_at and published_at < history_cutoff:
        continue

    entry_url = normalize_url(str(entry.get("url_norm") or entry.get("url") or ""))
    entry_title = normalize_title(str(entry.get("title_norm") or entry.get("title") or ""))
    if entry_url:
        history_urls.add(entry_url)
    if entry_title:
        history_titles.add(entry_title)

def looks_like_non_article(url: str, title: str, desc: str) -> bool:
    normalized = normalize_url(url)
    parsed = urlparse(normalized)
    path = parsed.path or "/"

    if path in ("", "/"):
        return True

    bad_path_patterns = [
        r"^/search/.*",
        r"^/world/total$",
        r"^/realtimenews$",
        r"^/realtimenews/$",
        r"^/business/?$",
        r"^/live/?$",
        r"^/news/?$",
        r"^/world/?$",
        r"^/international/?$",
        r"^/hk/news/index\.html$",
        r"^/hk/intnews/index\.html$",
    ]
    for pat in bad_path_patterns:
        if re.search(pat, path, re.I):
            return True

    generic_title_patterns = [
        r"即時新聞",
        r"總覽",
        r"首頁",
        r"home",
        r"breaking international news",
        r"latest news",
    ]
    title_lower = (title or "").strip().lower()
    desc_lower = (desc or "").strip().lower()

    if len(title_lower) < min_title_length:
        return True

    for pat in generic_title_patterns:
        if re.search(pat, title, re.I):
            if len(path.strip("/").split("/")) <= 1:
                return True

    generic_desc_patterns = [
        r"find latest news from every corner",
        r"online source for breaking",
        r"delivers current national and local news",
    ]
    for pat in generic_desc_patterns:
        if re.search(pat, desc_lower, re.I):
            return True

    return False

for block in results:
    query = block.get("query", "")
    response = block.get("response", {})
    web = response.get("web", {})
    web_results = web.get("results", [])

    for r in web_results:
        stats["raw_count"] += 1

        title = (r.get("title") or "").strip()
        desc = (r.get("description") or "").strip()
        url = (r.get("url") or "").strip()
        age = (r.get("age") or "").strip()
        profile = r.get("profile") or {}
        source = (profile.get("name") or "").strip()

        if not title or not url:
            stats["filtered_bad_url"] += 1
            continue

        if len(title) < min_title_length:
            stats["filtered_short_title"] += 1
            continue

        if is_bad_url(url):
            stats["filtered_bad_url"] += 1
            continue

        if is_bad_source(source):
            stats["filtered_bad_source"] += 1
            continue

        if looks_like_non_article(url, title, desc):
            stats["filtered_non_article"] += 1
            continue

        published_at = parse_age_datetime(age)
        if published_at and published_at < freshness_cutoff:
            stats["filtered_stale"] += 1
            continue

        title_years = [int(y) for y in re.findall(r"(20\d{2})", title)]
        if title_years and max(title_years) < current_year:
            stats["filtered_stale"] += 1
            continue

        dedupe_key = (title, normalize_url(url))
        if dedupe_key in seen:
            stats["filtered_duplicate"] += 1
            continue

        url_norm = normalize_url(url)
        title_norm = normalize_title(title)
        if (url_norm and url_norm in history_urls) or (title_norm and title_norm in history_titles):
            stats["filtered_history"] += 1
            continue

        seen.add(dedupe_key)

        items.append({
            "query": query,
            "title": title,
            "description": desc,
            "url": url,
            "source": source,
            "age": age,
        })

stats["kept_count"] = len(items)

prepared = {
    "program_name": data.get("program_name", ""),
    "generated_at": data.get("generated_at", ""),
    "item_count": len(items),
    "filter_stats": stats,
    "items": items
}

prepared_file.write_text(
    json.dumps(prepared, ensure_ascii=False, indent=2),
    encoding="utf-8"
)
PY
}


cluster_events_ai() {
  local prepared_file="$1"
  local request_file="$2"
  local response_file="$3"

  local clustering_enabled="${EVENT_CLUSTERING_ENABLED:-1}"
  if [[ "$clustering_enabled" != "1" ]]; then
    log INFO "step=cluster_events_ai skipped EVENT_CLUSTERING_ENABLED=$clustering_enabled"
    return 0
  fi

  if [[ ! -f "$prepared_file" || ! -s "$prepared_file" ]]; then
    log WARN "step=cluster_events_ai skipped prepared file missing: $prepared_file"
    return 0
  fi

  local clustering_input_limit="${EVENT_CLUSTERING_INPUT_LIMIT:-60}"
  local clustering_strength="${EVENT_CLUSTERING_STRENGTH:-medium}"
  local clustering_timeout="${EVENT_CLUSTERING_TIMEOUT:-120}"

  python3 - <<'PYI' "$prepared_file" "$request_file" "$DEEPSEEK_MODEL" "$clustering_input_limit" "$clustering_strength" "$PROGRAM_NAME"
import json
import sys
from pathlib import Path

prepared_file = Path(sys.argv[1])
request_file = Path(sys.argv[2])
model_name = sys.argv[3]
input_limit = int(sys.argv[4])
strength = sys.argv[5]
program_name = sys.argv[6]

prepared = json.loads(prepared_file.read_text(encoding="utf-8"))
items = prepared.get("items", [])
if not isinstance(items, list):
    items = []
items = items[:max(1, input_limit)]
slim_items = []
for x in items:
    if not isinstance(x, dict):
        continue
    title = (x.get("title") or "").strip()
    url = (x.get("url") or "").strip()
    if not title or not url:
        continue
    slim_items.append({
        "title": title,
        "source": (x.get("source") or "").strip(),
        "url": url,
        "query": (x.get("query") or "").strip(),
        "age": (x.get("age") or "").strip(),
    })

system_prompt = (
    "You are a Traditional Chinese news event clustering assistant. "
    "Cluster the input news items into distinct real-world events. "
    "Dedup strength is medium: merge same core event across outlets, but keep materially different updates or angles. "
    "Output JSON only."
)

user_payload = {
    "task": "cluster_news_events",
    "program_name": program_name,
    "dedup_strength": strength,
    "items": slim_items,
    "output_schema": {
        "clusters": [
            {
                "cluster_id": "event-1",
                "event_summary": "short summary in zh-TW",
                "representative_index": 0,
                "member_indices": [0, 3, 7]
            }
        ],
        "deduped_items": [
            {
                "title": "headline",
                "source": "source",
                "url": "https://example.com",
                "description": "description",
                "query": "query",
                "age": "age"
            }
        ]
    }
}

payload = {
    "model": model_name,
    "temperature": 0.2,
    "messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": json.dumps(user_payload, ensure_ascii=False)}
    ]
}

request_file.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
PYI

  local http_code
  http_code="$(curl -sS \
    -o "$response_file" \
    -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
    --max-time "$clustering_timeout" \
    -d @"$request_file" \
    "$DEEPSEEK_API_URL")"

  if [[ "$http_code" != "200" ]]; then
    log WARN "step=cluster_events_ai fallback reason=http_code_$http_code"
    return 0
  fi

  local cluster_result
  if ! cluster_result="$(python3 - <<'PYO' "$response_file" "$prepared_file" "$clustering_input_limit"
import json
import re
import sys
from pathlib import Path

response_file = Path(sys.argv[1])
prepared_file = Path(sys.argv[2])
input_limit = int(sys.argv[3])

def extract_json_block(text: str):
    text = (text or "").strip()
    m = re.search(r"```json\s*(\{.*\})\s*```", text, re.S)
    if m:
        return m.group(1)
    m = re.search(r"(\{.*\})", text, re.S)
    if m:
        return m.group(1)
    return text

def normalize_item(item):
    if not isinstance(item, dict):
        return None
    title = (item.get("title") or "").strip()
    url = (item.get("url") or "").strip()
    if not title or not url:
        return None
    return {
        "query": (item.get("query") or "").strip(),
        "title": title,
        "description": (item.get("description") or "").strip(),
        "url": url,
        "source": (item.get("source") or "").strip(),
        "age": (item.get("age") or "").strip(),
    }

prepared = json.loads(prepared_file.read_text(encoding="utf-8"))
original_items = prepared.get("items", [])
if not isinstance(original_items, list):
    original_items = []
limited_original = original_items[:max(1, input_limit)]

data = json.loads(response_file.read_text(encoding="utf-8"))
content = data["choices"][0]["message"]["content"]
parsed = json.loads(extract_json_block(content))

clusters = parsed.get("clusters", [])
if not isinstance(clusters, list):
    clusters = []

deduped_items = []
for item in parsed.get("deduped_items", []):
    normalized = normalize_item(item)
    if normalized:
        deduped_items.append(normalized)

if not deduped_items and clusters:
    seen_idx = set()
    for c in clusters:
        if not isinstance(c, dict):
            continue
        idx = c.get("representative_index")
        if not isinstance(idx, int):
            continue
        if idx < 0 or idx >= len(limited_original) or idx in seen_idx:
            continue
        normalized = normalize_item(limited_original[idx])
        if normalized:
            deduped_items.append(normalized)
            seen_idx.add(idx)

if not deduped_items:
    raise ValueError("no usable deduped_items from clustering response")

before_count = len(original_items)
after_count = len(deduped_items)
prepared["items"] = deduped_items
prepared["item_count"] = after_count
prepared["clusters"] = clusters
prepared["cluster_stats"] = {
    "before_count": before_count,
    "after_count": after_count,
    "cluster_count": len(clusters),
    "merged_count": max(0, before_count - after_count),
}

prepared_file.write_text(json.dumps(prepared, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"before={before_count} after={after_count} clusters={len(clusters)}")
PYO
  )"; then
    log WARN "step=cluster_events_ai fallback reason=parse_or_validation_failed"
    return 0
  fi

  log INFO "step=cluster_events_ai done $cluster_result"
}

select_candidates() {
  log INFO "step=select_candidates start"

  if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
    die "DEEPSEEK_API_KEY is empty"
  fi

  if [[ -z "${DEEPSEEK_API_URL:-}" ]]; then
    die "DEEPSEEK_API_URL is empty"
  fi

  local raw_file="$OUTPUT_DIR/raw_search_results.json"
  local prepared_file="$OUTPUT_DIR/prepared_search_items.json"
  local request_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_candidate_request.json"
  local response_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_candidate_response.json"
  local cluster_request_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_cluster_request.json"
  local cluster_response_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_cluster_response.json"

  if [[ ! -f "$raw_file" ]]; then
    die "raw search file not found: $raw_file"
  fi

  prepare_candidate_input "$raw_file" "$prepared_file"

  if [[ ! -f "$prepared_file" || ! -s "$prepared_file" ]]; then
    die "prepared search items file not generated: $prepared_file"
  fi

  cluster_events_ai "$prepared_file" "$cluster_request_file" "$cluster_response_file"

  python3 - <<'PY' "$prepared_file" "$request_file" "$CANDIDATE_COUNT" "$PROGRAM_NAME" "$SCRIPT_TARGET_CHARS" "$DEEPSEEK_MODEL" "${EVENT_CLUSTERING_INPUT_LIMIT:-60}"
import json
import sys
from pathlib import Path

prepared_file = Path(sys.argv[1])
request_file = Path(sys.argv[2])
candidate_count = int(sys.argv[3])
program_name = sys.argv[4]
script_target_chars = sys.argv[5]
model_name = sys.argv[6]
input_limit = int(sys.argv[7])

prepared = json.loads(prepared_file.read_text(encoding="utf-8"))
items = prepared.get("items", [])

items = items[:max(1, input_limit)]

system_prompt = f"""你是台灣繁體中文新聞編輯。
你的工作是根據搜尋結果，初選出最適合做成 {program_name} 的候選新聞。

請遵守以下規則：
1. 使用繁體中文。
2. 以台灣聽眾的關聯性為優先。
3. 避免重複主題。
4. 優先挑選明確、具公共性、具討論價值的新聞。
5. 不要挑選首頁、分類頁、搜尋頁、評論頁、直播頁、影音頁。
6. 只輸出 JSON，不要輸出額外說明。
7. 請選出 {candidate_count} 則候選新聞。
8. 每則新聞都要包含：
   - rank
   - title
   - source
   - url
   - reason
   - category
   - region
"""

user_prompt = {
    "task": "select_candidate_news",
    "program_name": program_name,
    "candidate_count": candidate_count,
    "script_target_chars": script_target_chars,
    "items": items,
    "output_schema": {
        "candidates": [
            {
                "rank": 1,
                "title": "新聞標題",
                "source": "媒體名稱",
                "url": "https://example.com",
                "reason": "入選原因",
                "category": "politics/economy/society/world/sports/other",
                "region": "taiwan/world"
            }
        ]
    }
}

payload = {
    "model": model_name,
    "temperature": 0.3,
    "messages": [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": json.dumps(user_prompt, ensure_ascii=False)}
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
    --max-time "${DEEPSEEK_TIMEOUT:-120}" \
    -d @"$request_file" \
    "$DEEPSEEK_API_URL")"

  if [[ "$http_code" != "200" ]]; then
    log ERROR "step=select_candidates failed http_code=$http_code"
    if [[ -f "$response_file" ]]; then
      log ERROR "step=select_candidates response=$(tr '\n' ' ' < "$response_file" | head -c 800)"
    fi
    die "deepseek candidate selection failed"
  fi

  python3 - <<'PY' "$response_file" "$CANDIDATES_FILE"
import json
import re
import sys
from pathlib import Path

response_file = Path(sys.argv[1])
candidates_file = Path(sys.argv[2])

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

candidates_file.write_text(
    json.dumps(parsed, ensure_ascii=False, indent=2),
    encoding="utf-8"
)
PY

  if [[ ! -f "$CANDIDATES_FILE" || ! -s "$CANDIDATES_FILE" ]]; then
    die "candidates file not generated: $CANDIDATES_FILE"
  fi

  local candidate_size
  candidate_size=$(stat -c%s "$CANDIDATES_FILE" 2>/dev/null || echo 0)

  log INFO "step=select_candidates done candidates_file=$CANDIDATES_FILE size_bytes=$candidate_size"
}

