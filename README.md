# News Broadcast System

包含三種新聞播報模組：

1. morning-news（早安新聞）
2. evening-news（晚安新聞）
3. feature-news（新聞專題）

## 目錄原則

- common/: 共用設定、prompt、資源、腳本
- 各模組目錄: 各自的 data / output / runs / logs

## Development Workflow (Windows + VM)

This project is edited on Windows (Cursor/ChatGPT extension) and executed inside Ubuntu VM.

### Rules

1. VM path is the source of truth:
   - `/home/vboxuser/news-broadcast-system`
2. Run scripts and tests in VM only (bash/python3/curl/ffmpeg/flock environment).
3. Keep shell scripts in LF line endings.
4. Run preflight check before pipeline:
   - `common/scripts/doctor.sh`
5. Commit small, incremental changes with clear messages.

### Quick Start (VM)

```bash
cd /home/vboxuser/news-broadcast-system
common/scripts/doctor.sh
bash morning-news/run_morning_news.sh

Git Hygiene
Runtime outputs/logs are ignored by .gitignore.
Keep .env untracked, update .env.example when adding new env keys.
