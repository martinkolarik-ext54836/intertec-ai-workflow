#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=review-common.sh
source "$SCRIPT_DIR/review-common.sh"

worker_lock="$RUNTIME_ROOT/locks/worker"
if ! acquire_lock "$worker_lock"; then
  exit 0
fi
trap 'rm -rf "$worker_lock" >/dev/null 2>&1 || true' EXIT INT TERM

log_review "SCAN projects_root=$PROJECTS_ROOT"
while IFS= read -r state_file; do
  repo="${state_file%/.ai/state/current.md}"
  status="$(state_value "$state_file" status | tr '[:upper:]' '[:lower:]')"
  [ "$status" = "waiting_for_external_review" ] || continue
  "$SCRIPT_DIR/review-one.sh" "$repo" || true
done < <(
  find "$PROJECTS_ROOT" -maxdepth 7 \
    -path '*/.git' -prune -o \
    -path '*/old/*' -prune -o \
    -path '*/pen/share/*' -prune -o \
    -type f -path '*/.ai/state/current.md' -print 2>/dev/null | sort
)
