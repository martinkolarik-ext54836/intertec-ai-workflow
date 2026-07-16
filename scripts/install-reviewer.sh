#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLIST="$HOME/Library/LaunchAgents/sk.intertec.ai-reviewer.plist"
LOG_ROOT="$HOME/Library/Logs/IntertecAIReviewer"
DOMAIN="gui/$(id -u)"
LABEL="sk.intertec.ai-reviewer"

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
    <string>gpt-5.6-terra</string>
    <key>REVIEW_REASONING</key>
    <string>high</string>
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
echo "Model: gpt-5.6-terra"
echo "Reasoning: high"
echo "Interval: 60 seconds"
echo "Status: $AI_ROOT/scripts/reviewer-status.sh"
