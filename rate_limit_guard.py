#!/usr/bin/env python3
"""
Cross-platform rate limit guard for Claude Code.
Uses curl_cffi to bypass Cloudflare's TLS fingerprinting.

Install: pip install curl_cffi
"""

import os
import sys
import json
import time
from datetime import datetime, timezone
from pathlib import Path

# Parse CLI arguments
verbose = "--verbose" in sys.argv or "-v" in sys.argv
no_sleep = "--no-sleep" in sys.argv

THRESHOLD = 90


def load_secrets():
    """Load credentials from ~/.claude/secrets by parsing shell exports."""
    secrets_path = Path.home() / ".claude" / "secrets"

    if not secrets_path.exists():
        return {}

    secrets = {}
    with open(secrets_path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("export "):
                line = line[7:]  # Remove 'export '
            if "=" in line:
                key, _, value = line.partition("=")
                # Remove quotes if present
                value = value.strip("'\"")
                secrets[key] = value

    return secrets


def fetch_usage(session_key: str, org_id: str) -> dict:
    """Fetch usage data from Claude API using curl_cffi for TLS fingerprint impersonation."""
    try:
        from curl_cffi import requests as cffi_requests
    except ImportError:
        print("Error: curl_cffi not installed. Run: pip install curl_cffi", file=sys.stderr)
        sys.exit(1)

    url = f"https://claude.ai/api/organizations/{org_id}/usage"

    headers = {
        "Cookie": f"sessionKey={session_key}",
        "Accept": "application/json",
    }

    # Impersonate Safari (closest to Swift's URLSession behavior)
    response = cffi_requests.get(
        url,
        headers=headers,
        impersonate="safari15_5",
        timeout=10,
    )

    if response.status_code != 200:
        raise Exception(f"API returned status {response.status_code}")

    return response.json()


def parse_reset_time(iso_string: str) -> datetime | None:
    """Parse ISO8601 timestamp with fractional seconds."""
    if not iso_string:
        return None

    try:
        # Handle fractional seconds
        if "." in iso_string:
            # Python's fromisoformat handles this in 3.11+
            return datetime.fromisoformat(iso_string.replace("Z", "+00:00"))
        else:
            return datetime.fromisoformat(iso_string.replace("Z", "+00:00"))
    except ValueError:
        return None


def main():
    # Check for bypass
    if os.environ.get("CLAUDE_NO_LIMIT") == "1":
        if verbose:
            print("⚠️  Rate limit guard bypassed (CLAUDE_NO_LIMIT=1)")
        sys.exit(0)

    # Load secrets from file first, then check env vars
    secrets = load_secrets()

    session_key = os.environ.get("CLAUDE_SESSION_KEY") or secrets.get("CLAUDE_SESSION_KEY")
    org_id = os.environ.get("CLAUDE_ORG_ID") or secrets.get("CLAUDE_ORG_ID")

    if not session_key:
        if verbose:
            print("⚠️  No CLAUDE_SESSION_KEY set - skipping rate limit check")
        sys.exit(0)

    if not org_id:
        if verbose:
            print("⚠️  No CLAUDE_ORG_ID set - skipping rate limit check")
        sys.exit(0)

    try:
        data = fetch_usage(session_key, org_id)

        # Extract five_hour usage data
        five_hour = data.get("five_hour", {})
        utilization = five_hour.get("utilization", 0)
        resets_at = five_hour.get("resets_at")

        # Format as integer if whole number, otherwise 1 decimal
        usage_str = f"{utilization:.0f}" if utilization == int(utilization) else f"{utilization:.1f}"

        if verbose:
            print(f"✓ Usage: {usage_str}% (threshold: {THRESHOLD}%)")

        if utilization >= THRESHOLD and not no_sleep:
            # Calculate sleep time
            sleep_seconds = 600  # Default 10 minutes

            if resets_at:
                reset_time = parse_reset_time(resets_at)
                if reset_time:
                    now = datetime.now(timezone.utc)
                    seconds_until_reset = int((reset_time - now).total_seconds()) + 60  # 1 min buffer
                    if seconds_until_reset > 0:
                        sleep_seconds = seconds_until_reset

            minutes = sleep_seconds // 60
            print(f"⚠️  Claude usage at {usage_str}% - sleeping {minutes} minutes until reset...")

            time.sleep(sleep_seconds)
            print("✓ Resuming after rate limit cooldown")

        sys.exit(0)

    except Exception as e:
        if verbose:
            print(f"⚠️  Error checking usage: {e}")
        sys.exit(0)


if __name__ == "__main__":
    main()
