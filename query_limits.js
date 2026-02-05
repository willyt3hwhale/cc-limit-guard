#!/usr/bin/env node
/**
 * Query Claude Code rate limit status using the same Anthropic API headers
 * that Claude Code reads internally.
 *
 * Auth resolution order:
 *   1. ANTHROPIC_API_KEY env var (API key users)
 *   2. ~/.claude/.credentials.json (plaintext fallback, all platforms)
 *   3. macOS keychain "Claude Code-credentials" (macOS only)
 *
 * Usage: node query_limits.js [--json] [--verbose]
 */

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const API_URL = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-haiku-4-5-20251001';
const CLAIMS = ['5h', '7d', 'overage'];

function readCredentialsFile() {
  const configDir = process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
  const credPath = path.join(configDir, '.credentials.json');
  if (!fs.existsSync(credPath)) return null;
  return JSON.parse(fs.readFileSync(credPath, 'utf8'));
}

function readMacKeychain() {
  if (process.platform !== 'darwin') return null;
  try {
    const username = os.userInfo().username;
    const raw = execFileSync('security', [
      'find-generic-password',
      '-s', 'Claude Code-credentials',
      '-a', username,
      '-w',
    ], { encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }).trim();

    try {
      return JSON.parse(raw);
    } catch {
      return JSON.parse(Buffer.from(raw, 'hex').toString('utf8'));
    }
  } catch {
    return null;
  }
}

function getAuth() {
  // 1. API key from env
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (apiKey) {
    return {
      authHeader: `x-api-key`,
      token: apiKey,
      tier: 'api-key',
      sub: 'api',
    };
  }

  // 2. Plaintext credentials file (all platforms)
  let creds = readCredentialsFile();

  // 3. macOS keychain
  if (!creds) creds = readMacKeychain();

  if (!creds) throw new Error('No credentials found. Set ANTHROPIC_API_KEY or log in with Claude Code.');

  const oauth = creds.claudeAiOauth;
  if (!oauth?.accessToken) throw new Error('No OAuth access token in credentials');

  if (oauth.expiresAt && Date.now() > oauth.expiresAt) {
    throw new Error('OAuth token expired - run Claude Code to refresh');
  }

  return {
    authHeader: 'Authorization',
    token: `Bearer ${oauth.accessToken}`,
    tier: oauth.rateLimitTier || 'unknown',
    sub: oauth.subscriptionType || 'unknown',
  };
}

function formatReset(epochSeconds) {
  if (!epochSeconds) return null;
  const diffMs = epochSeconds * 1000 - Date.now();
  if (diffMs <= 0) return 'now';

  const hours = Math.floor(diffMs / 3600000);
  const minutes = Math.floor((diffMs % 3600000) / 60000);
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m`;
}

function parseRateLimitHeaders(headers) {
  const result = {
    status: headers.get('anthropic-ratelimit-unified-status') || 'unknown',
    reset: headers.get('anthropic-ratelimit-unified-reset'),
    fallback: headers.get('anthropic-ratelimit-unified-fallback'),
    representativeClaim: headers.get('anthropic-ratelimit-unified-representative-claim'),
    overageStatus: headers.get('anthropic-ratelimit-unified-overage-status'),
    overageReset: headers.get('anthropic-ratelimit-unified-overage-reset'),
    overageDisabledReason: headers.get('anthropic-ratelimit-unified-overage-disabled-reason'),
    claims: {},
  };

  for (const claim of CLAIMS) {
    const utilization = headers.get(`anthropic-ratelimit-unified-${claim}-utilization`);
    const reset = headers.get(`anthropic-ratelimit-unified-${claim}-reset`);
    const surpassed = headers.get(`anthropic-ratelimit-unified-${claim}-surpassed-threshold`);

    if (utilization !== null || reset !== null) {
      result.claims[claim] = {
        utilization: utilization ? Number(utilization) : null,
        reset: reset ? Number(reset) : null,
        surpassedThreshold: surpassed ? Number(surpassed) : null,
      };
    }
  }

  return result;
}

async function queryLimits(auth, verbose) {
  const headers = {
    'Content-Type': 'application/json',
    'anthropic-version': '2023-06-01',
  };

  // OAuth needs the beta header; API keys use x-api-key directly
  if (auth.authHeader === 'Authorization') {
    headers['Authorization'] = auth.token;
    headers['anthropic-beta'] = 'oauth-2025-04-20';
  } else {
    headers['x-api-key'] = auth.token;
  }

  const response = await fetch(API_URL, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1,
      messages: [{ role: 'user', content: 'hi' }],
    }),
  });

  if (verbose) {
    console.error(`API status: ${response.status}`);
    for (const [k, v] of response.headers.entries()) {
      if (k.startsWith('anthropic-ratelimit'))
        console.error(`  ${k}: ${v}`);
    }
  }

  // Only headers matter - consume body so fetch completes
  await response.text();

  return parseRateLimitHeaders(response.headers);
}

function printHuman(info, auth) {
  console.log(`\nClaude Code Rate Limits (${auth.sub} / ${auth.tier})`);
  console.log('\u2500'.repeat(50));

  const statusColors = {
    allowed: '\x1b[32m',
    allowed_warning: '\x1b[33m',
    rejected: '\x1b[31m',
    unknown: '\x1b[90m',
  };
  const resetCode = '\x1b[0m';
  const color = statusColors[info.status] || statusColors.unknown;
  console.log(`Status: ${color}${info.status}${resetCode}`);

  if (info.reset) {
    console.log(`Resets in: ${formatReset(Number(info.reset))}`);
  }

  const claimLabels = { '5h': 'Session (5h)', '7d': 'Weekly (7d)', overage: 'Extra usage' };
  for (const [claim, data] of Object.entries(info.claims)) {
    const label = claimLabels[claim] || claim;
    const pct = data.utilization !== null ? `${(data.utilization * 100).toFixed(1)}%` : '?';
    const resetStr = data.reset ? ` | resets ${formatReset(data.reset)}` : '';
    const bar = data.utilization !== null ? makeBar(data.utilization) : '';
    console.log(`${label}: ${bar} ${pct}${resetStr}`);
  }

  if (info.overageStatus) {
    console.log(`Overage: ${info.overageStatus}`);
  }
  if (info.fallback) {
    console.log(`Fallback: ${info.fallback}`);
  }
  if (info.representativeClaim) {
    console.log(`Limit hit: ${info.representativeClaim}`);
  }
  console.log();
}

function makeBar(utilization, width = 20) {
  const filled = Math.round(utilization * width);
  const empty = width - filled;
  let color;
  if (utilization >= 0.9) color = '\x1b[31m';
  else if (utilization >= 0.7) color = '\x1b[33m';
  else color = '\x1b[32m';
  return `${color}${'\u2588'.repeat(filled)}${'\u2591'.repeat(empty)}\x1b[0m`;
}

module.exports = { getAuth, queryLimits, parseRateLimitHeaders, formatReset };

async function main() {
  const jsonMode = process.argv.includes('--json');
  const verbose = process.argv.includes('--verbose') || process.argv.includes('-v');

  try {
    const auth = getAuth();
    if (verbose) console.error(`Auth: ${auth.sub} / ${auth.tier} (${auth.authHeader})`);

    const info = await queryLimits(auth, verbose);

    if (jsonMode) {
      console.log(JSON.stringify(info, null, 2));
    } else {
      printHuman(info, auth);
    }
  } catch (e) {
    if (verbose) console.error(`Error: ${e.message}`);
    console.error(`Failed: ${e.message}`);
    process.exit(1);
  }
}

if (require.main === module) main();
