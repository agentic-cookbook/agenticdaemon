#!/bin/bash
set -euo pipefail

LABEL="com.agentic-cookbook.daemon"
SUPPORT="$HOME/Library/Application Support/$LABEL"
LOGS="$HOME/Library/Logs/$LABEL"
PLIST_SRC="$(cd "$(dirname "$0")" && pwd)/${LABEL}.plist"
PLIST_DST="$HOME/Library/LaunchAgents/${LABEL}.plist"
PKG_DIR="$(cd "$(dirname "$0")" && pwd)/AgenticDaemon"

echo "Building agentic-daemon..."
cd "$PKG_DIR"
swift build -c release

BINARY=$(swift build -c release --show-bin-path)/agentic-daemon

echo "Installing..."
mkdir -p "$SUPPORT/jobs"
mkdir -p "$LOGS"
cp "$BINARY" "$SUPPORT/agentic-daemon"
chmod 755 "$SUPPORT/agentic-daemon"

# Expand $HOME in plist and install
sed "s|\${HOME}|$HOME|g" "$PLIST_SRC" > "$PLIST_DST"

# Unload if already registered
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

# Load and start
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"

echo ""
echo "Installed: $LABEL"
echo "  Binary:  $SUPPORT/agentic-daemon"
echo "  Jobs:    $SUPPORT/jobs/"
echo "  Logs:    $LOGS/"
echo "  Plist:   $PLIST_DST"
echo ""
launchctl list "$LABEL"
