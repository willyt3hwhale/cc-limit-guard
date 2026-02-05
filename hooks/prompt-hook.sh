#!/bin/bash

# Rate Limit Guard - UserPromptSubmit Hook
# Checks usage before Claude processes a prompt

# Check for bypass
if [[ "$CLAUDE_NO_LIMIT" == "1" ]]; then
  exit 0
fi

# Check cached usage first (fast path)
CACHE_FILE="/tmp/cc-limit-guard-usage-cache"
THRESHOLD=90

if [[ -f "$CACHE_FILE" ]]; then
  CACHED_USAGE=$(cat "$CACHE_FILE" | grep -o '[0-9]*' | head -1)
  if [[ -n "$CACHED_USAGE" ]]; then
    jq -n --arg msg "Usage: ${CACHED_USAGE}% (threshold: ${THRESHOLD}%)" '{"systemMessage": $msg}'

    if [[ "$CACHED_USAGE" -lt "$THRESHOLD" ]]; then
      exit 0
    fi
  fi
fi

# Above threshold or no cache - run guard to get fresh data and potentially sleep
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT=$(node "${SCRIPT_DIR}/rate_limit_guard.js" --verbose 2>&1)

if [[ -n "$OUTPUT" ]]; then
  jq -n --arg msg "$OUTPUT" '{"systemMessage": $msg}'
fi

exit 0
