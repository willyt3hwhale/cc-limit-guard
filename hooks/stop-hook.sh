#!/bin/bash

# Rate Limit Guard Stop Hook
# Checks usage and pauses if above threshold

# Check for bypass
if [[ "$CLAUDE_NO_LIMIT" == "1" ]]; then
  exit 0
fi

# Check cached usage first - much faster than querying the API
CACHE_FILE="/tmp/cc-limit-guard-usage-cache"
THRESHOLD=90

if [[ -f "$CACHE_FILE" ]]; then
  CACHED_USAGE=$(cat "$CACHE_FILE" | grep -o '[0-9]*' | head -1)
  if [[ -n "$CACHED_USAGE" ]] && [[ "$CACHED_USAGE" -lt "$THRESHOLD" ]]; then
    exit 0
  fi
fi

# Above threshold or no cache - run guard to handle sleep
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
node "${SCRIPT_DIR}/rate_limit_guard.js" >/dev/null 2>&1

exit 0
