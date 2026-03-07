#!/usr/bin/env bash
set -Eeuo pipefail

source /home/vboxuser/news-broadcast-system/common/scripts/load_env.sh morning
source /home/vboxuser/news-broadcast-system/common/scripts/common.sh
source /home/vboxuser/news-broadcast-system/common/scripts/search_news.sh
source /home/vboxuser/news-broadcast-system/common/scripts/select_candidates.sh
source /home/vboxuser/news-broadcast-system/common/scripts/write_script.sh
source /home/vboxuser/news-broadcast-system/common/scripts/generate_tts.sh
source /home/vboxuser/news-broadcast-system/common/scripts/mix_audio.sh
source /home/vboxuser/news-broadcast-system/common/scripts/send_telegram.sh

LOCK_FILE="/tmp/news_broadcast_morning.lock"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date '+%F %T') [ERROR] morning-news is already running"
  exit 1
fi

START_TS=$(date +%s)

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
  if ! history_result="$(python3 - <<'PY' "$SELECTED_FILE" "$HISTORY_FILE" "${HISTORY_MAX_ITEMS:-1000}"
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

selected_file = Path(sys.argv[1])
history_file = Path(sys.argv[2])
history_max_items = int(sys.argv[3])

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
        "program_name": "morning-news",
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

on_error() {
  local exit_code=$?
  local line_no=$1
  log ERROR "script failed at line $line_no with exit code $exit_code"
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

log INFO "========================================"
log INFO "morning-news started"
log INFO "PROGRAM_NAME=$PROGRAM_NAME"
log INFO "SCRIPT_FILE=$SCRIPT_FILE"
log INFO "VOICE_FILE=$VOICE_FILE"
log INFO "FINAL_AUDIO_FILE=$FINAL_AUDIO_FILE"
log INFO "BGM_FILE=$BGM_FILE"
log INFO "TTS_VOICE=$TTS_VOICE"
log INFO "NEWS_COUNT=$NEWS_COUNT"
log INFO "CANDIDATE_COUNT=$CANDIDATE_COUNT"
log INFO "SCRIPT_TARGET_CHARS=$SCRIPT_TARGET_CHARS"

search_news
select_candidates
write_script
generate_tts
mix_audio
send_telegram_audio
update_history_from_selected

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
log INFO "morning-news finished in ${DURATION}s"
log INFO "========================================"

