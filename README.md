# Rate Limit Guard

A Claude Code plugin that monitors your usage and automatically pauses when approaching rate limits.

## Features

- Monitors both session (5-hour) and weekly (7-day) usage limits
- Checks usage before each tool call
- Automatically sleeps when usage exceeds thresholds
- Resumes automatically when the billing window resets
- Cross-platform (macOS, Linux, Windows)
- Bypass option for when you need to use all your tokens

## Thresholds

| Limit | Threshold | Reset Period |
|-------|-----------|--------------|
| Session | 90% | Every 5 hours |
| Weekly | 95% | Every 7 days |

## Installation

### Via marketplace

In Claude Code, run:
```
/plugin marketplace add willyt3hwhale/cc-limit-guard
/plugin add rate-limit-guard@cc-limit-guard
```

### Via --plugin-dir (alternative)

```bash
git clone https://github.com/willyt3hwhale/cc-limit-guard ~/.claude/plugins/local/cc-limit-guard
```

Then add an alias to your shell config:
```bash
alias claude='claude --plugin-dir ~/.claude/plugins/local/cc-limit-guard'
```

## Configuration

No manual configuration needed. The plugin automatically finds your credentials in this order:

1. `ANTHROPIC_API_KEY` environment variable
2. `~/.claude/.credentials.json` (written by Claude Code on login)
3. macOS keychain (`Claude Code-credentials`)

Just install the plugin and it works.

## Usage

The plugin runs automatically. You'll see usage info as a system message:

```
Session: 29% | Weekly: 12%
```

When either threshold is exceeded, the plugin will:
1. Display a warning message
2. Sleep until the billing window resets
3. Resume automatically

### Bypass

To temporarily bypass the rate limit guard:

```bash
CLAUDE_NO_LIMIT=1 claude
```

## Requirements

- Node.js 18+ (uses built-in fetch)
- Claude Pro/Max subscription
- `jq` installed (`brew install jq` / `apt install jq`)

## How it works

The plugin uses a PreToolUse hook that runs before each tool call. It:

1. Sends a minimal API request to `api.anthropic.com` and reads rate limit headers back
2. Compares session and weekly utilization against thresholds
3. If above threshold, calculates time until reset and sleeps
4. Outputs status via JSON systemMessage for display
5. Uses stale-while-revalidate caching (30s) to keep hook response fast

## License

MIT
