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

  "${EDGE_TTS_PYTHON:-python3}" -m "${EDGE_TTS_MODULE:-edge_tts}" \
    --voice "$TTS_VOICE" \
    --file "$SCRIPT_FILE" \
    --write-media "$VOICE_FILE"

  if [[ ! -f "$VOICE_FILE" || ! -s "$VOICE_FILE" ]]; then
    die "tts failed: voice file not generated: $VOICE_FILE"
  fi

  local voice_size
  voice_size=$(stat -c%s "$VOICE_FILE" 2>/dev/null || echo 0)

  log INFO "step=tts done voice_file=$VOICE_FILE size_bytes=$voice_size"
}
