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

BIN_PATH=$(swift build -c release --show-bin-path)
BINARY="$BIN_PATH/agentic-daemon"

echo "Installing..."
mkdir -p "$SUPPORT/jobs"
mkdir -p "$SUPPORT/lib/Modules"
mkdir -p "$LOGS"

# Install daemon binary
cp "$BINARY" "$SUPPORT/agentic-daemon"
chmod 755 "$SUPPORT/agentic-daemon"

# Install AgenticJobKit shared library + module for job compilation
cp "$BIN_PATH/libAgenticJobKit.dylib" "$SUPPORT/lib/"
for ext in swiftmodule swiftdoc abi.json swiftsourceinfo; do
    src="$BIN_PATH/Modules/AgenticJobKit.$ext"
    [ -f "$src" ] && cp "$src" "$SUPPORT/lib/Modules/"
done

# Expand $HOME in plist and install
sed "s|\${HOME}|$HOME|g" "$PLIST_SRC" > "$PLIST_DST"

# Unload if already registered
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

# Load and start
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"

echo ""
echo "Installed: $LABEL"
echo "  Binary:  $SUPPORT/agentic-daemon"
echo "  JobKit:  $SUPPORT/lib/libAgenticJobKit.dylib"
echo "  Jobs:    $SUPPORT/jobs/"
echo "  Logs:    $LOGS/"
echo "  Plist:   $PLIST_DST"
echo ""
launchctl list "$LABEL"
