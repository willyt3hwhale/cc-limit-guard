# Rate Limit Guard

A Claude Code plugin that monitors your usage and automatically pauses when approaching rate limits.

## Features

- Checks usage after each Claude response
- Displays current usage percentage in the status line
- Automatically sleeps when usage exceeds threshold (default: 90%)
- Resumes automatically when the 5-hour billing window resets
- Bypass option for when you need to use all your tokens

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

### 1. Get your session key

1. Go to [claude.ai](https://claude.ai) and log in
2. Open browser DevTools (F12) → Application → Cookies
3. Find the `sessionKey` cookie and copy its value

### 2. Find your organization ID

1. Go to [claude.ai](https://claude.ai) and open DevTools (F12)
2. Go to Network tab, filter by "usage"
3. Look for a request to `/api/organizations/{org-id}/usage`
4. Copy the org ID from the URL

### 3. Create secrets file

Create `~/.claude/secrets`:
```bash
export CLAUDE_SESSION_KEY=sk-ant-sid01-YOUR_KEY_HERE
export CLAUDE_ORG_ID=your-org-id-here
```

Secure the file:
```bash
chmod 600 ~/.claude/secrets
```

## Usage

Once configured, the plugin runs automatically. After each Claude response, you'll see:

```
Stop says: ✓ Usage: 29% (threshold: 90%)
```

When usage exceeds 90%, the plugin will:
1. Display a warning message
2. Sleep until the billing window resets
3. Resume automatically

### Bypass

To temporarily bypass the rate limit guard:

```bash
CLAUDE_NO_LIMIT=1 claude
```

## Requirements

- macOS (uses Swift for API calls)
- Claude Pro/Max subscription
- `jq` installed (`brew install jq`)

## Compatibility

- **ralph-wiggum**: Compatible. The plugin automatically stays silent during active ralph loops to avoid interfering with the loop's Stop hook.

## How it works

The plugin uses a Stop hook that runs after each Claude response. It:

1. Fetches usage data from the Claude.ai API using Swift's URLSession
2. Compares current usage against the threshold
3. If above threshold, calculates time until reset and sleeps
4. Outputs status via JSON systemMessage for display

## License

MIT
