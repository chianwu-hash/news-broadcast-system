#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${1:-/home/vboxuser/news-broadcast-system}"
RUN_SCRIPT="$PROJECT_DIR/evening-news/run_evening_news.sh"
LOG_DIR="$PROJECT_DIR/evening-news/logs"
CRON_LOG_FILE="$LOG_DIR/cron.log"
CRON_MARKER="# news-broadcast-system evening-news"
CRON_LINE="0 16 * * * /usr/bin/env bash $RUN_SCRIPT >> $CRON_LOG_FILE 2>&1 $CRON_MARKER"

if [[ ! -f "$RUN_SCRIPT" ]]; then
  echo "[ERROR] run script not found: $RUN_SCRIPT"
  exit 1
fi

mkdir -p "$LOG_DIR"

tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

crontab -l 2>/dev/null | grep -v "$CRON_MARKER" > "$tmp_file" || true
echo "$CRON_LINE" >> "$tmp_file"
crontab "$tmp_file"

echo "[OK] installed evening-news cron schedule"
echo "      schedule: daily 16:00"
echo "      run script: $RUN_SCRIPT"
echo "      cron log: $CRON_LOG_FILE"
echo ""
echo "[INFO] current crontab:"
crontab -l | sed -n '1,200p'
