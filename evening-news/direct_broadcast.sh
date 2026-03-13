#!/usr/bin/env bash
set -Eeuo pipefail

# 載入環境變數
source /home/vboxuser/news-broadcast-system/common/scripts/load_env.sh evening

# 設定變數
SCRIPT_FILE="/home/vboxuser/news-broadcast-system/evening-news/output/script.txt"
VOICE_FILE="/home/vboxuser/news-broadcast-system/evening-news/output/voice.mp3"
FINAL_AUDIO_FILE="/home/vboxuser/news-broadcast-system/evening-news/output/news.mp3"
BGM_FILE="/home/vboxuser/news-broadcast-system/common/assets/bgm/evening.mp3"

# 檢查新聞稿是否存在
if [[ ! -f "$SCRIPT_FILE" ]]; then
    echo "錯誤：新聞稿檔案不存在: $SCRIPT_FILE"
    exit 1
fi

echo "開始晚間新聞播報..."
echo "使用新聞稿: $SCRIPT_FILE"

# 刪除舊的語音檔案
echo "刪除舊的語音檔案..."
rm -f "$VOICE_FILE" "$FINAL_AUDIO_FILE"

# 直接使用 edge-tts 生成語音（跳過正規化）
echo "直接生成語音..."
cd /home/vboxuser/news-broadcast-system/evening-news
python3 -m edge_tts --voice zh-TW-HsiaoChenNeural --file "$SCRIPT_FILE" --write-media "$VOICE_FILE"

# 檢查語音檔案是否生成
if [[ ! -f "$VOICE_FILE" ]]; then
    echo "錯誤：語音檔案生成失敗"
    exit 1
fi

echo "語音檔案已生成: $VOICE_FILE ($(du -h "$VOICE_FILE" | cut -f1))"

# 混音（加入背景音樂）
echo "混音（加入背景音樂）..."
if [[ -f "$BGM_FILE" ]]; then
    # 使用 ffmpeg 混音
    ffmpeg -y \
      -i "$VOICE_FILE" \
      -i "$BGM_FILE" \
      -filter_complex "[0:a]volume=1.0[a1];[1:a]volume=0.3,aloop=loop=-1:size=2e+09[a2];[a1][a2]amix=inputs=2:duration=longest" \
      -c:a libmp3lame \
      -q:a 2 \
      "$FINAL_AUDIO_FILE" 2>/dev/null
    
    if [[ ! -f "$FINAL_AUDIO_FILE" ]]; then
        echo "警告：混音失敗，使用原始語音檔案"
        cp "$VOICE_FILE" "$FINAL_AUDIO_FILE"
    fi
else
    echo "警告：背景音樂檔案不存在，使用原始語音檔案"
    cp "$VOICE_FILE" "$FINAL_AUDIO_FILE"
fi

echo "最終音頻檔案已生成: $FINAL_AUDIO_FILE ($(du -h "$FINAL_AUDIO_FILE" | cut -f1))"

# 發送到Telegram
echo "發送到Telegram..."
if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
    # 發送音頻檔案
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendAudio" \
      -F "chat_id=${TELEGRAM_CHAT_ID}" \
      -F "audio=@${FINAL_AUDIO_FILE}" \
      -F "title=晚間新聞 $(date '+%Y-%m-%d %H:%M')" \
      -F "caption=晚間新聞播報完成！" \
      -F "parse_mode=Markdown"
    echo ""
    echo "音頻已發送到Telegram"
else
    echo "錯誤：Telegram 設定不完整"
fi

echo "晚間新聞播報完成！"
echo "新聞稿內容預覽："
head -3 "$SCRIPT_FILE"