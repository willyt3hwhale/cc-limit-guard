#!/usr/bin/env node
/**
 * Cross-platform rate limit guard for Claude Code.
 * Uses Node.js built-in fetch with Safari User-Agent to bypass Cloudflare.
 *
 * No external dependencies required (Node 18+).
 */

const fs = require('fs');
const path = require('path');

const THRESHOLD = 90;
const verbose = process.argv.includes('--verbose') || process.argv.includes('-v');
const noSleep = process.argv.includes('--no-sleep');

function loadSecrets() {
  const secretsPath = path.join(process.env.HOME, '.claude', 'secrets');
  const secrets = {};

  try {
    const content = fs.readFileSync(secretsPath, 'utf8');
    for (const line of content.split('\n')) {
      let trimmed = line.trim();
      if (trimmed.startsWith('export ')) {
        trimmed = trimmed.slice(7);
      }
      const eqIndex = trimmed.indexOf('=');
      if (eqIndex > 0) {
        const key = trimmed.slice(0, eqIndex);
        let value = trimmed.slice(eqIndex + 1);
        // Remove surrounding quotes
        if ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'"))) {
          value = value.slice(1, -1);
        }
        secrets[key] = value;
      }
    }
  } catch (e) {
    // File doesn't exist or unreadable
  }

  return secrets;
}

async function fetchUsage(sessionKey, orgId) {
  const url = `https://claude.ai/api/organizations/${orgId}/usage`;

  const response = await fetch(url, {
    headers: {
      'Cookie': `sessionKey=${sessionKey}`,
      'Accept': 'application/json',
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
    }
  });

  if (!response.ok) {
    throw new Error(`API returned status ${response.status}`);
  }

  return response.json();
}

function parseResetTime(isoString) {
  if (!isoString) return null;
  try {
    return new Date(isoString);
  } catch (e) {
    return null;
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function formatUsage(utilization) {
  return utilization === Math.floor(utilization)
    ? utilization.toString()
    : utilization.toFixed(1);
}

async function main() {
  // Check for bypass
  if (process.env.CLAUDE_NO_LIMIT === '1') {
    if (verbose) console.log('⚠️  Rate limit guard bypassed (CLAUDE_NO_LIMIT=1)');
    process.exit(0);
  }

  // Load secrets from file first, then check env vars
  const secrets = loadSecrets();

  const sessionKey = process.env.CLAUDE_SESSION_KEY || secrets.CLAUDE_SESSION_KEY;
  const orgId = process.env.CLAUDE_ORG_ID || secrets.CLAUDE_ORG_ID;

  if (!sessionKey) {
    if (verbose) console.log('⚠️  No CLAUDE_SESSION_KEY set - skipping rate limit check');
    process.exit(0);
  }

  if (!orgId) {
    if (verbose) console.log('⚠️  No CLAUDE_ORG_ID set - skipping rate limit check');
    process.exit(0);
  }

  try {
    const data = await fetchUsage(sessionKey, orgId);

    const fiveHour = data.five_hour || {};
    const utilization = fiveHour.utilization || 0;
    const resetsAt = fiveHour.resets_at;

    const usageStr = formatUsage(utilization);

    if (verbose) {
      console.log(`✓ Usage: ${usageStr}% (threshold: ${THRESHOLD}%)`);
    }

    if (utilization >= THRESHOLD && !noSleep) {
      // Calculate sleep time
      let sleepSeconds = 600; // Default 10 minutes

      if (resetsAt) {
        const resetTime = parseResetTime(resetsAt);
        if (resetTime) {
          const now = new Date();
          const secondsUntilReset = Math.floor((resetTime - now) / 1000) + 60; // 1 min buffer
          if (secondsUntilReset > 0) {
            sleepSeconds = secondsUntilReset;
          }
        }
      }

      const minutes = Math.floor(sleepSeconds / 60);
      console.log(`⚠️  Claude usage at ${usageStr}% - sleeping ${minutes} minutes until reset...`);

      await sleep(sleepSeconds * 1000);
      console.log('✓ Resuming after rate limit cooldown');
    }

    process.exit(0);

  } catch (e) {
    if (verbose) console.log(`⚠️  Error checking usage: ${e.message}`);
    process.exit(0);
  }
}

main();
