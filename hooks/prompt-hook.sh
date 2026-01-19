#!/bin/bash

# Rate Limit Guard - UserPromptSubmit Hook
# Checks usage before Claude processes a prompt

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

# Check cached usage first (fast path)
CACHE_FILE="/tmp/cc-limit-guard-usage-cache"
THRESHOLD=90

if [[ -f "$CACHE_FILE" ]]; then
  CACHED_USAGE=$(cat "$CACHE_FILE" | grep -o '[0-9]*' | head -1)
  if [[ -n "$CACHED_USAGE" ]]; then
    # Output usage info via JSON
    jq -n --arg msg "Usage: ${CACHED_USAGE}% (threshold: ${THRESHOLD}%)" '{"systemMessage": $msg}'

    # If below threshold, exit without sleeping
    if [[ "$CACHED_USAGE" -lt "$THRESHOLD" ]]; then
      exit 0
    fi
  fi
fi

# Above threshold or no cache - run Swift to get fresh data and potentially sleep
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT=$(swift "${SCRIPT_DIR}/rate_limit_guard.swift" --verbose 2>&1)

# Output result
if [[ -n "$OUTPUT" ]]; then
  jq -n --arg msg "$OUTPUT" '{"systemMessage": $msg}'
fi

exit 0
