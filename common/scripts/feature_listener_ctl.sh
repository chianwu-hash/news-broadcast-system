#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="/home/vboxuser/news-broadcast-system"
LISTENER_SCRIPT="$BASE_DIR/common/scripts/telegram_feature_listener.sh"
PID_FILE="$BASE_DIR/feature-news/runs/telegram_feature_listener.pid"
LOG_FILE="$BASE_DIR/feature-news/logs/telegram_feature_listener.log"

cmd="${1:-status}"

is_running() {
  if [[ ! -f "$PID_FILE" ]]; then
    return 1
  fi
  pid="$(cat "$PID_FILE" 2>/dev/null || echo "")"
  [[ -n "$pid" ]] || return 1
  kill -0 "$pid" 2>/dev/null
}

case "$cmd" in
  start)
    if is_running; then
      echo "[INFO] listener already running pid=$(cat "$PID_FILE")"
      exit 0
    fi
    mkdir -p "$(dirname "$PID_FILE")" "$(dirname "$LOG_FILE")"
    nohup /bin/bash "$LISTENER_SCRIPT" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    echo "[OK] listener started pid=$!"
    ;;
  stop)
    if ! is_running; then
      echo "[INFO] listener not running"
      rm -f "$PID_FILE"
      exit 0
    fi
    pid="$(cat "$PID_FILE")"
    kill "$pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "[OK] listener stopped pid=$pid"
    ;;
  restart)
    "$0" stop
    "$0" start
    ;;
  once)
    /bin/bash "$LISTENER_SCRIPT" --once
    ;;
  status)
    if is_running; then
      echo "[INFO] listener running pid=$(cat "$PID_FILE")"
    else
      echo "[INFO] listener not running"
    fi
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status|once}"
    exit 1
    ;;
esac
