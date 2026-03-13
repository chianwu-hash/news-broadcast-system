#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] send_telegram.sh 必須用 source 載入，不能直接執行"
  exit 1
fi

send_telegram_audio() {
  log INFO "step=send_telegram start"

  if [[ ! -f "$FINAL_AUDIO_FILE" ]]; then
    die "final audio file not found: $FINAL_AUDIO_FILE"
  fi

  if [[ ! -s "$FINAL_AUDIO_FILE" ]]; then
    die "final audio file is empty: $FINAL_AUDIO_FILE"
  fi

  local caption
  caption="${PROGRAM_NAME} $(date '+%F %T')"

  local response
  response=$(curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendAudio" \
    -F chat_id="$TELEGRAM_CHAT_ID" \
    -F audio=@"$FINAL_AUDIO_FILE" \
    -F caption="$caption")

  if ! echo "$response" | grep -q '"ok":true'; then
    log ERROR "telegram response: $response"
    die "telegram send failed"
  fi

  log INFO "step=send_telegram done"
}

send_telegram_text() {
  local message="$1"
  local chat_id="${2:-${TELEGRAM_CHAT_ID:-}}"

  if [[ -z "$chat_id" ]]; then
    die "telegram chat_id is empty"
  fi

  local response
  response=$(curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$chat_id" \
    --data-urlencode text="$message")

  if ! echo "$response" | grep -q '"ok":true'; then
    log ERROR "telegram text response: $response"
    die "telegram send text failed"
  fi
}
