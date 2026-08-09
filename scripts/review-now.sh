#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="${1:-$PWD}"
REVIEW_TRIGGER=manual exec "$SCRIPT_DIR/review-one.sh" "$repo"
