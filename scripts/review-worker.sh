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

rotate_logs
prune_runtime

log_review "SCAN projects_root=$PROJECTS_ROOT"
for state_file in \
  "$PROJECTS_ROOT"/*/.ai/state/current.md \
  "$PROJECTS_ROOT"/*/*/.ai/state/current.md; do
  [ -f "$state_file" ] || continue
  repo="${state_file%/.ai/state/current.md}"
  status="$(state_value "$state_file" status | tr '[:upper:]' '[:lower:]')"
  [ "$status" = "waiting_for_external_review" ] || continue
  REVIEW_TRIGGER=worker "$SCRIPT_DIR/review-one.sh" "$repo" || true
done
