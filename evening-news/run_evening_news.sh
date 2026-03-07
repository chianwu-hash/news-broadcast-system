#!/usr/bin/env bash
set -Eeuo pipefail

source /home/vboxuser/news-broadcast-system/common/scripts/load_env.sh evening
source /home/vboxuser/news-broadcast-system/common/scripts/common.sh

LOCK_FILE="/tmp/news_broadcast_evening.lock"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "$(date '+%F %T') [ERROR] evening-news is already running"
  exit 1
fi

START_TS=$(date +%s)

on_error() {
  local exit_code=$?
  local line_no=$1
  log ERROR "script failed at line $line_no with exit code $exit_code"
  exit "$exit_code"
}
trap 'on_error $LINENO' ERR

log INFO "========================================"
log INFO "evening-news started"
log INFO "PROGRAM_NAME=$PROGRAM_NAME"
log INFO "LOG_FILE=$LOG_FILE"
log INFO "HISTORY_FILE=$HISTORY_FILE"
log INFO "SCRIPT_FILE=$SCRIPT_FILE"
log INFO "FINAL_AUDIO_FILE=$FINAL_AUDIO_FILE"
log INFO "BGM_FILE=$BGM_FILE"
log INFO "TTS_VOICE=$TTS_VOICE"
log INFO "NEWS_COUNT=$NEWS_COUNT"
log INFO "CANDIDATE_COUNT=$CANDIDATE_COUNT"
log INFO "SCRIPT_TARGET_CHARS=$SCRIPT_TARGET_CHARS"

log INFO "step=search_news start"
sleep 1
log INFO "step=search_news done"

log INFO "step=select_candidates start"
sleep 1
log INFO "step=select_candidates done"

log INFO "step=verify_news start"
sleep 1
log INFO "step=verify_news done"

log INFO "step=write_script start"
sleep 1
log INFO "step=write_script done"

log INFO "step=tts start"
sleep 1
log INFO "step=tts done"

log INFO "step=mix_audio start"
sleep 1
log INFO "step=mix_audio done"

log INFO "step=send_telegram start"
sleep 1
log INFO "step=send_telegram done"

END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
log INFO "evening-news finished in ${DURATION}s"
log INFO "========================================"
