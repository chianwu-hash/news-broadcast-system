#!/usr/bin/env bash

log() {
  local level="$1"
  local message="$2"
  local ts
  ts="$(date '+%F %T')"

  if [[ -n "${LOG_FILE:-}" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "$ts [$level] $message" | tee -a "$LOG_FILE"
  else
    echo "$ts [$level] $message"
  fi
}

die() {
  local message="$1"
  log ERROR "$message"
  exit 1
}
