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

# 刪除舊的語音檔案以強制重新生成
echo "刪除舊的語音檔案..."
rm -f "$VOICE_FILE" "$FINAL_AUDIO_FILE"

# 生成語音
echo "生成語音..."
cd /home/vboxuser/news-broadcast-system/evening-news
source /home/vboxuser/news-broadcast-system/common/scripts/generate_tts.sh

# 檢查語音檔案是否生成
if [[ ! -f "$VOICE_FILE" ]]; then
    echo "錯誤：語音檔案生成失敗"
    exit 1
fi

echo "語音檔案已生成: $VOICE_FILE ($(du -h "$VOICE_FILE" | cut -f1))"

# 混音（加入背景音樂）
echo "混音（加入背景音樂）..."
source /home/vboxuser/news-broadcast-system/common/scripts/mix_audio.sh

# 檢查最終音頻檔案
if [[ ! -f "$FINAL_AUDIO_FILE" ]]; then
    echo "錯誤：最終音頻檔案生成失敗"
    exit 1
fi

echo "最終音頻檔案已生成: $FINAL_AUDIO_FILE ($(du -h "$FINAL_AUDIO_FILE" | cut -f1))"

# 發送到Telegram
echo "發送到Telegram..."
source /home/vboxuser/news-broadcast-system/common/scripts/send_telegram.sh

echo "晚間新聞播報完成！"
echo "新聞稿內容預覽："
head -5 "$SCRIPT_FILE"