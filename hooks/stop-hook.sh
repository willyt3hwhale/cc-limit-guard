#!/bin/bash

# Rate Limit Guard Stop Hook
# Checks usage and pauses if above threshold

# Check for bypass
if [[ "$CLAUDE_NO_LIMIT" == "1" ]]; then
  exit 0
fi

# Check if ralph-wiggum loop is active - don't interfere with its Stop hook
RALPH_STATE_FILE=".claude/ralph-loop.local.md"
RALPH_ACTIVE=false
if [[ -f "$RALPH_STATE_FILE" ]]; then
  RALPH_ACTIVE=true
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

# Output JSON with systemMessage for display (skip if ralph-wiggum is active)
if [[ -n "$OUTPUT" ]] && [[ "$RALPH_ACTIVE" == "false" ]]; then
  jq -n --arg msg "$OUTPUT" '{"systemMessage": $msg}'
fi

exit 0
