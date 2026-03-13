#!/usr/bin/env bash
set -Eeuo pipefail

# openclaw_tts_bridge.sh - TTS user corrections bridge for OpenClaw skills
#
# Usage:
#   openclaw_tts_bridge.sh add <from> <to>
#   openclaw_tts_bridge.sh list
#   openclaw_tts_bridge.sh remove <from>

CORRECTIONS_FILE="/home/vboxuser/news-broadcast-system/common/config/tts_user_corrections.json"

action="${1:-}"

case "$action" in
  add)
    from_word="${2:-}"
    to_word="${3:-}"
    if [[ -z "$from_word" || -z "$to_word" ]]; then
      echo "error: missing arguments"
      exit 1
    fi
    python3 - "$CORRECTIONS_FILE" "$from_word" "$to_word" <<'PY'
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

corrections_file.parent.mkdir(parents=True, exist_ok=True)
corrections_file.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
if updated:
    print(f"已更新：{from_word} -> {to_word}（共 {len(data)} 條）")
else:
    print(f"已新增：{from_word} -> {to_word}（共 {len(data)} 條）")
PY
    ;;

  list)
    python3 - "$CORRECTIONS_FILE" <<'PY'
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
    ;;

  remove)
    from_word="${2:-}"
    if [[ -z "$from_word" ]]; then
      echo "error: missing word to remove"
      exit 1
    fi
    python3 - "$CORRECTIONS_FILE" "$from_word" <<'PY'
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
if len(data) < before:
    print("removed")
else:
    print("not_found")
PY
    ;;

  *)
    echo "usage: $0 add <from> <to> | list | remove <from>"
    exit 2
    ;;
esac
