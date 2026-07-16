#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=review-common.sh
source "$SCRIPT_DIR/review-common.sh"

DOMAIN="gui/$(id -u)"
LABEL="sk.intertec.ai-reviewer"

echo "Service: $LABEL"
if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
  echo "Status: loaded"
  launchctl print "$DOMAIN/$LABEL" 2>/dev/null | awk '
    /state =|runs =|last exit code =/ {sub(/^[[:space:]]+/, ""); print}
  '
else
  echo "Status: not loaded"
fi
echo "Model: $REVIEW_MODEL"
echo "Reasoning: $REVIEW_REASONING"
echo "Runtime: $RUNTIME_ROOT"
echo "Logs: $LOG_ROOT"
echo
echo "Recent activity:"
if [ -f "$LOG_ROOT/reviewer.log" ]; then
  tail -n 20 "$LOG_ROOT/reviewer.log"
else
  echo "none"
fi
