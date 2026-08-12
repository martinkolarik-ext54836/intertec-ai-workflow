#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=review-common.sh
source "$SCRIPT_DIR/review-common.sh"

# The reviewer runtime directory is a disposable cache. Reports, specs, plans,
# and workflow state are committed to the owning repository, so nothing here is
# a source of truth and everything here may be deleted at any time.

before="$(find "$RUNTIME_ROOT" "$LOG_ROOT" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
rotate_logs
prune_runtime
after="$(find "$RUNTIME_ROOT" "$LOG_ROOT" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"

echo "Runtime: $RUNTIME_ROOT"
echo "Logs: $LOG_ROOT"
echo "Retention: $REVIEW_RETENTION_DAYS day(s)"
echo "Log rotation: $REVIEW_LOG_MAX_BYTES byte(s), keeping $REVIEW_LOG_KEEP file(s)"
echo "Files before: $before"
echo "Files after: $after"
