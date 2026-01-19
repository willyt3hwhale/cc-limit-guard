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
THRESHOLD=90
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Check if cache is fresh
CACHE_FRESH=false
if [[ -f "$CACHE_FILE" ]]; then
  CACHE_AGE=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)))
  if [[ $CACHE_AGE -lt $CACHE_MAX_AGE ]]; then
    CACHE_FRESH=true
  fi
fi

# If cache is fresh, use cached value
if [[ "$CACHE_FRESH" == "true" ]]; then
  # Cache format is "Usage: X%" - extract just the number
  CACHED_USAGE=$(cat "$CACHE_FILE" | grep -o '[0-9]*' | head -1)
  if [[ -n "$CACHED_USAGE" ]]; then
    # Output usage info
    jq -n --arg msg "Usage: ${CACHED_USAGE}% (threshold: ${THRESHOLD}%)" '{"systemMessage": $msg}'

    if [[ "$CACHED_USAGE" -lt "$THRESHOLD" ]]; then
      # Below threshold - exit immediately
      exit 0
    fi
  fi
fi

# Cache stale or above threshold - run Node to get fresh data
OUTPUT=$(node "${SCRIPT_DIR}/rate_limit_guard.js" --verbose --no-sleep 2>/dev/null)
USAGE_WITH_PCT=$(echo "$OUTPUT" | grep -o '[0-9]*%' | head -1)
USAGE=$(echo "$USAGE_WITH_PCT" | tr -d '%')

# Update cache (write full format for statusline compatibility)
if [[ -n "$USAGE" ]]; then
  echo "Usage: ${USAGE_WITH_PCT}" > "$CACHE_FILE"
fi

# Output usage info for fresh fetch
if [[ -n "$USAGE" ]]; then
  jq -n --arg msg "Usage: ${USAGE}% (threshold: ${THRESHOLD}%)" '{"systemMessage": $msg}'
fi

# If above threshold, run Node again to sleep
if [[ -n "$USAGE" ]] && [[ "$USAGE" -ge "$THRESHOLD" ]]; then
  node "${SCRIPT_DIR}/rate_limit_guard.js" --verbose 2>/dev/null
fi

exit 0
