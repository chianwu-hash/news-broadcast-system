#!/usr/bin/env bash

# 用法：
# source /home/vboxuser/news-broadcast-system/common/scripts/load_env.sh morning
# source /home/vboxuser/news-broadcast-system/common/scripts/load_env.sh evening
# source /home/vboxuser/news-broadcast-system/common/scripts/load_env.sh feature

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] load_env.sh 必須用 source 載入，不能直接執行"
  exit 1
fi

PROGRAM_MODE="${1:-}"

BASE_DIR="/home/vboxuser/news-broadcast-system"
ENV_FILE="$BASE_DIR/.env"

if [[ -z "$PROGRAM_MODE" ]]; then
  echo "[ERROR] missing program mode: morning | evening | feature"
  return 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] .env not found: $ENV_FILE"
  return 1
fi

# 載入 .env
set -a
source "$ENV_FILE"
set +a

# ===== 共用必要欄位檢查 =====
required_common_vars=(
  BRAVE_API_KEY
  DEEPSEEK_API_KEY
  TELEGRAM_BOT_TOKEN
  TELEGRAM_CHAT_ID
  BASE_DIR
  DEFAULT_TTS_VOICE
)

for var in "${required_common_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "[ERROR] missing env var: $var"
    return 1
  fi
done

# ===== 依節目模式切換 =====
case "$PROGRAM_MODE" in
  morning)
    PROGRAM_NAME="morning-news"
    PROGRAM_DIR="$MORNING_DIR"
    DATA_DIR="$MORNING_DATA_DIR"
    OUTPUT_DIR="$MORNING_OUTPUT_DIR"
    RUNS_DIR="$MORNING_RUNS_DIR"
    PROGRAM_LOG_DIR="$MORNING_LOG_DIR"

    HISTORY_FILE="$MORNING_HISTORY_FILE"
    SCRIPT_FILE="$MORNING_SCRIPT_FILE"
    VOICE_FILE="$MORNING_VOICE_FILE"
    FINAL_AUDIO_FILE="$MORNING_FINAL_AUDIO_FILE"
    CANDIDATES_FILE="$MORNING_CANDIDATES_FILE"
    SELECTED_FILE="$MORNING_SELECTED_FILE"
    LOG_FILE="$MORNING_LOG_FILE"
    BGM_FILE="$MORNING_BGM_FILE"
    TTS_VOICE="${MORNING_TTS_VOICE:-$DEFAULT_TTS_VOICE}"
    NEWS_COUNT="$MORNING_NEWS_COUNT"
    CANDIDATE_COUNT="$MORNING_CANDIDATE_COUNT"
    SCRIPT_TARGET_CHARS="$MORNING_SCRIPT_TARGET_CHARS"
    ;;
  evening)
    PROGRAM_NAME="evening-news"
    PROGRAM_DIR="$EVENING_DIR"
    DATA_DIR="$EVENING_DATA_DIR"
    OUTPUT_DIR="$EVENING_OUTPUT_DIR"
    RUNS_DIR="$EVENING_RUNS_DIR"
    PROGRAM_LOG_DIR="$EVENING_LOG_DIR"

    HISTORY_FILE="$EVENING_HISTORY_FILE"
    SCRIPT_FILE="$EVENING_SCRIPT_FILE"
    VOICE_FILE="$EVENING_VOICE_FILE"
    FINAL_AUDIO_FILE="$EVENING_FINAL_AUDIO_FILE"
    CANDIDATES_FILE="$EVENING_CANDIDATES_FILE"
    SELECTED_FILE="$EVENING_SELECTED_FILE"
    LOG_FILE="$EVENING_LOG_FILE"
    BGM_FILE="$EVENING_BGM_FILE"
    TTS_VOICE="${EVENING_TTS_VOICE:-$DEFAULT_TTS_VOICE}"
    NEWS_COUNT="$EVENING_NEWS_COUNT"
    CANDIDATE_COUNT="$EVENING_CANDIDATE_COUNT"
    SCRIPT_TARGET_CHARS="$EVENING_SCRIPT_TARGET_CHARS"
    ;;
  feature)
    PROGRAM_NAME="feature-news"
    PROGRAM_DIR="$FEATURE_DIR"
    DATA_DIR="$FEATURE_DATA_DIR"
    OUTPUT_DIR="$FEATURE_OUTPUT_DIR"
    RUNS_DIR="$FEATURE_RUNS_DIR"
    PROGRAM_LOG_DIR="$FEATURE_LOG_DIR"

    HISTORY_FILE="$FEATURE_HISTORY_FILE"
    SCRIPT_FILE="$FEATURE_SCRIPT_FILE"
    VOICE_FILE="$FEATURE_VOICE_FILE"
    FINAL_AUDIO_FILE="$FEATURE_FINAL_AUDIO_FILE"
    CANDIDATES_FILE="$FEATURE_CANDIDATES_FILE"
    SELECTED_FILE="$FEATURE_SELECTED_FILE"
    LOG_FILE="$FEATURE_LOG_FILE"
    BGM_FILE="$FEATURE_BGM_FILE"
    TTS_VOICE="${FEATURE_TTS_VOICE:-$DEFAULT_TTS_VOICE}"
    NEWS_COUNT="$FEATURE_NEWS_COUNT"
    CANDIDATE_COUNT="$FEATURE_CANDIDATE_COUNT"
    SCRIPT_TARGET_CHARS="$FEATURE_SCRIPT_TARGET_CHARS"
    ;;
  *)
    echo "[ERROR] invalid program mode: $PROGRAM_MODE"
    echo "        allowed: morning | evening | feature"
    return 1
    ;;
esac

# ===== 節目模式必要欄位檢查 =====
required_program_vars=(
  PROGRAM_NAME
  PROGRAM_DIR
  DATA_DIR
  OUTPUT_DIR
  RUNS_DIR
  PROGRAM_LOG_DIR
  HISTORY_FILE
  SCRIPT_FILE
  VOICE_FILE
  FINAL_AUDIO_FILE
  CANDIDATES_FILE
  SELECTED_FILE
  LOG_FILE
  BGM_FILE
  TTS_VOICE
  NEWS_COUNT
  CANDIDATE_COUNT
  SCRIPT_TARGET_CHARS
)

for var in "${required_program_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "[ERROR] missing program env var: $var"
    return 1
  fi
done

# ===== 確保必要目錄存在 =====
mkdir -p "$COMMON_LOG_DIR" "$COMMON_TMP_DIR"
mkdir -p "$PROGRAM_DIR" "$DATA_DIR" "$OUTPUT_DIR" "$RUNS_DIR" "$PROGRAM_LOG_DIR"

# ===== 若 history.json 不存在就補空陣列 =====
if [[ ! -f "$HISTORY_FILE" ]]; then
  echo "[]" > "$HISTORY_FILE"
fi
