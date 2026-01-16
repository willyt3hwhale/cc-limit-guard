#!/bin/bash

# Rate Limit Guard Stop Hook
# Checks usage and pauses if above threshold

# Check for bypass
if [[ "$CLAUDE_NO_LIMIT" == "1" ]]; then
  exit 0
fi

# Load secrets file
SECRETS_FILE="$HOME/.claude/secrets"
if [[ -f "$SECRETS_FILE" ]]; then
  source "$SECRETS_FILE"
fi

# Check for session key
if [[ -z "$CLAUDE_SESSION_KEY" ]]; then
  exit 0
fi

# Check cached usage first (from statusline) - much faster than running Swift
CACHE_FILE="/tmp/cc-limit-guard-usage-cache"
THRESHOLD=90

if [[ -f "$CACHE_FILE" ]]; then
  CACHED_USAGE=$(cat "$CACHE_FILE" | grep -o '[0-9]*' | head -1)
  if [[ -n "$CACHED_USAGE" ]] && [[ "$CACHED_USAGE" -lt "$THRESHOLD" ]]; then
    # Below threshold - exit immediately without running slow Swift
    exit 0
  fi
fi

# Above threshold or no cache - run Swift to handle sleep
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
swift "${SCRIPT_DIR}/rate_limit_guard.swift" >/dev/null 2>&1

exit 0
