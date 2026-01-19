#!/bin/bash
# Setup script for cross-platform rate limit guard

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"

echo "Setting up rate limit guard..."

# Check for Python 3
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 not found. Please install Python 3.8+" >&2
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
fi

# Install dependencies
echo "Installing curl_cffi..."
"$VENV_DIR/bin/pip" install --quiet curl_cffi

# Make scripts executable
chmod +x "$SCRIPT_DIR/rate_limit_guard.py"

echo ""
echo "✓ Setup complete!"
echo ""
echo "Usage:"
echo "  $VENV_DIR/bin/python $SCRIPT_DIR/rate_limit_guard.py --verbose --no-sleep"
echo ""
echo "Or update hooks/pretool-hook.sh to use Python instead of Swift."
