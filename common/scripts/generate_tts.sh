#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] generate_tts.sh 必須用 source 載入，不能直接執行"
  exit 1
fi

generate_tts() {
  log INFO "step=tts start"

  if [[ ! -f "$SCRIPT_FILE" ]]; then
    die "script file not found: $SCRIPT_FILE"
  fi

  if [[ ! -s "$SCRIPT_FILE" ]]; then
    die "script file is empty: $SCRIPT_FILE"
  fi

  mkdir -p "$(dirname "$VOICE_FILE")"

  local ssml_file="$COMMON_TMP_DIR/${PROGRAM_NAME}_tts.ssml"
  local tts_timeout="${AZURE_TTS_TIMEOUT:-60}"

  # ── Step 1：文字 → SSML（含多音字 phoneme 標籤）
  python3 "$(dirname "${BASH_SOURCE[0]}")/text_to_ssml.py" \
    "$SCRIPT_FILE" \
    "$ssml_file" \
    "$TTS_VOICE"

  if [[ ! -f "$ssml_file" || ! -s "$ssml_file" ]]; then
    die "step=tts ssml generation failed: $ssml_file"
  fi

  # ── Step 2：SSML → Azure TTS → voice.mp3
  local azure_endpoint="https://${AZURE_SPEECH_REGION}.tts.speech.microsoft.com/cognitiveservices/v1"
  local http_code

  http_code="$(curl -sS \
    -o "$VOICE_FILE" \
    -w "%{http_code}" \
    -X POST "$azure_endpoint" \
    -H "Ocp-Apim-Subscription-Key: $AZURE_SPEECH_KEY" \
    -H "Content-Type: application/ssml+xml" \
    -H "X-Microsoft-OutputFormat: audio-24khz-160kbitrate-mono-mp3" \
    --max-time "$tts_timeout" \
    --data-binary @"$ssml_file")"

  if [[ "$http_code" != "200" ]]; then
    # 印出錯誤回應內容輔助診斷
    local err_body=""
    err_body=$(cat "$VOICE_FILE" 2>/dev/null || true)
    die "step=tts azure api failed http=$http_code body=${err_body:0:200}"
  fi

  if [[ ! -f "$VOICE_FILE" || ! -s "$VOICE_FILE" ]]; then
    die "step=tts voice file not generated: $VOICE_FILE"
  fi

  local voice_size
  voice_size=$(stat -c%s "$VOICE_FILE" 2>/dev/null || echo 0)

  log INFO "step=tts done voice_file=$VOICE_FILE size_bytes=$voice_size"
}
