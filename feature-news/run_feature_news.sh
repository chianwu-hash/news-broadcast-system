#!/usr/bin/env bash
set -Eeuo pipefail

source /home/vboxuser/news-broadcast-system/common/scripts/load_env.sh feature
source /home/vboxuser/news-broadcast-system/common/scripts/common.sh
source /home/vboxuser/news-broadcast-system/common/scripts/search_news.sh
source /home/vboxuser/news-broadcast-system/common/scripts/select_candidates.sh
source /home/vboxuser/news-broadcast-system/common/scripts/write_script.sh
source /home/vboxuser/news-broadcast-system/common/scripts/generate_tts.sh
source /home/vboxuser/news-broadcast-system/common/scripts/mix_audio.sh
source /home/vboxuser/news-broadcast-system/common/scripts/send_telegram.sh

LOCK_FILE="/tmp/news_broadcast_feature.lock"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date '+%F %T') [ERROR] feature-news is already running"
  exit 1
fi

START_TS=$(date +%s)
FEATURE_TOPIC="${1:-${FEATURE_TOPIC:-}}"
export FEATURE_TOPIC
FEATURE_TEXT_ONLY_MODE="${FEATURE_TEXT_ONLY_MODE:-1}"

FEATURE_STYLE_NAME="小蝦"
TTS_VOICE="zh-TW-HsiaoChenNeural"
export FEATURE_STYLE_NAME TTS_VOICE

send_selected_sources_summary() {
  if [[ ! -f "$SELECTED_FILE" || ! -s "$SELECTED_FILE" ]]; then
    log WARN "step=send_sources skipped selected file missing: $SELECTED_FILE"
    return 0
  fi

  local source_message=""
  if ! source_message="$(python3 - <<'PY' "$SELECTED_FILE" "$OUTPUT_DIR/prepared_search_items.json" "$PROGRAM_NAME" "${FEATURE_TOPIC:-}"
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse, urlsplit, urlunsplit

selected_file = Path(sys.argv[1])
prepared_file = Path(sys.argv[2])
program_name = sys.argv[3]
feature_topic = (sys.argv[4] or "").strip()

def parse_date(text: str, url: str) -> str:
    raw = (text or "").strip()
    def _parse_any(s: str) -> str | None:
        if not s:
            return None
        m = re.search(r"(20\d{2})[-/](\d{1,2})[-/](\d{1,2})", s)
        if m:
            return f"{int(m.group(1)):04d}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
        m = re.search(r"(20\d{2})年(\d{1,2})月(\d{1,2})日?", s)
        if m:
            return f"{int(m.group(1)):04d}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
        for fmt in (
            "%a, %d %b %Y %H:%M:%S GMT",
            "%a, %d %b %Y %H:%M:%S",
            "%Y-%m-%d %H:%M:%S",
            "%Y-%m-%d",
        ):
            try:
                dt = datetime.strptime(s, fmt).replace(tzinfo=timezone.utc)
                return dt.strftime("%Y-%m-%d")
            except Exception:
                pass
        lower = s.lower()
        now = datetime.now(timezone.utc)
        if "yesterday" in lower or "昨天" in s:
            return (now - timedelta(days=1)).strftime("%Y-%m-%d")
        if "today" in lower or "今天" in s:
            return now.strftime("%Y-%m-%d")
        m = re.search(r"(\d+)\s*(day|days)\s*ago", lower)
        if m:
            return (now - timedelta(days=int(m.group(1)))).strftime("%Y-%m-%d")
        m = re.search(r"(\d+)\s*(hour|hours|hr|hrs|min|mins|minute|minutes)\s*ago", lower)
        if m:
            return now.strftime("%Y-%m-%d")
        m = re.search(r"(\d+)\s*(天|日)\s*前", s)
        if m:
            return (now - timedelta(days=int(m.group(1)))).strftime("%Y-%m-%d")
        m = re.search(r"(\d+)\s*(小時|分鐘|分)\s*前", s)
        if m:
            return now.strftime("%Y-%m-%d")
        iso_text = s.replace("Z", "+00:00")
        try:
            dt = datetime.fromisoformat(iso_text)
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc).strftime("%Y-%m-%d")
        except Exception:
            return None

    parsed = _parse_any(raw)
    if parsed:
        return parsed

    u = (url or "").strip()
    m = re.search(r"/(20\d{2})/(0?[1-9]|1[0-2])/(0?[1-9]|[12]\d|3[01])(?:/|$)", u)
    if m:
        return f"{int(m.group(1)):04d}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
    m = re.search(r"/(20\d{2})(0[1-9]|1[0-2])([0-2]\d|3[01])(?:[^0-9]|$)", u)
    if m:
        return f"{int(m.group(1)):04d}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
    return "unknown"

def get_domain(source: str, url: str) -> str:
    source = (source or "").strip()
    if source:
        s = re.sub(r"^https?://", "", source, flags=re.I).strip().strip("/")
        s = s.split("/")[0]
        if s and "." in s and " " not in s:
            return s.lower()
    parsed = urlparse((url or "").strip())
    return (parsed.netloc or "unknown").lower()

def normalize_url(url: str) -> list[str]:
    u = (url or "").strip()
    if not u:
        return []
    keys = {u, u.rstrip("/")}
    try:
        s = urlsplit(u)
        no_q = urlunsplit((s.scheme, s.netloc, s.path, "", ""))
        keys.add(no_q)
        keys.add(no_q.rstrip("/"))
    except Exception:
        pass
    return [x for x in keys if x]

payload = json.loads(selected_file.read_text(encoding="utf-8"))
items = payload.get("selected", [])
if not isinstance(items, list):
    items = []

age_by_url = {}
if prepared_file.exists():
    try:
        prepared = json.loads(prepared_file.read_text(encoding="utf-8"))
        for it in prepared.get("items", []):
            if not isinstance(it, dict):
                continue
            age = (it.get("age") or "").strip()
            for k in normalize_url(str(it.get("url") or "")):
                if k and age and k not in age_by_url:
                    age_by_url[k] = age
    except Exception:
        pass

lines = []
for idx, item in enumerate(items, 1):
    if not isinstance(item, dict):
        continue
    title_zh = (item.get("title_zh") or "").strip()
    title = title_zh or (item.get("title") or "").strip() or "（無標題）"
    url = str(item.get("url") or "")
    raw_age = str(item.get("age") or "").strip()
    if not raw_age:
        for k in normalize_url(url):
            if k in age_by_url:
                raw_age = age_by_url[k]
                break
    age = parse_date(raw_age, url)
    source = get_domain(str(item.get("source") or ""), url)
    lines.append(f"{idx}. {age} | {source} | {title}")

topic_suffix = f"｜主題：{feature_topic}" if feature_topic else ""
if not lines:
    print(f"{program_name} 來源資訊{topic_suffix}：無可用資料")
    raise SystemExit(0)

header = f"{program_name} 來源資訊（{len(lines)}則）{topic_suffix}"
msg = header + "\n" + "\n".join(lines)
if len(msg) > 3500:
    kept = []
    size = len(header) + 1
    for line in lines:
        extra = len(line) + 1
        if size + extra > 3400:
            break
        kept.append(line)
        size += extra
    msg = header + "\n" + "\n".join(kept) + "\n（其餘略）"
print(msg)
PY
  )"; then
    log WARN "step=send_sources skipped parse failure selected_file=$SELECTED_FILE"
    return 0
  fi

  send_telegram_text "$source_message"
  log INFO "step=send_sources done selected_file=$SELECTED_FILE"
}

update_history_from_selected() {
  if [[ ! -f "$SELECTED_FILE" || ! -s "$SELECTED_FILE" ]]; then
    log ERROR "step=update_history skipped selected file missing: $SELECTED_FILE"
    return 0
  fi

  if [[ -z "${HISTORY_FILE:-}" ]]; then
    log ERROR "step=update_history skipped HISTORY_FILE is empty"
    return 0
  fi

  local history_result=""
  if ! history_result="$(python3 - <<'PY' "$SELECTED_FILE" "$HISTORY_FILE" "${HISTORY_MAX_ITEMS:-1000}" "$PROGRAM_NAME"
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

selected_file = Path(sys.argv[1])
history_file = Path(sys.argv[2])
history_max_items = int(sys.argv[3])
program_name = sys.argv[4]

def normalize_url(url: str) -> str:
    return (url or "").strip().rstrip("/")

def normalize_title(title: str) -> str:
    t = (title or "").strip().lower()
    t = re.sub(r"\s+", "", t)
    t = re.sub(r"[^\w\u4e00-\u9fff]+", "", t)
    return t

def load_json_list(path: Path):
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return []
    return data if isinstance(data, list) else []

selected_payload = json.loads(selected_file.read_text(encoding="utf-8"))
selected_items = selected_payload.get("selected", [])
if not isinstance(selected_items, list):
    selected_items = []

history_items = load_json_list(history_file)
now_iso = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

new_entries = []
for item in selected_items:
    if not isinstance(item, dict):
        continue
    title = (item.get("title") or "").strip()
    url = (item.get("url") or "").strip()
    if not title and not url:
        continue
    new_entries.append({
        "program_name": program_name,
        "published_at": now_iso,
        "title": title,
        "title_norm": normalize_title(title),
        "url": url,
        "url_norm": normalize_url(url),
        "source": (item.get("source") or "").strip(),
        "category": (item.get("category") or "").strip(),
        "region": (item.get("region") or "").strip(),
    })

merged = []
seen = set()
for entry in new_entries + history_items:
    if not isinstance(entry, dict):
        continue
    url_norm = normalize_url(str(entry.get("url_norm") or entry.get("url") or ""))
    title_norm = normalize_title(str(entry.get("title_norm") or entry.get("title") or ""))
    key = url_norm or title_norm
    if not key:
        continue
    if key in seen:
        continue
    seen.add(key)
    entry["url_norm"] = url_norm
    entry["title_norm"] = title_norm
    merged.append(entry)
    if len(merged) >= history_max_items:
        break

history_file.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"added={len(new_entries)} total={len(merged)}")
PY
  )"; then
    log ERROR "step=update_history failed to write history file: $HISTORY_FILE"
    return 0
  fi

  log INFO "step=update_history done $history_result history_file=$HISTORY_FILE"
}

archive_run_artifacts() {
  local keep_count="${FEATURE_RUNS_KEEP:-5}"
  if ! [[ "$keep_count" =~ ^[0-9]+$ ]] || (( keep_count < 1 )); then
    keep_count=5
  fi

  local run_ts topic_slug run_dir
  run_ts="$(date '+%Y%m%d_%H%M%S')"
  topic_slug="$(python3 - <<'PY' "${FEATURE_TOPIC:-adhoc}"
import re
import sys
s = (sys.argv[1] or "adhoc").strip()
s = re.sub(r"[\s/:]+", "_", s)
s = re.sub("[^0-9A-Za-z_\u4e00-\u9fff-]+", "", s)
print((s or "adhoc")[:40])
PY
)"
  [[ -z "$topic_slug" ]] && topic_slug="adhoc"
  run_dir="$RUNS_DIR/${run_ts}_${topic_slug}"

  mkdir -p "$run_dir"

  for f in \
    "$OUTPUT_DIR/raw_search_results.json" \
    "$OUTPUT_DIR/prepared_search_items.json" \
    "$CANDIDATES_FILE" \
    "$SELECTED_FILE" \
    "$SCRIPT_FILE" \
    "$VOICE_FILE" \
    "$FINAL_AUDIO_FILE"; do
    [[ -f "$f" ]] && cp -f "$f" "$run_dir/"
  done

  python3 - <<'PY' "$run_dir/metadata.json" "$PROGRAM_NAME" "${FEATURE_TOPIC:-}" "$START_TS" "$(date +%s)"
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

meta_file = Path(sys.argv[1])
program_name = sys.argv[2]
topic = sys.argv[3]
start_ts = int(sys.argv[4])
end_ts = int(sys.argv[5])
meta = {
    "program_name": program_name,
    "feature_topic": topic,
    "started_at_utc": datetime.fromtimestamp(start_ts, tz=timezone.utc).isoformat(),
    "finished_at_utc": datetime.fromtimestamp(end_ts, tz=timezone.utc).isoformat(),
    "duration_seconds": max(0, end_ts - start_ts),
}
meta_file.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
PY

  log INFO "step=archive_run done run_dir=$run_dir keep_count=$keep_count"

  mapfile -t run_dirs < <(find "$RUNS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
  local total="${#run_dirs[@]}"
  if (( total > keep_count )); then
    local remove_count=$((total - keep_count))
    for ((i=0; i<remove_count; i++)); do
      rm -rf "${run_dirs[$i]}"
      log INFO "step=archive_run pruned dir=${run_dirs[$i]}"
    done
  fi
}

on_error() {
  local exit_code=$?
  local line_no=$1
  log ERROR "script failed at line $line_no with exit code $exit_code"
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

log INFO "========================================"
log INFO "feature-news started"
log INFO "PROGRAM_NAME=$PROGRAM_NAME"
log INFO "LOG_FILE=$LOG_FILE"
log INFO "HISTORY_FILE=$HISTORY_FILE"
log INFO "SCRIPT_FILE=$SCRIPT_FILE"
log INFO "VOICE_FILE=$VOICE_FILE"
log INFO "FINAL_AUDIO_FILE=$FINAL_AUDIO_FILE"
log INFO "BGM_FILE=$BGM_FILE"
log INFO "TTS_VOICE=$TTS_VOICE"
log INFO "NEWS_COUNT=$NEWS_COUNT"
log INFO "CANDIDATE_COUNT=$CANDIDATE_COUNT"
log INFO "SCRIPT_TARGET_CHARS=$SCRIPT_TARGET_CHARS"
log INFO "FEATURE_TOPIC=${FEATURE_TOPIC:-N/A}"
log INFO "FEATURE_RUNS_KEEP=${FEATURE_RUNS_KEEP:-5}"
log INFO "FEATURE_TEXT_ONLY_MODE=$FEATURE_TEXT_ONLY_MODE"

search_news
select_candidates

# ── Material count gate（材料不足時提早中止，在 clustering/AI 前已判斷）
if [[ "${FEATURE_MATERIAL_INSUFFICIENT:-0}" == "1" ]]; then
  msg="材料不足，暫停產稿。主題：${FEATURE_TOPIC:-adhoc}"
  log WARN "step=material_count_gate aborted topic=${FEATURE_TOPIC:-adhoc}"
  send_telegram_text "$msg"
  archive_run_artifacts
  END_TS=$(date +%s)
  DURATION=$((END_TS - START_TS))
  log INFO "feature-news aborted by material_count_gate in ${DURATION}s"
  log INFO "========================================"
  exit 0
fi

# ── Source quality gate（僅 feature-news，可由 FEATURE_SOURCE_QUALITY_ENABLED 控制）
if [[ "${FEATURE_SOURCE_QUALITY_ENABLED:-1}" == "1" ]]; then
  local_prepared="$OUTPUT_DIR/prepared_search_items.json"
  local_gate_report="$OUTPUT_DIR/source_quality_report.json"
  local_gate_config="${FEATURE_SOURCE_QUALITY_CONFIG:-$BASE_DIR/common/config/feature_source_quality.json}"
  local_top_n="${FEATURE_SOURCE_QUALITY_TOP_N:-30}"
  if [[ -f "$local_prepared" && -s "$local_prepared" ]]; then
    gate_result="$(python3 "$BASE_DIR/common/scripts/source_quality_gate.py" \
      --input "$local_prepared" \
      --output "$local_gate_report" \
      --config "$local_gate_config" \
      --top-n "$local_top_n" 2>&1)" || true
    log INFO "step=source_quality_gate $gate_result"

    read -r gate_ok tier_a tier_b min_tier_a_actual min_tier_b_actual < <(python3 - "$local_gate_report" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
gate_ok = "true" if r.get("gate_ok") else "false"
tier_a = r["tier_counts"]["A"]
tier_b = r["tier_counts"]["B"]
min_a = r.get("rules", {}).get("min_tier_a", 0)
min_b = r.get("rules", {}).get("min_tier_b", 1)
print(f"{gate_ok} {tier_a} {tier_b} {min_a} {min_b}")
PY
    )

    if [[ "$gate_ok" != "true" ]]; then
      msg="來源品質不足，暫停產稿。主題：${FEATURE_TOPIC:-adhoc}｜A級：${tier_a}（需≥${min_tier_a_actual}）B級：${tier_b}（需≥${min_tier_b_actual}）"
      log WARN "step=source_quality_gate gate_ok=false tier_a=$tier_a tier_b=$tier_b"
      send_telegram_text "$msg"
      archive_run_artifacts
      END_TS=$(date +%s)
      DURATION=$((END_TS - START_TS))
      log INFO "feature-news aborted by source_quality_gate in ${DURATION}s"
      log INFO "========================================"
      exit 0
    fi
  else
    log WARN "step=source_quality_gate skipped: prepared_search_items.json not found"
  fi
fi

write_script
update_history_from_selected
archive_run_artifacts

if [[ "$FEATURE_TEXT_ONLY_MODE" != "1" ]]; then
  generate_tts
  mix_audio
  send_telegram_audio
fi

if [[ -n "${FEATURE_TOPIC:-}" ]]; then
  if [[ "$FEATURE_TEXT_ONLY_MODE" == "1" ]]; then
    send_telegram_text "文字稿已完成：${FEATURE_TOPIC}"
  else
    send_telegram_text "已完成：${FEATURE_TOPIC}"
  fi
else
  if [[ "$FEATURE_TEXT_ONLY_MODE" == "1" ]]; then
    send_telegram_text "文字稿已完成：新聞專題"
  else
    send_telegram_text "已完成：新聞專題"
  fi
fi
send_selected_sources_summary

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
log INFO "feature-news finished in ${DURATION}s"
log INFO "========================================"
