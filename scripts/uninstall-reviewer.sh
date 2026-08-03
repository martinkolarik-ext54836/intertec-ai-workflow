#!/usr/bin/env bash
set -euo pipefail

DOMAIN="gui/$(id -u)"
LABEL="${REVIEW_SERVICE_LABEL:-sk.intertec.ai-reviewer}"
PLIST="${REVIEW_SERVICE_PLIST:-$HOME/Library/LaunchAgents/$LABEL.plist}"

launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
if [ -f "$PLIST" ]; then
  rm "$PLIST"
fi
echo "Uninstalled $LABEL"
echo "Logs and completed-review markers were preserved."
