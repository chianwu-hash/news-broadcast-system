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

# 生成語音
echo "生成語音..."
source /home/vboxuser/news-broadcast-system/common/scripts/generate_tts.sh

# 混音（加入背景音樂）
echo "混音（加入背景音樂）..."
source /home/vboxuser/news-broadcast-system/common/scripts/mix_audio.sh

# 發送到Telegram
echo "發送到Telegram..."
source /home/vboxuser/news-broadcast-system/common/scripts/send_telegram.sh

echo "晚間新聞播報完成！"