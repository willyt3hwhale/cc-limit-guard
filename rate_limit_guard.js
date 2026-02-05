#!/usr/bin/env node
/**
 * Cross-platform rate limit guard for Claude Code.
 * Queries the Anthropic API for rate limit headers using Claude Code's
 * own credentials (OAuth tokens from keychain/credentials file, or ANTHROPIC_API_KEY).
 *
 * No manual session keys or org IDs needed.
 * No external dependencies required (Node 18+).
 */

const { getAuth, queryLimits, formatReset } = require('./query_limits');

const SESSION_THRESHOLD = 90;
const WEEKLY_THRESHOLD = 95;
const verbose = process.argv.includes('--verbose') || process.argv.includes('-v');
const noSleep = process.argv.includes('--no-sleep');

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function formatUsage(utilization) {
  const pct = utilization * 100;
  return pct === Math.floor(pct) ? pct.toString() : pct.toFixed(1);
}

async function main() {
  if (process.env.CLAUDE_NO_LIMIT === '1') {
    if (verbose) console.log('Rate limit guard bypassed (CLAUDE_NO_LIMIT=1)');
    process.exit(0);
  }

  try {
    const auth = getAuth();
    const info = await queryLimits(auth, verbose);

    const sessionClaim = info.claims['5h'];
    const weeklyClaim = info.claims['7d'];

    const sessionUsage = sessionClaim ? sessionClaim.utilization * 100 : 0;
    const weeklyUsage = weeklyClaim ? weeklyClaim.utilization * 100 : 0;

    const sessionStr = formatUsage(sessionClaim ? sessionClaim.utilization : 0);
    const weeklyStr = formatUsage(weeklyClaim ? weeklyClaim.utilization : 0);

    if (verbose) {
      console.log(`Session: ${sessionStr}% (threshold: ${SESSION_THRESHOLD}%) | Weekly: ${weeklyStr}% (threshold: ${WEEKLY_THRESHOLD}%)`);
    }

    let shouldSleep = false;
    let sleepReason = '';
    let resetEpoch = null;

    if (sessionUsage >= SESSION_THRESHOLD) {
      shouldSleep = true;
      sleepReason = `session at ${sessionStr}%`;
      resetEpoch = sessionClaim?.reset;
    } else if (weeklyUsage >= WEEKLY_THRESHOLD) {
      shouldSleep = true;
      sleepReason = `weekly at ${weeklyStr}%`;
      resetEpoch = weeklyClaim?.reset;
    }

    if (shouldSleep && !noSleep) {
      let sleepSeconds = 600; // default 10 minutes

      if (resetEpoch) {
        const secondsUntilReset = Math.floor(resetEpoch - Date.now() / 1000) + 60;
        if (secondsUntilReset > 0) {
          sleepSeconds = secondsUntilReset;
        }
      }

      const minutes = Math.floor(sleepSeconds / 60);
      const hours = Math.floor(minutes / 60);
      const timeStr = hours > 0 ? `${hours}h ${minutes % 60}m` : `${minutes}m`;

      console.log(`Claude ${sleepReason} - sleeping ${timeStr} until reset...`);

      await sleep(sleepSeconds * 1000);
      console.log('Resuming after rate limit cooldown');
    }

    process.exit(0);

  } catch (e) {
    if (verbose) console.log(`Error checking usage: ${e.message}`);
    process.exit(0);
  }
}

main();
