#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOMAIN="gui/$(id -u)"
LABEL="${REVIEW_SERVICE_LABEL:-sk.intertec.ai-reviewer}"
PLIST="${REVIEW_SERVICE_PLIST:-$HOME/Library/LaunchAgents/$LABEL.plist}"
LOG_ROOT="${REVIEW_LOG_ROOT:-$HOME/Library/Logs/IntertecAIReviewer}"
REVIEW_MODEL="${REVIEW_MODEL:-gpt-5.6-terra}"
REVIEW_REASONING="${REVIEW_REASONING:-high}"

mkdir -p "$(dirname "$PLIST")" "$LOG_ROOT"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$AI_ROOT/scripts/review-worker.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>60</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>$HOME</string>
    <key>PATH</key>
    <string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    <key>PROJECTS_ROOT</key>
    <string>$(cd "$AI_ROOT/.." && pwd)</string>
    <key>REVIEW_MODEL</key>
    <string>$REVIEW_MODEL</string>
    <key>REVIEW_REASONING</key>
    <string>$REVIEW_REASONING</string>
  </dict>
  <key>StandardOutPath</key>
  <string>$LOG_ROOT/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_ROOT/launchd.err.log</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST"
launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "$DOMAIN" "$PLIST"
launchctl kickstart -k "$DOMAIN/$LABEL"

echo "Installed and started $LABEL"
echo "Model: $REVIEW_MODEL"
echo "Reasoning: $REVIEW_REASONING"
echo "Interval: 60 seconds"
echo "Status: $AI_ROOT/scripts/reviewer-status.sh"
