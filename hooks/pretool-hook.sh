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
  CACHED_USAGE=$(cat "$CACHE_FILE" | grep -o '[0-9]*' | head -1)
  if [[ -n "$CACHED_USAGE" ]] && [[ "$CACHED_USAGE" -lt "$THRESHOLD" ]]; then
    # Below threshold - exit immediately
    exit 0
  fi
fi

# Cache stale or above threshold - run Swift to get fresh data
OUTPUT=$(swift "${SCRIPT_DIR}/rate_limit_guard.swift" --verbose --no-sleep 2>/dev/null)
USAGE=$(echo "$OUTPUT" | grep -o '[0-9]*%' | head -1 | tr -d '%')

# Update cache
if [[ -n "$USAGE" ]]; then
  echo "$USAGE" > "$CACHE_FILE"
fi

# If above threshold, run Swift again to sleep
if [[ -n "$USAGE" ]] && [[ "$USAGE" -ge "$THRESHOLD" ]]; then
  swift "${SCRIPT_DIR}/rate_limit_guard.swift" --verbose 2>/dev/null
fi

exit 0
