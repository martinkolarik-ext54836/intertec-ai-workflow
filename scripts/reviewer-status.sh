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
echo "Environment cooldown:"
cooldown_remaining="$(environment_cooldown_remaining)"
if [ -f "$ENVIRONMENT_COOLDOWN_FILE" ]; then
  sed 's/^/  /' "$ENVIRONMENT_COOLDOWN_FILE"
  echo "  seconds_remaining=$cooldown_remaining"
else
  echo "none"
fi

print_marker_group() {
  local label="$1"
  local pattern="$2"
  local entries entry
  echo
  echo "$label:"
  entries="$(find "$RUNTIME_ROOT/failures" -maxdepth 1 -type f -name "$pattern" -print 2>/dev/null | sort)"
  if [ -z "$entries" ]; then
    echo "none"
    return 0
  fi
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    echo "${entry##*/}"
    sed 's/^/  /' "$entry"
  done <<MARKERS
$entries
MARKERS
}

print_marker_group "Give-up entries" '*.giveup'
print_marker_group "Stalled handoffs (review recorded but project still waiting)" '*.stalled'
echo
echo "Recent activity:"
if [ -f "$LOG_ROOT/reviewer.log" ]; then
  tail -n 20 "$LOG_ROOT/reviewer.log"
else
  echo "none"
fi
