#!/usr/bin/env bash
# 測試 Azure TTS 語速、音調、停頓及語音品質
set -euo pipefail
set -a; source /home/vboxuser/news-broadcast-system/.env; set +a

OUT_DIR="/home/vboxuser/news-broadcast-system/common/tmp"
ENDPOINT="https://${AZURE_SPEECH_REGION}.tts.speech.microsoft.com/cognitiveservices/v1"
VOICE="zh-TW-HsiaoChenNeural"

call_tts() {
  local label="$1" ssml_file="$2"
  local out="${OUT_DIR}/prosody_${label}.mp3"
  local http
  http=$(curl -sS -o "$out" -w "%{http_code}" \
    -X POST "$ENDPOINT" \
    -H "Ocp-Apim-Subscription-Key: $AZURE_SPEECH_KEY" \
    -H "Content-Type: application/ssml+xml" \
    -H "X-Microsoft-OutputFormat: audio-24khz-160kbitrate-mono-mp3" \
    --max-time 60 --data-binary @"$ssml_file")
  if [[ "$http" == "200" ]]; then
    echo "✅ [$label] $(ls -lh "$out" | awk '{print $5}')"
  else
    echo "❌ [$label] HTTP $http: $(cat "$out" | head -c 300)"
  fi
}

# ── 測試稿（含多音字、多段落）──────────────────────────────────
read -r -d '' BODY << 'EOF' || true
今天是重要的一天，歡迎收聽早安新聞。

首先，看台灣政治動態。行政院長在立法院備詢時強調，政府將積極推動能源轉型，大幅降低燃煤發電的比重，並以再生能源取而代之。院長表示，這項政策已獲得各部會的全力支持，預計三年內見到明顯成效。

接著看國際局勢。以色列與哈瑪斯的衝突仍在持續，聯合國秘書長對此表示高度關切，呼籲雙方儘速重啟和談，以和為貴，讓地區盡快恢復和平。分析師認為，外交斡旋若能成功，將對全球油價產生正面影響。

在財經方面，台積電今日股價再度創下新高，市場分析師指出，隨著人工智慧晶片需求持續大增，半導體廠商的獲利預計將大幅成長。銀行業者也表示，企業融資需求明顯增加，整體景氣正在好轉。

最後是好消息。台中市一名長者在山中迷路三天後順利獲救，救難人員表示，長者身體狀況尚稱穩定，家屬得知消息後激動落淚。教練帶領球隊延長賽逆轉勝，全場觀眾起立歡呼，為今天畫下完美句點。

以上是今天的早安新聞，感謝您的收聽，我們明天同一時間再會。
EOF

# 函式：把測試稿包成 SSML
make_ssml() {
  local rate="$1" pitch="$2" file="$3"
  cat > "$file" << SSML
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="zh-TW">
  <voice name="${VOICE}">
    <prosody rate="${rate}" pitch="${pitch}">
$(echo "$BODY" \
  | sed 's/院長/院掌/g' \
  | sed 's/重要/仲要/g' \
  | sed 's/重啟/崇啟/g' \
  | sed 's/成長/成掌/g' \
  | sed 's/延長賽/延長ㄕㄟ/g' \
  | sed 's/銀行/銀航/g' \
  | python3 -c "
import sys, re
from xml.sax.saxutils import escape
text = sys.stdin.read()
# 段落分隔加 break
paras = [p.strip() for p in re.split(r'\n{2,}', text) if p.strip()]
parts = []
for i, p in enumerate(paras):
    if i > 0:
        parts.append('<break time=\"700ms\"/>')
    # 句末加短停頓
    p = re.sub(r'([。！？])', lambda m: escape(m.group(1)) + '<break time=\"300ms\"/>', escape(p))
    parts.append(p)
print('\n    '.join(parts))
")
    </prosody>
  </voice>
</speak>
SSML
}

mkdir -p "$OUT_DIR"

echo "=============================="
echo "Azure TTS 語速 / 音調 測試"
echo "=============================="

# 1. 預設（baseline）
make_ssml "+0%" "+0Hz" /tmp/ssml_default.ssml
call_tts "1_default" /tmp/ssml_default.ssml

# 2. 稍慢 -10%（新聞播報感）
make_ssml "-10%" "+0Hz" /tmp/ssml_slow.ssml
call_tts "2_rate_minus10" /tmp/ssml_slow.ssml

# 3. 稍快 +10%
make_ssml "+10%" "+0Hz" /tmp/ssml_fast.ssml
call_tts "3_rate_plus10" /tmp/ssml_fast.ssml

# 4. 音調低 -2Hz（較沉穩）
make_ssml "+0%" "-2Hz" /tmp/ssml_low.ssml
call_tts "4_pitch_low" /tmp/ssml_low.ssml

# 5. 語速-10% + 音調-2Hz（推薦播報設定）
make_ssml "-10%" "-2Hz" /tmp/ssml_recommended.ssml
call_tts "5_recommended" /tmp/ssml_recommended.ssml

echo ""
echo "輸出目錄：$OUT_DIR"
echo "檔案列表："
ls -lh "${OUT_DIR}"/prosody_*.mp3 2>/dev/null
