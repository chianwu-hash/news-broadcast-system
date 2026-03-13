#!/usr/bin/env bash
set -Eeuo pipefail

source /home/vboxuser/news-broadcast-system/common/scripts/load_env.sh feature
source /home/vboxuser/news-broadcast-system/common/scripts/common.sh
source /home/vboxuser/news-broadcast-system/common/scripts/send_telegram.sh

LOCK_FILE="/tmp/news_broadcast_telegram_feature_listener.lock"
exec 8>"$LOCK_FILE"
if ! flock -n 8; then
  echo "$(date '+%F %T') [ERROR] telegram feature listener is already running"
  exit 1
fi

OFFSET_FILE="${TELEGRAM_FEATURE_OFFSET_FILE:-$RUNS_DIR/telegram_feature_offset.txt}"
POLL_TIMEOUT="${TELEGRAM_POLL_TIMEOUT:-25}"
POLL_INTERVAL="${TELEGRAM_POLL_INTERVAL:-2}"
ALLOWED_CHAT_ID="${TELEGRAM_FEATURE_CHAT_ID:-$TELEGRAM_CHAT_ID}"
BOT_TOKEN="${TELEGRAM_FEATURE_BOT_TOKEN:-$TELEGRAM_BOT_TOKEN}"
CLEAR_WEBHOOK_ON_START="${TELEGRAM_CLEAR_WEBHOOK_ON_START:-0}"
TRIGGER_LOG_FILE="${PROGRAM_LOG_DIR}/feature-trigger.log"
RUN_SCRIPT="/home/vboxuser/news-broadcast-system/feature-news/run_feature_news.sh"
RUN_ONCE="${1:-}"

mkdir -p "$(dirname "$OFFSET_FILE")" "$PROGRAM_LOG_DIR"
touch "$TRIGGER_LOG_FILE"

if [[ ! -f "$OFFSET_FILE" ]]; then
  echo "0" > "$OFFSET_FILE"
fi

if [[ ! -x "$RUN_SCRIPT" ]]; then
  chmod +x "$RUN_SCRIPT" || true
fi

if [[ "$CLEAR_WEBHOOK_ON_START" == "1" ]]; then
  curl -sS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/deleteWebhook" \
    -d drop_pending_updates=false >/dev/null || true
fi

log INFO "telegram_feature_listener started offset_file=$OFFSET_FILE allowed_chat_id=$ALLOWED_CHAT_ID"

handle_message() {
  local update_id="$1"
  local chat_id="$2"
  local text="$3"

  if [[ "$chat_id" != "$ALLOWED_CHAT_ID" ]]; then
    log WARN "listener skip unauthorized chat_id=$chat_id update_id=$update_id"
    return 0
  fi

  if [[ "$text" == "/featurehelp" ]]; then
    send_telegram_text "用法：/feature <專題主題>" "$chat_id"
    return 0
  fi

  if [[ "$text" == "/feature" ]]; then
    send_telegram_text "請提供主題，例如：/feature 台積電赴美投資" "$chat_id"
    return 0
  fi

  if [[ "$text" =~ ^/ttsfix[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)$ ]]; then
    local from_word="${BASH_REMATCH[1]}"
    local to_word="${BASH_REMATCH[2]}"
    local corrections_file="$BASE_DIR/common/config/tts_user_corrections.json"
    local result
    result="$(python3 - <<'PY' "$corrections_file" "$from_word" "$to_word"
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

corrections_file = Path(sys.argv[1])
from_word = sys.argv[2]
to_word = sys.argv[3]

if corrections_file.exists():
    try:
        data = json.loads(corrections_file.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            data = []
    except Exception:
        data = []
else:
    data = []

# 若已有相同 from，更新 to
updated = False
for rule in data:
    if rule.get("from") == from_word:
        rule["to"] = to_word
        rule["added_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        updated = True
        break

if not updated:
    data.append({
        "from": from_word,
        "to": to_word,
        "added_at": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
    })

corrections_file.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print(f"{'updated' if updated else 'added'} {from_word} -> {to_word} total={len(data)}")
PY
    )"
    send_telegram_text "✅ TTS 詞典已更新：「${from_word}」→「${to_word}」（$result）" "$chat_id"
    return 0
  fi

  if [[ "$text" == "/ttslist" ]]; then
    local corrections_file="$BASE_DIR/common/config/tts_user_corrections.json"
    local msg
    msg="$(python3 - <<'PY' "$corrections_file"
import json
import sys
from pathlib import Path

corrections_file = Path(sys.argv[1])
if not corrections_file.exists():
    print("（詞典為空）")
    sys.exit(0)
try:
    data = json.loads(corrections_file.read_text(encoding="utf-8"))
    if not isinstance(data, list) or not data:
        print("（詞典為空）")
        sys.exit(0)
except Exception:
    print("（讀取失敗）")
    sys.exit(0)

lines = [f"TTS 用戶詞典（共 {len(data)} 條）："]
for i, rule in enumerate(data, 1):
    lines.append(f"{i}. 「{rule.get('from','')}」→「{rule.get('to','')}」 ({rule.get('added_at','')})")
print("\n".join(lines))
PY
    )"
    send_telegram_text "$msg" "$chat_id"
    return 0
  fi

  if [[ "$text" =~ ^/ttsrm[[:space:]]+([^[:space:]]+)$ ]]; then
    local from_word="${BASH_REMATCH[1]}"
    local corrections_file="$BASE_DIR/common/config/tts_user_corrections.json"
    local result
    result="$(python3 - <<'PY' "$corrections_file" "$from_word"
import json
import sys
from pathlib import Path

corrections_file = Path(sys.argv[1])
from_word = sys.argv[2]

if not corrections_file.exists():
    print("not_found")
    sys.exit(0)
try:
    data = json.loads(corrections_file.read_text(encoding="utf-8"))
    if not isinstance(data, list):
        data = []
except Exception:
    print("error")
    sys.exit(0)

before = len(data)
data = [r for r in data if r.get("from") != from_word]
corrections_file.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
print("removed" if len(data) < before else "not_found")
PY
    )"
    if [[ "$result" == "removed" ]]; then
      send_telegram_text "🗑️ 已移除：「${from_word}」" "$chat_id"
    else
      send_telegram_text "⚠️ 找不到「${from_word}」的規則" "$chat_id"
    fi
    return 0
  fi

  if [[ "$text" =~ ^/feature(@[A-Za-z0-9_]+)?[[:space:]]+(.+) ]]; then
    local topic="${BASH_REMATCH[2]}"
    topic="$(echo "$topic" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if [[ -z "$topic" ]]; then
      send_telegram_text "請提供主題，例如：/feature 台積電赴美投資" "$chat_id"
      return 0
    fi

    if ! nohup /bin/bash "$RUN_SCRIPT" "$topic" >> "$TRIGGER_LOG_FILE" 2>&1 & then
      send_telegram_text "[feature-news] 觸發失敗，請稍後再試。" "$chat_id"
      return 0
    fi

    send_telegram_text "[feature-news] 已接單：$topic" "$chat_id"
    log INFO "listener triggered feature topic=$topic update_id=$update_id"
  fi
}

while true; do
  offset="$(cat "$OFFSET_FILE" 2>/dev/null || echo "0")"
  response_file="$COMMON_TMP_DIR/telegram_feature_updates.json"
  parsed_file="$COMMON_TMP_DIR/telegram_feature_updates.tsv"

  http_code="$(curl -sS \
    -o "$response_file" \
    -w "%{http_code}" \
    --max-time $((POLL_TIMEOUT + 10)) \
    "https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?timeout=${POLL_TIMEOUT}&offset=${offset}")"

  if [[ "$http_code" != "200" ]]; then
    local_snippet=""
    if [[ -f "$response_file" ]]; then
      local_snippet="$(tr '\n' ' ' < "$response_file" | head -c 300)"
    fi
    log WARN "listener getUpdates failed http_code=$http_code response=$local_snippet"
    sleep "$POLL_INTERVAL"
    if [[ "$RUN_ONCE" == "--once" ]]; then
      break
    fi
    continue
  fi

  python3 - <<'PY' "$response_file" "$parsed_file"
import json
import sys
from pathlib import Path

response_file = Path(sys.argv[1])
parsed_file = Path(sys.argv[2])

data = json.loads(response_file.read_text(encoding="utf-8"))
rows = []
for item in data.get("result", []):
    if not isinstance(item, dict):
        continue
    update_id = item.get("update_id")
    msg = item.get("message") or item.get("edited_message") or {}
    if not isinstance(msg, dict):
        continue
    text = msg.get("text", "")
    chat = msg.get("chat", {}) if isinstance(msg.get("chat", {}), dict) else {}
    chat_id = chat.get("id")
    if update_id is None or chat_id is None:
        continue
    text = " ".join(str(text).split())
    rows.append(f"{update_id}\t{chat_id}\t{text}")

parsed_file.write_text("\n".join(rows), encoding="utf-8")
PY

  if [[ -s "$parsed_file" ]]; then
    max_update_id=-1
    while IFS=$'\t' read -r update_id chat_id text; do
      [[ -z "${update_id:-}" ]] && continue
      handle_message "$update_id" "$chat_id" "$text"
      if (( update_id > max_update_id )); then
        max_update_id="$update_id"
      fi
    done < "$parsed_file"

    if (( max_update_id >= 0 )); then
      echo $((max_update_id + 1)) > "$OFFSET_FILE"
    fi
  fi

  if [[ "$RUN_ONCE" == "--once" ]]; then
    break
  fi

  sleep "$POLL_INTERVAL"
done

log INFO "telegram_feature_listener stopped"
