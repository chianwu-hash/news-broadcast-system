#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "[ERROR] mix_audio.sh 必須用 source 載入，不能直接執行"
  exit 1
fi

mix_audio() {
  log INFO "step=mix_audio start"

  if [[ ! -f "$VOICE_FILE" ]]; then
    die "voice file not found: $VOICE_FILE"
  fi

  if [[ ! -s "$VOICE_FILE" ]]; then
    die "voice file is empty: $VOICE_FILE"
  fi

  if [[ ! -f "$BGM_FILE" ]]; then
    die "bgm file not found: $BGM_FILE"
  fi

  if [[ ! -s "$BGM_FILE" ]]; then
    die "bgm file is empty: $BGM_FILE"
  fi

  mkdir -p "$(dirname "$FINAL_AUDIO_FILE")"

  ffmpeg -y \
    -stream_loop -1 -i "$BGM_FILE" \
    -i "$VOICE_FILE" \
    -filter_complex "\
[0:a]volume=0.08,afade=t=in:st=0:d=2[bgm]; \
[1:a]volume=1.0[voice]; \
[bgm][voice]amix=inputs=2:duration=shortest:dropout_transition=2[aout]" \
    -map "[aout]" \
    -c:a mp3 \
    -b:a 192k \
    "$FINAL_AUDIO_FILE" \
    >/dev/null 2>&1

  if [[ ! -f "$FINAL_AUDIO_FILE" || ! -s "$FINAL_AUDIO_FILE" ]]; then
    die "mixing failed: final audio not generated: $FINAL_AUDIO_FILE"
  fi

  local final_size
  final_size=$(stat -c%s "$FINAL_AUDIO_FILE" 2>/dev/null || echo 0)

  log INFO "step=mix_audio done final_audio=$FINAL_AUDIO_FILE size_bytes=$final_size"
}
