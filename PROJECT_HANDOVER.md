# News Broadcast System - Project Handover

## 1. Current handover status

- All current project files have already been handed over into Cursor.
- The project directory has already been opened in Cursor.
- The next development stage will continue inside Cursor using ChatGPT-related tooling/modules.

---

## 2. Project purpose

This project is an automated AI news broadcast system.

Its goal is to:

1. search latest news
2. filter and clean results
3. use AI to select candidate news
4. use AI to write a broadcast script
5. convert script to speech
6. mix background music
7. send the final audio to Telegram

---

## 3. Program types

This repository is designed for three program types:

- morning-news
- evening-news
- feature-news

At this moment, the main implemented and tested pipeline is:

- morning-news

The other two program types are planned to reuse the same shared architecture.

---

## 4. Root directory

Project root:

```text
/home/vboxuser/news-broadcast-system
```

---

## 5. Current directory structure

```text
news-broadcast-system/
|
|- .env
|- .env.example
|- .gitignore
|- PROJECT_HANDOVER.md
|
|- common/
|   |- assets/
|   |   `- bgm/
|   |       |- morning.mp3
|   |       |- evening.mp3
|   |       `- feature.mp3
|   |
|   |- logs/
|   |- prompts/
|   |- config/
|   |- tmp/
|   `- scripts/
|       |- load_env.sh
|       |- common.sh
|       |- search_news.sh
|       |- select_candidates.sh
|       |- write_script.sh
|       |- generate_tts.sh
|       |- mix_audio.sh
|       `- send_telegram.sh
|
|- morning-news/
|   |- run_morning_news.sh
|   |- data/
|   |   `- history.json
|   |- logs/
|   |- output/
|   `- runs/
|
|- evening-news/
|   |- data/
|   |- logs/
|   |- output/
|   `- runs/
|
`- feature-news/
    |- data/
    |- logs/
    |- output/
    `- runs/
```

---

## 6. Current shared architecture

Shared logic is stored in:

```text
common/scripts/
```

Program-specific execution entry is stored in:

```text
morning-news/run_morning_news.sh
evening-news/run_evening_news.sh
feature-news/run_feature_news.sh
```

The design principle is:

- shared utility logic stays in `common/scripts/`
- program-specific orchestration stays in each program folder

---

## 7. Environment variable system

Configuration is managed through:

```text
.env
```

Important variables already used include:

```env
BRAVE_API_KEY=
DEEPSEEK_API_KEY=
DEEPSEEK_API_URL=
DEEPSEEK_MODEL=
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=

BASE_DIR=/home/vboxuser/news-broadcast-system

DEFAULT_TTS_VOICE=zh-TW-HsiaoChenNeural
EDGE_TTS_PYTHON=python3
EDGE_TTS_MODULE=edge_tts

BRAVE_SEARCH_ENDPOINT=https://api.search.brave.com/res/v1/web/search
BRAVE_SEARCH_FRESHNESS=pd
BRAVE_SEARCH_COUNTRY=TW
BRAVE_SEARCH_LANG=zh-hant
BRAVE_SEARCH_COUNT=10

NEWS_URL_BLACKLIST_PATTERNS="/talk/|/opinion/|/commentary/|/forum/|/column/|/blog/|/search/|/live/|/video/|youtube\\.com|youtu\\.be"
NEWS_SOURCE_BLACKLIST="Newtalk Opinion,Forum,Commentary,YouTube,PChome Online 新聞,Cmoney"
NEWS_EXACT_URL_BLACKLIST_PATTERNS="https://www.storm.mg|https://www.reuters.com/|https://www.reuters.com/live/|https://www.reuters.com/business/|https://www.chinatimes.com/realtimenews/|https://www.chinatimes.com/world/total"
MIN_NEWS_TITLE_LENGTH=12
```

Morning-news specific variables include:

```env
MORNING_DIR=/home/vboxuser/news-broadcast-system/morning-news
MORNING_DATA_DIR=/home/vboxuser/news-broadcast-system/morning-news/data
MORNING_OUTPUT_DIR=/home/vboxuser/news-broadcast-system/morning-news/output
MORNING_RUNS_DIR=/home/vboxuser/news-broadcast-system/morning-news/runs
MORNING_LOG_DIR=/home/vboxuser/news-broadcast-system/morning-news/logs

MORNING_HISTORY_FILE=/home/vboxuser/news-broadcast-system/morning-news/data/history.json
MORNING_SCRIPT_FILE=/home/vboxuser/news-broadcast-system/morning-news/output/script.txt
MORNING_VOICE_FILE=/home/vboxuser/news-broadcast-system/morning-news/output/voice.mp3
MORNING_FINAL_AUDIO_FILE=/home/vboxuser/news-broadcast-system/morning-news/output/news.mp3
MORNING_CANDIDATES_FILE=/home/vboxuser/news-broadcast-system/morning-news/output/candidates.json
MORNING_SELECTED_FILE=/home/vboxuser/news-broadcast-system/morning-news/output/selected.json
MORNING_LOG_FILE=/home/vboxuser/news-broadcast-system/morning-news/logs/morning-news.log
MORNING_BGM_FILE=/home/vboxuser/news-broadcast-system/common/assets/bgm/morning.mp3
MORNING_TTS_VOICE=zh-TW-HsiaoChenNeural
MORNING_NEWS_COUNT=8
MORNING_CANDIDATE_COUNT=15
MORNING_SCRIPT_TARGET_CHARS=2000
MORNING_STYLE_NAME=小蝦
MORNING_TAIWAN_NEWS_COUNT=5
MORNING_WORLD_NEWS_COUNT=3
MORNING_SCRIPT_TONE="podcast聊天風、清楚、自然、適合口語播報"
```

---

## 8. Current working pipeline

The current working morning-news pipeline is:

```text
search_news
-> select_candidates
-> write_script
-> generate_tts
-> mix_audio
-> send_telegram_audio
```

This pipeline is orchestrated in:

```text
morning-news/run_morning_news.sh
```

---

## 9. Current script responsibilities

### load_env.sh

Purpose:

- load `.env`
- validate required environment variables
- map program mode (`morning`, `evening`, `feature`) to runtime variables such as:
  - `PROGRAM_NAME`
  - `OUTPUT_DIR`
  - `LOG_FILE`
  - `SCRIPT_FILE`
  - `VOICE_FILE`
  - `FINAL_AUDIO_FILE`
  - `BGM_FILE`

---

### common.sh

Purpose:

- provide shared helper functions such as:
  - `log`
  - `die`

---

### search_news.sh

Purpose:

- call Brave Search API
- run multiple news queries depending on program type
- save raw results

Output:

```text
output/raw_search_results.json
```

For morning-news, current query set includes 6 queries such as:

- 台灣 即時新聞
- 台灣 政治 最新
- 台灣 財經 最新
- 台灣 社會 新聞
- 國際新聞 最新 中文
- international breaking news

---

### select_candidates.sh

Purpose:

1. clean raw search results
2. filter bad URLs and bad sources
3. remove non-article pages
4. remove duplicates
5. call DeepSeek to select candidate news

Outputs:

```text
output/prepared_search_items.json
output/candidates.json
```

Current filtering logic is implemented inside:

```text
prepare_candidate_input()
```

Current filtering goals include removing:

- homepage URLs
- category pages
- search pages
- commentary pages
- live pages
- video pages
- YouTube links
- duplicates
- obvious non-article pages
- blacklisted sources

`prepared_search_items.json` now also contains:

```json
"filter_stats": {
  "raw_count": 0,
  "kept_count": 0,
  "filtered_short_title": 0,
  "filtered_bad_url": 0,
  "filtered_bad_source": 0,
  "filtered_non_article": 0,
  "filtered_duplicate": 0
}
```

---

### write_script.sh

Purpose:

- read `candidates.json`
- use AI to choose final selected news
- generate final script for broadcast

Outputs:

```text
output/selected.json
output/script.txt
```

This is currently a combined step:

- final selection
- script writing

These are not yet separated into different scripts.

---

### generate_tts.sh

Purpose:

- convert `script.txt` into speech audio

Current implementation uses:

```bash
python3 -m edge_tts
```

because direct shell commands like `edge_tts` / `edge-tts` were not reliably in PATH.

Output:

```text
output/voice.mp3
```

---

### mix_audio.sh

Purpose:

- mix generated voice with background music using ffmpeg

Inputs:

- `voice.mp3`
- program-specific BGM

Output:

```text
output/news.mp3
```

---

### send_telegram.sh

Purpose:

- send final mixed audio to Telegram Bot API

Input:

```text
output/news.mp3
```

Result:

- final audio is delivered to the configured Telegram chat successfully

---

## 10. Current execution status

The morning-news pipeline has already been tested successfully end-to-end.

Verified working steps:

- load `.env`
- search news from Brave Search
- filter raw news items
- select candidates via DeepSeek
- generate selected news + script via DeepSeek
- generate TTS audio
- mix background music
- send final audio to Telegram

This means the project is no longer only a skeleton.
It is already a working first-version automated pipeline.

---

## 11. Current known issues / quality concerns

The system runs successfully, but content quality still needs improvement.

Known remaining concerns:

1. some candidate results may still include weak-quality sources
2. same global event can still appear in multiple selected items
3. script style is usable, but still somewhat templated
4. source quality control still needs stronger refinement
5. Chinese polyphone mispronunciation in TTS (e.g. 院長、重要、銀行) — fix in progress

---

## 12. Most recent major improvements already completed

The following upgrades were recently completed:

- `.env` separation from scripts
- shared runtime loader via `load_env.sh`
- shared logging via `common.sh`
- flock-based duplicate-run prevention in main entry script
- Brave Search integration
- DeepSeek candidate selection
- DeepSeek final selection + script generation
- Edge TTS integration
- FFmpeg audio mixing
- Telegram delivery
- candidate pre-filtering logic
- filter statistics in prepared news output
- news freshness filtering (`NEWS_MAX_AGE_DAYS`)
- history-based deduplication (`HISTORY_LOOKBACK_DAYS`, `history.json`)
- AI event clustering via DeepSeek (`cluster_events_ai`)
- Git repository initialized and synced between Windows (local) and VM (remote)

---

## 13. Important development principles

When continuing this project, preserve these principles:

1. do not break the current pipeline order
2. keep shared logic in `common/scripts/`
3. keep program-specific orchestration in each program directory
4. keep `.env` as the main configuration layer
5. filtering should happen before AI candidate selection
6. avoid introducing unnecessary heavy frameworks
7. prefer Bash + Python standard library + curl
8. avoid rewriting the whole project unless necessary

---

## 14. Immediate next recommended tasks

### Priority 1 - Chinese polyphone fix (TTS pre-processor)

**Status: in progress**

The TTS (edge-tts, `zh-TW-HsiaoChenNeural`) mispronounces polyphone characters such as:
- 院長 reads 長 as ㄔㄤˊ instead of ㄓㄤˇ
- 重要 reads 重 as ㄔㄨㄥˊ instead of ㄓㄨㄥˋ
- 銀行 reads 行 as ㄒㄧㄥˊ instead of ㄏㄤˊ

Planned fix: a pre-processor script that runs before edge-tts:
1. Uses jieba for word segmentation
2. Uses pypinyin to determine correct reading in context
3. Replaces polyphone characters with unambiguous homophone substitutes

Example substitutions:
- 院長 → 院掌 (掌 only reads ㄓㄤˇ)
- 重要 → 仲要 (仲 only reads ㄓㄨㄥˋ)
- 銀行 → 銀航 (航 only reads ㄏㄤˊ)

Planned file: common/scripts/normalize_tts_text.py
Called inside generate_tts.sh before the edge-tts call.

Polyphone reference sources:
- pypinyin + jieba (already installed on VM)
- MoE 教育部重編國語辭典 open data (most authoritative for zh-TW)
- mozillazg/phrase-pinyin-data (source data used by pypinyin)

IMPORTANT: generate_tts.sh currently uses Azure TTS REST API.
It must be reverted to edge-tts before the polyphone pre-processor is added.
The Azure TTS key/region remain in .env and load_env.sh for potential future use.

---

### Priority 2 - stronger source quality control

Improve source allow/deny logic and reduce low-value aggregated pages.

### Priority 3 - style refinement

Make the generated script sound more natural and less templated.

### Priority 4 - extend the same architecture to:

- evening-news
- feature-news

---

## 15. Notes for Cursor / ChatGPT agent

Before editing code:

- read this file first
- inspect current shell scripts before rewriting
- do not assume the project is incomplete: many parts already work
- prefer incremental upgrades over large rewrites
- preserve JSON compatibility between pipeline stages

Suggested editing style:

- modify one module at a time
- keep outputs stable
- keep existing filenames unless there is a strong reason to change them

---

## 16. Development environment

- VM (VirtualBox): vboxuser@192.168.50.138
- VM project root: /home/vboxuser/news-broadcast-system
- Windows local: e:\shared\news-broadcast-system
- Git remote: vboxuser@192.168.50.138:/home/vboxuser/news-broadcast-system
- Git push to VM: receive.denyCurrentBranch=updateInstead (already configured)
- Workflow: edit on Windows, git push to VM, run scripts on VM

---

## 17. TTS investigation summary (2026-03)

### edge-tts (current, to be kept)

- Free, uses Microsoft Edge browser read-aloud endpoint
- Does NOT support any SSML tags — phoneme, break, prosody all return NoAudioReceived
- Known polyphone mispronunciations: 院長、重要、重啟、銀行 etc.

### Azure TTS (tested, credentials stored, NOT used in production)

- REST API endpoint: https://{AZURE_SPEECH_REGION}.tts.speech.microsoft.com/cognitiveservices/v1
- Credentials: AZURE_SPEECH_KEY, AZURE_SPEECH_REGION in .env
- Supports break and prosody tags; does NOT support phoneme for zh-TW voices
- Voice quality similar to edge-tts; free tier 500k chars/month
- generate_tts.sh was temporarily rewritten for Azure — must be reverted to edge-tts
- text_to_ssml.py was added for Azure SSML generation — can be removed or kept for reference

### Polyphone fix plan (next task)

- Approach: plain text substitution before edge-tts
- Replace polyphone characters with unambiguous homophones in the same word context
- Example: 院長→院掌, 重要→仲要, 銀行→銀航
- Implementation: common/scripts/normalize_tts_text.py
- Method: jieba word segmentation + pypinyin context-aware pinyin → auto-detect and substitute
- Both jieba and pypinyin are already installed on VM
