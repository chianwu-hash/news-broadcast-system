#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="/home/vboxuser/news-broadcast-system"
RUN_SCRIPT="$BASE_DIR/feature-news/run_feature_news.sh"
LOG_FILE="$BASE_DIR/feature-news/logs/openclaw-feature-bridge.log"

mkdir -p "$(dirname "$LOG_FILE")"

raw_input="${1:-}"
if [[ -z "$raw_input" ]]; then
  echo "usage: $0 '新聞專題：台積電赴美投資'" >&2
  exit 2
fi

topic=""
if [[ "$raw_input" =~ ^新聞專題[：:][[:space:]]*(.+)$ ]]; then
  topic="${BASH_REMATCH[1]}"
else
  echo "ignored: unsupported format" >&2
  exit 3
fi

topic="$(echo "$topic" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
if [[ -z "$topic" ]]; then
  echo "ignored: empty topic" >&2
  exit 4
fi

# Minimal hardening to avoid unsafe shell chars.
if echo "$topic" | grep -q '[`$\\]'; then
  echo "ignored: unsafe topic content" >&2
  exit 5
fi

if [[ ! -x "$RUN_SCRIPT" ]]; then
  chmod +x "$RUN_SCRIPT" || true
fi

ts="$(date '+%F %T')"
echo "$ts [INFO] bridge accepted topic=$topic" >> "$LOG_FILE"

nohup /bin/bash "$RUN_SCRIPT" "$topic" >> "$LOG_FILE" 2>&1 &
pid=$!

echo "$ts [INFO] bridge triggered pid=$pid topic=$topic" >> "$LOG_FILE"
echo "accepted: $topic"
echo "triggered_pid: $pid"
