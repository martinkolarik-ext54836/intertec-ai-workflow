#!/usr/bin/env bash
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/sk.intertec.ai-reviewer.plist"
DOMAIN="gui/$(id -u)"
LABEL="sk.intertec.ai-reviewer"

launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
if [ -f "$PLIST" ]; then
  rm "$PLIST"
fi
echo "Uninstalled $LABEL"
echo "Logs and completed-review markers were preserved."
