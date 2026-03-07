#!/usr/bin/env bash
set -a; source /home/vboxuser/news-broadcast-system/.env; set +a

OUT_DIR="/home/vboxuser/news-broadcast-system/common/tmp"
ENDPOINT="https://${AZURE_SPEECH_REGION}.tts.speech.microsoft.com/cognitiveservices/v1"
SAMPLE="今天是重要的一天，歡迎收聽早安新聞。行政院掌在立法院備詢時強調，政府將積極推動能源轉型，大幅降低燃煤發電的比重。仲要的是，這項政策已獲得各部會的全力支持。"

call() {
  local label="$1" ssml_file="$2"
  local out="${OUT_DIR}/style_${label}.mp3"
  local http
  http=$(curl -sS -o "$out" -w "%{http_code}" \
    -X POST "$ENDPOINT" \
    -H "Ocp-Apim-Subscription-Key: $AZURE_SPEECH_KEY" \
    -H "Content-Type: application/ssml+xml" \
    -H "X-Microsoft-OutputFormat: audio-24khz-160kbitrate-mono-mp3" \
    --max-time 30 --data-binary @"$ssml_file")
  if [[ "$http" == "200" ]]; then
    echo "✅ [$label] $(ls -lh "$out" | awk '{print $5}')"
  else
    echo "❌ [$label] HTTP $http"
  fi
}

make_style_ssml() {
  local style="$1" file="$2"
  cat > "$file" << EOF
<speak version="1.0"
  xmlns="http://www.w3.org/2001/10/synthesis"
  xmlns:mstts="https://www.w3.org/2001/mstts"
  xml:lang="zh-TW">
  <voice name="zh-TW-HsiaoChenNeural">
    <mstts:express-as style="${style}">
      ${SAMPLE}
    </mstts:express-as>
  </voice>
</speak>
EOF
}

mkdir -p "$OUT_DIR"
echo "測試 HsiaoChenNeural 說話風格支援..."

for style in chat cheerful newscast customerservice gentle calm; do
  make_style_ssml "$style" /tmp/style_test.ssml
  call "$style" /tmp/style_test.ssml
done
