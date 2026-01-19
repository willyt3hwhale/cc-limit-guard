#!/bin/bash

# Rate Limit Guard - PreToolUse Hook
# Checks usage before each tool call, sleeps if above threshold

# Check for bypass
if [[ "$CLAUDE_NO_LIMIT" == "1" ]]; then
  exit 0
fi

# Load secrets file
SECRETS_FILE="$HOME/.claude/secrets"
if [[ -f "$SECRETS_FILE" ]]; then
  source "$SECRETS_FILE"
fi

# Check for required env vars
if [[ -z "$CLAUDE_SESSION_KEY" ]] || [[ -z "$CLAUDE_ORG_ID" ]]; then
  exit 0
fi

CACHE_FILE="/tmp/cc-limit-guard-usage-cache"
CACHE_MAX_AGE=30
SESSION_THRESHOLD=90
WEEKLY_THRESHOLD=95
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Cross-platform file modification time (seconds since epoch)
get_file_mtime() {
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f %m "$1" 2>/dev/null || echo 0
  else
    stat -c %Y "$1" 2>/dev/null || echo 0
  fi
}

# Check if cache is fresh
CACHE_FRESH=false
if [[ -f "$CACHE_FILE" ]]; then
  CACHE_AGE=$(($(date +%s) - $(get_file_mtime "$CACHE_FILE")))
  if [[ $CACHE_AGE -lt $CACHE_MAX_AGE ]]; then
    CACHE_FRESH=true
  fi
fi

# If cache is fresh, use cached value
if [[ "$CACHE_FRESH" == "true" ]]; then
  # Cache format is "session|weekly" (e.g. "56|3")
  CACHED=$(cat "$CACHE_FILE")
  CACHED_SESSION=$(echo "$CACHED" | cut -d'|' -f1)
  CACHED_WEEKLY=$(echo "$CACHED" | cut -d'|' -f2)

  if [[ -n "$CACHED_SESSION" ]]; then
    # Output usage info
    jq -n --arg msg "Session: ${CACHED_SESSION}% | Weekly: ${CACHED_WEEKLY}%" '{"systemMessage": $msg}'

    # Check both thresholds
    if [[ "$CACHED_SESSION" -lt "$SESSION_THRESHOLD" ]] && [[ "$CACHED_WEEKLY" -lt "$WEEKLY_THRESHOLD" ]]; then
      exit 0
    fi
  fi
fi

# Cache stale or above threshold - run Node to get fresh data
# Output format: "✓ Session: 56% (threshold: 90%) | Weekly: 3% (threshold: 95%)"
OUTPUT=$(node "${SCRIPT_DIR}/rate_limit_guard.js" --verbose --no-sleep 2>/dev/null)

# Extract session and weekly percentages
SESSION=$(echo "$OUTPUT" | grep -oE 'Session: [0-9]+' | grep -oE '[0-9]+')
WEEKLY=$(echo "$OUTPUT" | grep -oE 'Weekly: [0-9]+' | grep -oE '[0-9]+')

# Update cache
if [[ -n "$SESSION" ]]; then
  echo "${SESSION}|${WEEKLY}" > "$CACHE_FILE"
fi

# Output usage info for fresh fetch
if [[ -n "$SESSION" ]]; then
  jq -n --arg msg "Session: ${SESSION}% | Weekly: ${WEEKLY}%" '{"systemMessage": $msg}'
fi

# If above either threshold, run Node again to sleep
if [[ -n "$SESSION" ]]; then
  if [[ "$SESSION" -ge "$SESSION_THRESHOLD" ]] || [[ "$WEEKLY" -ge "$WEEKLY_THRESHOLD" ]]; then
    node "${SCRIPT_DIR}/rate_limit_guard.js" --verbose 2>/dev/null
  fi
fi

exit 0
