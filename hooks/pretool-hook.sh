#!/bin/bash

# Rate Limit Guard - PreToolUse Hook
# Uses stale-while-revalidate: always returns cached values immediately,
# refreshes cache in background if stale

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
LOCK_FILE="/tmp/cc-limit-guard-updating"
CACHE_MAX_AGE=30
SESSION_THRESHOLD=90
WEEKLY_THRESHOLD=95
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Function to refresh cache in background
refresh_cache_background() {
  # Check lock file - skip if another refresh is in progress
  # Lock file older than 60s is considered stale (refresh crashed/hung)
  if [[ -f "$LOCK_FILE" ]]; then
    if [[ "$(uname)" == "Darwin" ]]; then
      LOCK_MTIME=$(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0)
    else
      LOCK_MTIME=$(stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)
    fi
    LOCK_AGE=$(($(date +%s) - LOCK_MTIME))
    if [[ $LOCK_AGE -lt 60 ]]; then
      return 0
    fi
  fi

  # Create lock file
  echo $$ > "$LOCK_FILE"

  # Fetch fresh data
  OUTPUT=$(node "${SCRIPT_DIR}/rate_limit_guard.js" --verbose --no-sleep 2>/dev/null)
  SESSION=$(echo "$OUTPUT" | grep -oE 'Session: [0-9]+' | grep -oE '[0-9]+')
  WEEKLY=$(echo "$OUTPUT" | grep -oE 'Weekly: [0-9]+' | grep -oE '[0-9]+')

  # Update cache
  if [[ -n "$SESSION" ]]; then
    echo "${SESSION}|${WEEKLY}" > "$CACHE_FILE"
  fi

  # Remove lock file
  rm -f "$LOCK_FILE"
}

# Check cache age
CACHE_STALE=true
if [[ -f "$CACHE_FILE" ]]; then
  if [[ "$(uname)" == "Darwin" ]]; then
    CACHE_MTIME=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
  else
    CACHE_MTIME=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
  fi
  CACHE_AGE=$(($(date +%s) - CACHE_MTIME))
  if [[ $CACHE_AGE -lt $CACHE_MAX_AGE ]]; then
    CACHE_STALE=false
  fi
fi

# If cache exists, use it (stale or fresh)
if [[ -f "$CACHE_FILE" ]]; then
  CACHED=$(cat "$CACHE_FILE")
  CACHED_SESSION=$(echo "$CACHED" | cut -d'|' -f1)
  CACHED_WEEKLY=$(echo "$CACHED" | cut -d'|' -f2)

  if [[ -n "$CACHED_SESSION" ]]; then
    # Output usage info
    jq -n --arg msg "Session: ${CACHED_SESSION}% | Weekly: ${CACHED_WEEKLY}%" '{"systemMessage": $msg}'

    # If stale, trigger background refresh
    if [[ "$CACHE_STALE" == "true" ]]; then
      refresh_cache_background &
      disown
    fi

    # Check thresholds - if under, exit fast
    if [[ "$CACHED_SESSION" -lt "$SESSION_THRESHOLD" ]] && [[ "$CACHED_WEEKLY" -lt "$WEEKLY_THRESHOLD" ]]; then
      exit 0
    fi

    # Above threshold - need to sleep (blocking call)
    node "${SCRIPT_DIR}/rate_limit_guard.js" --verbose 2>/dev/null
    exit 0
  fi
fi

# No cache exists - must fetch synchronously (first run)
OUTPUT=$(node "${SCRIPT_DIR}/rate_limit_guard.js" --verbose --no-sleep 2>/dev/null)
SESSION=$(echo "$OUTPUT" | grep -oE 'Session: [0-9]+' | grep -oE '[0-9]+')
WEEKLY=$(echo "$OUTPUT" | grep -oE 'Weekly: [0-9]+' | grep -oE '[0-9]+')

# Update cache
if [[ -n "$SESSION" ]]; then
  echo "${SESSION}|${WEEKLY}" > "$CACHE_FILE"
  jq -n --arg msg "Session: ${SESSION}% | Weekly: ${WEEKLY}%" '{"systemMessage": $msg}'

  # Check if above threshold
  if [[ "$SESSION" -ge "$SESSION_THRESHOLD" ]] || [[ "$WEEKLY" -ge "$WEEKLY_THRESHOLD" ]]; then
    node "${SCRIPT_DIR}/rate_limit_guard.js" --verbose 2>/dev/null
  fi
fi

exit 0
