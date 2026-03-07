#!/usr/bin/env bash
set -a; source /home/vboxuser/news-broadcast-system/.env; set +a

call_tts() {
  local label="$1"
  local ssml="$2"
  local out="/tmp/ph_test_${label}.mp3"
  local http
  http=$(echo "$ssml" | curl -sS \
    -o "$out" -w "%{http_code}" \
    -X POST "https://${AZURE_SPEECH_REGION}.tts.speech.microsoft.com/cognitiveservices/v1" \
    -H "Ocp-Apim-Subscription-Key: $AZURE_SPEECH_KEY" \
    -H "Content-Type: application/ssml+xml" \
    -H "X-Microsoft-OutputFormat: audio-24khz-160kbitrate-mono-mp3" \
    --max-time 30 --data-binary @-)
  if [[ "$http" == "200" ]]; then
    echo "✅ [$label] HTTP $http $(ls -lh "$out" | awk '{print $5}')"
  else
    echo "❌ [$label] HTTP $http: $(cat "$out" 2>/dev/null)"
  fi
}

# 測試 1：bopo phoneme
call_tts "bopo" '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="zh-TW"><voice name="zh-TW-HsiaoChenNeural">今天是<phoneme alphabet="bopo" ph="ㄓㄨㄥˋ">重</phoneme>要的一天。</voice></speak>'

# 測試 2：pinyin phoneme
call_tts "pinyin" '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="zh-TW"><voice name="zh-TW-HsiaoChenNeural">今天是<phoneme alphabet="zh-latn-pinyin" ph="zhòng">重</phoneme>要的一天。</voice></speak>'

# 測試 3：ipa phoneme
call_tts "ipa" '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="zh-TW"><voice name="zh-TW-HsiaoChenNeural">今天是<phoneme alphabet="ipa" ph="ʈʂʊŋ˥˩">重</phoneme>要的一天。</voice></speak>'
