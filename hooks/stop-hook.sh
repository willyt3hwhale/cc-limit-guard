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

# Run Swift script silently - it will sleep if above threshold
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
swift "${SCRIPT_DIR}/rate_limit_guard.swift" >/dev/null 2>&1

# Exit silently - statusline handles display
exit 0
