#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] select_candidates.sh 必須用 source 載入，不能直接執行"
  exit 1
fi

prepare_candidate_input() {
  local raw_file="$1"
  local prepared_file="$2"

  python3 - <<'PY' "$raw_file" "$prepared_file" "${NEWS_URL_BLACKLIST_PATTERNS:-}" "${NEWS_SOURCE_BLACKLIST:-}" "${MIN_NEWS_TITLE_LENGTH:-12}" "${NEWS_EXACT_URL_BLACKLIST_PATTERNS:-}" "${HISTORY_FILE:-}" "${HISTORY_LOOKBACK_DAYS:-3}" "${NEWS_MAX_AGE_DAYS:-3}" "$PROGRAM_NAME" "${FEATURE_TOPIC:-}"
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
program_name = sys.argv[10]
feature_topic = (sys.argv[11] or '').strip()

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
    "filtered_sports_filler": 0,
    "filtered_non_article": 0,
    "filtered_stale": 0,
    "filtered_duplicate": 0,
    "filtered_history": 0,
    "filtered_topic_mismatch": 0,
}

def normalize_title(title: str) -> str:
    t = (title or "").strip().lower()
    t = re.sub(r"\s+", "", t)
    t = re.sub(r"[^\w\u4e00-\u9fff]+", "", t)
    return t

def normalize_url(url: str) -> str:
    return (url or "").strip().rstrip("/")


def extract_topic_keywords(topic: str):
    text = (topic or "").strip().lower()
    if not text:
        return []

    stopwords = {
        "latest", "news", "analysis", "impact", "feature", "topic",
        "??", "??", "??", "??", "??", "??", "??", "??", "??",
        "??", "??", "??", "???", "??", "??", "??",
    }
    keywords = []
    seen_keywords = set()

    for part in re.findall(r"[a-z0-9][a-z0-9\-]{1,}|[\u4e00-\u9fff]+", text, re.I):
        chunk = part.strip().lower()
        if not chunk:
            continue
        if re.fullmatch(r"20\d{2}", chunk):
            if chunk not in seen_keywords:
                seen_keywords.add(chunk)
                keywords.append(chunk)
            continue
        if re.fullmatch(r"[a-z0-9][a-z0-9\-]{1,}", chunk, re.I):
            if chunk not in stopwords and chunk not in seen_keywords:
                seen_keywords.add(chunk)
                keywords.append(chunk)
            continue
        if len(chunk) <= 4:
            if chunk not in stopwords and chunk not in seen_keywords:
                seen_keywords.add(chunk)
                keywords.append(chunk)
            continue
        for size in (4, 3, 2):
            for i in range(0, len(chunk) - size + 1):
                kw = chunk[i:i + size]
                if kw in stopwords or kw in seen_keywords:
                    continue
                seen_keywords.add(kw)
                keywords.append(kw)

    keywords.sort(key=lambda x: (-len(x), x))
    return keywords[:10]

topic_keywords = extract_topic_keywords(feature_topic)
core_topic_keywords = [kw for kw in topic_keywords if not re.fullmatch(r"20\d{2}", kw)][:4]

def feature_topic_exclusions(topic: str):
    raw = (topic or "").lower()
    if not raw:
        return []
    if any(token in raw for token in ["??", "??", "??", "tariff", "export", "trade"]):
        return ["??", "??", "??", "??", "???", "???", "????", "Sunday Service"]
    if any(token in raw for token in ["gtc", "??", "nvidia"]):
        return ["??", "??", "????", "?????", "????"]
    if any(token in raw for token in ["wbc", "?????", "???", "???"]):
        return ["????", "???", "???", "??", "??"]
    return []

topic_exclusions = feature_topic_exclusions(feature_topic)


def feature_topic_requirements(topic: str):
    raw = (topic or "").lower()
    if not raw:
        return []
    if any(token in raw for token in ["gtc"]):
        return [["gtc"], ["??", "nvidia"]]
    if any(token in raw for token in ["??", "??", "??", "tariff", "export", "trade"]):
        return [["??", "tariff"], ["??", "??", "export", "trade", "??"]]
    if any(token in raw for token in ["wbc", "?????"]):
        return [["wbc", "?????", "???????"], ["???", "???"]]
    return []

required_term_groups = feature_topic_requirements(feature_topic)

def feature_source_boost(source: str, url: str) -> int:
    if program_name != "feature-news":
        return 0
    source_lc = (source or "").strip().lower()
    url_lc = (url or "").strip().lower()

    preferred = [
        "reuters", "ap", "associated press", "bloomberg", "financial times",
        "wsj", "wall street journal", "nikkei", "economist", "cna", "中央社",
        "udn", "經濟日報", "工商時報",
    ]
    for token in preferred:
        if token in source_lc or token in url_lc:
            return 2
    return 0

def feature_topic_metrics(title: str, desc: str, query: str, url: str):
    if program_name != "feature-news" or not feature_topic:
        return 0, 0, [], 0
    haystack = " ".join([
        (title or "").lower(),
        (desc or "").lower(),
        (query or "").lower(),
        (url or "").lower(),
    ])
    score = 0
    matched = []
    if feature_topic.lower() in haystack:
        score += 3
        matched.append(feature_topic.lower())
    for kw in topic_keywords:
        if kw in haystack:
            score += 2 if len(kw) >= 3 else 1
            matched.append(kw)
    core_hits = sum(1 for kw in core_topic_keywords if kw in haystack)
    required_hits = 0
    for group in required_term_groups:
        if any(term.lower() in haystack for term in group):
            required_hits += 1
    return score, core_hits, matched, required_hits

def feature_retrieval_score(title: str, desc: str, query: str, url: str, source: str):
    if program_name != "feature-news":
        return 0
    title_lc = (title or "").lower()
    desc_lc = (desc or "").lower()
    query_lc = (query or "").lower()
    topic_lc = (feature_topic or "").lower()

    score = 0
    if topic_lc and topic_lc in title_lc:
        score += 5
    if topic_lc and topic_lc in query_lc:
        score += 3

    for kw in core_topic_keywords:
        if kw in title_lc:
            score += 3
        elif kw in desc_lc:
            score += 1

    for group in required_term_groups:
        if any(term.lower() in title_lc for term in group):
            score += 4
        elif any(term.lower() in query_lc for term in group):
            score += 2

    score += feature_source_boost(source, url)
    return score

def feature_topic_is_excluded(title: str, desc: str, query: str, url: str) -> bool:
    if program_name != "feature-news" or not topic_exclusions:
        return False
    haystack = " ".join([
        (title or "").lower(),
        (desc or "").lower(),
        (query or "").lower(),
        (url or "").lower(),
    ])
    for token in topic_exclusions:
        if token.lower() in haystack:
            return True
    return False

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

# 過濾週報/週刊式軟性體育文章（不含即時新聞價值）
_SPORTS_FILLER_TITLE_RE = re.compile(
    r"週報|週刊|周報|weekly\s+report|賽季展望|賽季總覽|賽季回顧",
    re.I,
)

def is_sports_filler_title(title: str) -> bool:
    return bool(_SPORTS_FILLER_TITLE_RE.search(title or ""))

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

    relative_specs = [
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
    for pat, unit in relative_specs:
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
    for fmt in [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d",
        "%b %d, %Y",
        "%B %d, %Y",
    ]:
        try:
            dt = datetime.strptime(normalized, fmt)
            if "%H" in fmt:
                return dt.replace(tzinfo=timezone.utc)
            return datetime(dt.year, dt.month, dt.day, tzinfo=timezone.utc)
        except ValueError:
            continue
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

# 跨節目去重：載入其他節目的 history.json
sibling_shows = ["morning-news", "evening-news", "feature-news"]
if history_file:
    project_root = history_file.parent.parent.parent
    for show in sibling_shows:
        sibling_path = project_root / show / "data" / "history.json"
        if sibling_path == history_file or not sibling_path.exists():
            continue
        try:
            sibling_data = json.loads(sibling_path.read_text(encoding="utf-8"))
            if isinstance(sibling_data, list):
                history_entries.extend(sibling_data)
        except Exception:
            pass

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
        r"^/realtimenews/?$",
        r"^/business/?$",
        r"^/live/?$",
        r"^/news/?$",
        r"^/world/?$",
        r"^/international/?$",
        r"^/hk/news/index\.html$",
        r"^/hk/intnews/index\.html$",
        r"^/world/[a-z-]+/?$",
        r"^/news/[a-z-]+/?$",
        r"^/news/world/[a-z-]+/?$",
        r"^/[a-z-]+stock/?$",
        r"^/[a-z-]+/latest/?$",
        r"^/[a-z-]+/headlines/?$",
        r"^/topics?/[a-z-]+/?$",
        r"^/tag/[a-z-]+/?$",
        r"^/category/[a-z-]+/?$",
        r"/editorials?/",
        r"/opinions?/",
        r"/op-ed/",
        r"/commentary/",
        r"/columns?/",
    ]
    for pat in bad_path_patterns:
        if re.search(pat, path, re.I):
            return True

    # 股票個股頁面（無文章內容，只有即時報價）
    stock_page_patterns = [
        r"^/stocks/[A-Z]+/[A-Z]+/?$",
        r"/stock-price.*\$[A-Z]+",
    ]
    for pat in stock_page_patterns:
        if re.search(pat, url, re.I):
            return True

    generic_title_patterns = [
        r"即時新聞",
        r"總覽",
        r"首頁",
        r"home",
        r"breaking international news",
        r"latest news",
        r"^[\w\s]+ news\s*\|",
        r"latest headlines",
        r"頭條新聞",
        r"^EDITORIAL:",
        r"^OPINION:",
        r"^社論[：:]",
        r"^投書[：:]",
        r"Stock Price, News & Analysis",
    ]
    title_lower = (title or "").strip().lower()
    desc_lower = (desc or "").strip().lower()

    if len(title_lower) < min_title_length:
        return True

    for pat in generic_title_patterns:
        if re.search(pat, title, re.I):
            if len(path.strip("/").split("/")) <= 2:
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

        if is_sports_filler_title(title):
            stats["filtered_sports_filler"] += 1
            continue

        if looks_like_non_article(url, title, desc):
            stats["filtered_non_article"] += 1
            continue

        if feature_topic_is_excluded(title, desc, query, url):
            stats["filtered_topic_mismatch"] += 1
            continue

        published_at = parse_age_datetime(age)
        if published_at and published_at < freshness_cutoff:
            stats["filtered_stale"] += 1
            continue

        # For recurring events (for example WBC), force same-year freshness.
        title_years = [int(y) for y in re.findall(r"(20\d{2})", title)]
        if title_years and max(title_years) < current_year:
            stats["filtered_stale"] += 1
            continue

        dedupe_key = (title, normalize_url(url))
        title_dedupe_key = normalize_title(title)
        if dedupe_key in seen or (title_dedupe_key and title_dedupe_key in seen):
            stats["filtered_duplicate"] += 1
            continue

        url_norm = normalize_url(url)
        title_norm = normalize_title(title)
        if (url_norm and url_norm in history_urls) or (title_norm and title_norm in history_titles):
            stats["filtered_history"] += 1
            continue

        topic_score, topic_core_hits, topic_matched_keywords, topic_required_hits = feature_topic_metrics(title, desc, query, url)
        retrieval_score = feature_retrieval_score(title, desc, query, url, source)
        if program_name == "feature-news" and feature_topic:
            min_core_hits = 1 if len(core_topic_keywords) <= 1 else 2
            haystack = " ".join([title.lower(), desc.lower(), query.lower(), url.lower()])
            if required_term_groups and topic_required_hits < len(required_term_groups):
                stats["filtered_topic_mismatch"] += 1
                continue
            if topic_core_hits < min_core_hits and feature_topic.lower() not in haystack:
                stats["filtered_topic_mismatch"] += 1
                continue
            if topic_score < 3:
                stats["filtered_topic_mismatch"] += 1
                continue

        seen.add(dedupe_key)
        if title_dedupe_key:
            seen.add(title_dedupe_key)

        items.append({
            "query": query,
            "title": title,
            "description": desc,
            "url": url,
            "source": source,
            "age": age,
            "topic_score": topic_score,
            "topic_core_hits": topic_core_hits,
            "topic_required_hits": topic_required_hits,
            "topic_matched_keywords": topic_matched_keywords,
            "retrieval_score": retrieval_score,
        })

if program_name == "feature-news" and feature_topic:
    items.sort(
        key=lambda x: (
            int(x.get("topic_required_hits", 0)),
            int(x.get("retrieval_score", 0)),
            int(x.get("topic_core_hits", 0)),
            int(x.get("topic_score", 0)),
            x.get("title", ""),
        ),
        reverse=True,
    )

stats["kept_count"] = len(items)

material_summary = {}
if program_name == "feature-news" and feature_topic:
    material_summary = {
        "high_confidence_count": sum(
            1 for x in items
            if int(x.get("topic_required_hits", 0)) >= max(1, len(required_term_groups))
            and int(x.get("retrieval_score", 0)) >= 8
        ),
        "usable_count": sum(
            1 for x in items
            if int(x.get("retrieval_score", 0)) >= 5
        ),
    }

prepared = {
    "program_name": data.get("program_name", ""),
    "generated_at": data.get("generated_at", ""),
    "feature_topic": feature_topic,
    "feature_scope": data.get("feature_scope", ""),
    "feature_profile": data.get("feature_profile", ""),
    "item_count": len(items),
    "filter_stats": stats,
    "material_summary": material_summary,
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
  local clustering_timeout="${EVENT_CLUSTERING_TIMEOUT:-90}"

  python3 - <<'PY' "$prepared_file" "$request_file" "$DEEPSEEK_MODEL" "$clustering_input_limit" "$clustering_strength" "$PROGRAM_NAME"
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
        "description": (x.get("description") or "").strip()[:300],
        "query": (x.get("query") or "").strip(),
        "age": (x.get("age") or "").strip(),
    })

if program_name == "feature-news":
    dedup_instruction = (
        "Dedup strength is loose: only merge articles covering the exact same specific sub-event or announcement. "
        "Keep articles that cover different dimensions, timeframes, actors, or policy implications, "
        "even if on the same broad topic."
    )
else:
    dedup_instruction = (
        "Dedup strength is LOW: only merge if same exact event, same headline across outlets. "
        "Keep all sports game results, player moves, and team news as separate items. "
        "Do not merge sports articles even if similar topic."
    )
system_prompt = (
    "You are a Traditional Chinese news event clustering assistant. "
    "Cluster the input news items into distinct real-world events. "
    f"{dedup_instruction} "
    "IMPORTANT: Keep all sports/game articles (CPBL, MLB, NBA, etc.) as separate items. Do NOT merge them."
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

request_file.write_text(
    json.dumps(payload, ensure_ascii=False, indent=2),
    encoding="utf-8"
)
PY

  local http_code
  http_code="$(curl -s \
    -o "$response_file" \
    -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
    --max-time "$clustering_timeout" \
    -d @"$request_file" \
    "$DEEPSEEK_API_URL" || true)"

  if ! [[ "$http_code" =~ ^[0-9]{3}$ ]]; then
    log WARN "step=cluster_events_ai fallback reason=curl_error_or_timeout"
    return 0
  fi

  if [[ "$http_code" != "200" ]]; then
    log WARN "step=cluster_events_ai fallback reason=http_code_$http_code"
    return 0
  fi

  local cluster_result
  if ! cluster_result="$(python3 - 2>/dev/null <<'PY' "$response_file" "$prepared_file" "$clustering_input_limit"
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

def build_lookup(items):
    by_url = {}
    by_title = {}
    for item in items:
        if not isinstance(item, dict):
            continue
        url = (item.get("url") or "").strip()
        title = (item.get("title") or "").strip().lower()
        if url:
            by_url[url] = item
        if title:
            by_title[title] = item
    return by_url, by_title

def enrich_item(normalized, original_by_url, original_by_title):
    if not normalized:
        return None
    original = original_by_url.get(normalized.get("url", ""))
    if original is None:
        original = original_by_title.get((normalized.get("title") or "").strip().lower())
    if original is None:
        return normalized
    merged = dict(original)
    merged.update({k: v for k, v in normalized.items() if v not in ("", None, [])})
    return merged

prepared = json.loads(prepared_file.read_text(encoding="utf-8"))
original_items = prepared.get("items", [])
if not isinstance(original_items, list):
    original_items = []
limited_original = original_items[:max(1, input_limit)]
original_by_url, original_by_title = build_lookup(limited_original)

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
        deduped_items.append(enrich_item(normalized, original_by_url, original_by_title))

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
            deduped_items.append(enrich_item(normalized, original_by_url, original_by_title))
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
prepared["material_summary"] = {
    "high_confidence_count": sum(
        1 for x in deduped_items
        if int(x.get("topic_required_hits", 0)) >= 1 and int(x.get("retrieval_score", 0)) >= 8
    ),
    "usable_count": sum(
        1 for x in deduped_items
        if int(x.get("retrieval_score", 0)) >= 5
    ),
}

prepared_file.write_text(
    json.dumps(prepared, ensure_ascii=False, indent=2),
    encoding="utf-8"
)
print(f"before={before_count} after={after_count} clusters={len(clusters)}")
PY
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

  # Early material count check for feature-news (before clustering + AI calls)
  if [[ "$PROGRAM_NAME" == "feature-news" && "${FEATURE_MATERIAL_COUNT_GATE_ENABLED:-1}" == "1" ]]; then
    local _item_count
    _item_count=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('item_count',0))" "$prepared_file" 2>/dev/null || echo 0)
    local _min_items="${FEATURE_MIN_PREPARED_ITEMS:-4}"
    log INFO "step=select_candidates material_count_check item_count=$_item_count min=$_min_items"
    if (( _item_count < _min_items )); then
      log WARN "step=select_candidates material_insufficient item_count=$_item_count min=$_min_items"
      FEATURE_MATERIAL_INSUFFICIENT=1
      export FEATURE_MATERIAL_INSUFFICIENT
      return 0
    fi
  fi

  cluster_events_ai "$prepared_file" "$cluster_request_file" "$cluster_response_file"

  python3 - <<'PY' "$prepared_file" "$request_file" "$CANDIDATE_COUNT" "$PROGRAM_NAME" "$SCRIPT_TARGET_CHARS" "$DEEPSEEK_MODEL" "${EVENT_CLUSTERING_INPUT_LIMIT:-60}"
import json
import sys
from datetime import date
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

# 中華職棒賽季：3/25 ~ 10/31
def is_cpbl_season() -> bool:
    today = date.today()
    season_start = date(today.year, 3, 25)
    season_end = date(today.year, 10, 31)
    return season_start <= today <= season_end

cpbl_active = is_cpbl_season()

# 分類配額規則（依節目類型）
if program_name == "morning-news":
    tone_note = "早安新聞偏輕快，軟性類別比重可稍高。"
    category_rules = """
9. 新聞分類配額（請盡量均衡分配，各佔1則）：
   - 國際（world）：1則
   - 政治（politics）：1則
   - 財經或科技（economy/tech）：1則，兩者輪替，優先選當天最重要的
   - 社會或民生（society）：1則
   - 軟性（教育/健康/環境/文化，category 填 other）：1則"""
elif program_name == "evening-news":
    tone_note = "晚安新聞偏深度，政治財經比重可稍高。"
    category_rules = """
9. 新聞分類配額（請盡量均衡分配，各佔1則）：
   - 國際（world）：1則
   - 政治（politics）：1則
   - 財經或科技（economy/tech）：1則，兩者輪替，優先選當天最重要的
   - 社會或民生（society）：1則
   - 軟性（教育/健康/環境/文化，category 填 other）：1則"""
else:
    tone_note = ""
    category_rules = ""

# 中職賽季加體育 slot
sports_rule = ""
no_sports_rule = ""
if not cpbl_active and program_name in ("morning-news", "evening-news"):
    no_sports_rule = "\n10. 現在不是中華職棒賽季，請勿選入任何體育新聞（category = sports）。"
if cpbl_active and program_name == "morning-news":
    sports_rule = """
10. 今日為中華職棒賽季期間，體育新聞規則（**嚴格遵守**）：
    MLB（時區配合：美國賽事在台灣早上出結果）：
    - 請選 1-2 則有**具體比分或球員當場表現**的 MLB 賽事報導（非首頁、非聚合頁、非統計頁）。
    - 若找不到符合條件的 MLB 新聞，可不選（勿以首頁連結代替）。
    CPBL（中華職棒）：
    - 若有**昨日賽事比分**的報導可選 1 則，但 MLB 優先。
    - **嚴禁用週報、週刊、賽季分析、球員訪談或軟性故事代替比賽結果**。
    共通條件：所有體育新聞必須是 2 天內的。
    因此本次最多共需選出（含體育）{candidate_count_plus2} 則，但體育篇數可依實際素材品質調減。""".format(
        candidate_count_plus2=candidate_count + 2
    )
    candidate_count += 2
if cpbl_active and program_name == "evening-news":
    sports_rule = """
10. 今日為中華職棒賽季期間，體育新聞規則（**嚴格遵守**）：
    CPBL（中華職棒，時區配合：台灣晚間出今日賽果）：
    - 請選 2 則有**具體比分**的賽事報導（例：「X隊 N:M 擊敗 Y隊」、「某球員轟出全壘打」、「再見安打」、「勝投」等）。
    - **若搜尋結果中有比分的 CPBL 新聞不足 2 則，選 0 或 1 則即可**。
    - **嚴禁用週報、週刊、賽季分析、球員訪談或軟性故事代替比賽結果**。
    MLB：
    - 若有昨日 MLB 重大表現可選 1 則，但 CPBL 優先。
    共通條件：所有體育新聞必須是 2 天內的。
    因此本次最多共需選出（含體育）{candidate_count_plus2} 則，但體育篇數可依實際素材品質調減。""".format(
        candidate_count_plus2=candidate_count + 2
    )
    candidate_count += 2

system_prompt = f"""你是台灣繁體中文新聞編輯。
你的工作是根據搜尋結果，初選出最適合做成 {program_name} 的候選新聞。
{tone_note}

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
   - category（politics/economy/tech/society/sports/other）
   - region（taiwan/world）{category_rules}{sports_rule}{no_sports_rule}
11. 同一家公司或同一個主題最多選 2 則，避免過度集中（例如不要選 3 則以上台積電相關新聞）。
"""

user_prompt = {
    "task": "select_candidate_news",
    "program_name": program_name,
    "candidate_count": candidate_count,
    "script_target_chars": script_target_chars,
    "items": slim_items,
    "output_schema": {
        "candidates": [
            {
                "rank": 1,
                "title": "新聞標題",
                "source": "媒體名稱",
                "url": "https://example.com",
                "description": "必須原封不動複製 items 中該筆的 description 欄位，禁止改寫、摘要或重新措辭",
                "reason": "入選原因",
                "category": "politics/economy/tech/society/sports/other",
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
    --max-time "${DEEPSEEK_SELECT_TIMEOUT:-120}" \
    -d @"$request_file" \
    "$DEEPSEEK_API_URL" || true)"

  if ! [[ "$http_code" =~ ^[0-9]{3}$ ]]; then
    http_code="000"
  fi

  if [[ "$http_code" != "200" ]]; then
      log WARN "step=select_candidates fallback local_pick reason=http_${http_code}"
      python3 - <<'PY' "$prepared_file" "$CANDIDATES_FILE" "$CANDIDATE_COUNT"
import json
import sys
from pathlib import Path

prepared_file = Path(sys.argv[1])
candidates_file = Path(sys.argv[2])
candidate_count = int(sys.argv[3])

prepared = json.loads(prepared_file.read_text(encoding="utf-8"))
items = prepared.get("items", [])
if not isinstance(items, list):
    items = []

out = {"candidates": []}
rank = 1
for item in items:
    if rank > max(1, candidate_count):
        break
    if not isinstance(item, dict):
        continue
    title = (item.get("title") or "").strip()
    url = (item.get("url") or "").strip()
    if not title or not url:
        continue
    out["candidates"].append({
        "rank": rank,
        "title": title,
        "source": (item.get("source") or "").strip(),
        "url": url,
        "reason": "fallback_local_pick",
        "category": "other",
        "region": "taiwan",
    })
    rank += 1

candidates_file.write_text(
    json.dumps(out, ensure_ascii=False, indent=2),
    encoding="utf-8"
)
PY
    log INFO "step=select_candidates done candidates_file=$CANDIDATES_FILE mode=fallback_local_pick"
    return 0
  fi

  python3 - <<'PY' "$response_file" "$CANDIDATES_FILE" "$prepared_file"
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse, urlunparse

response_file = Path(sys.argv[1])
candidates_file = Path(sys.argv[2])
prepared_file = Path(sys.argv[3])

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

def norm_url(u):
    p = urlparse(u.strip().rstrip("/"))
    return urlunparse((p.scheme, p.netloc.lower(), p.path.rstrip("/"), "", "", ""))

prepared = json.loads(prepared_file.read_text(encoding="utf-8"))
orig_descs = {}
for item in prepared.get("items", []):
    url = item.get("url", "")
    desc = item.get("description", "")
    if url and desc:
        orig_descs[norm_url(url)] = desc

import html as _html

def clean_html(text):
    text = re.sub(r"<[^>]+>", "", text)
    return _html.unescape(text).strip()

for cand in parsed.get("candidates", []):
    url = cand.get("url", "")
    key = norm_url(url)
    if key in orig_descs:
        cand["description"] = clean_html(orig_descs[key])

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
