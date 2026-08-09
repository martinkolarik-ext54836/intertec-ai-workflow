#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=review-common.sh
source "$SCRIPT_DIR/review-common.sh"

DOMAIN="gui/$(id -u)"
LABEL="${REVIEW_SERVICE_LABEL:-sk.intertec.ai-reviewer}"

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
echo "Give-up entries:"
giveup_entries="$(find "$RUNTIME_ROOT/failures" -maxdepth 1 -type f -name '*.giveup' -print 2>/dev/null | sort)"
if [ -n "$giveup_entries" ]; then
  while IFS= read -r giveup_file; do
    echo "${giveup_file##*/}"
    sed 's/^/  /' "$giveup_file"
  done <<EOF
$giveup_entries
EOF
else
  echo "none"
fi
echo
echo "Recent activity:"
if [ -f "$LOG_ROOT/reviewer.log" ]; then
  tail -n 20 "$LOG_ROOT/reviewer.log"
else
  echo "none"
fi
