#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="/home/vboxuser/news-broadcast-system"
ENV_FILE="$BASE_DIR/.env"

ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
err() { echo "[ERROR] $1"; }

check_cmd() {
  local c="$1"
  if command -v "$c" >/dev/null 2>&1; then
    ok "command found: $c ($(command -v "$c"))"
  else
    err "command missing: $c"
    return 1
  fi
}

check_env_key() {
  local k="$1"
  if [[ -n "${!k:-}" ]]; then
    ok "env set: $k"
  else
    err "env missing: $k"
    return 1
  fi
}

echo "== doctor: news-broadcast-system =="

if [[ ! -f "$ENV_FILE" ]]; then
  err ".env not found: $ENV_FILE"
  exit 1
fi
ok ".env found: $ENV_FILE"

set -a
source "$ENV_FILE"
set +a

fail=0

check_cmd bash || fail=1
check_cmd python3 || fail=1
check_cmd curl || fail=1
check_cmd ffmpeg || fail=1
check_cmd flock || fail=1

check_env_key BRAVE_API_KEY || fail=1
check_env_key DEEPSEEK_API_KEY || fail=1
check_env_key DEEPSEEK_API_URL || fail=1
check_env_key DEEPSEEK_MODEL || fail=1
check_env_key TELEGRAM_BOT_TOKEN || fail=1
check_env_key TELEGRAM_CHAT_ID || fail=1

if [[ -f "${MORNING_BGM_FILE:-}" ]]; then
  ok "morning bgm found: ${MORNING_BGM_FILE}"
else
  err "morning bgm missing: ${MORNING_BGM_FILE:-<empty>}"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "doctor result: PASS"
else
  echo "doctor result: FAIL"
  exit 1
fi
