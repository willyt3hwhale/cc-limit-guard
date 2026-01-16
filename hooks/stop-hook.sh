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

# Run Swift script and capture output
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT=$(swift "${SCRIPT_DIR}/rate_limit_guard.swift" --verbose 2>&1)
EXIT_CODE=$?

# Output JSON with systemMessage for display
if [[ -n "$OUTPUT" ]]; then
  jq -n --arg msg "$OUTPUT" '{"systemMessage": $msg}'
fi

exit 0
