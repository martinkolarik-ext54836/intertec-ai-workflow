#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="${1:-$PWD}"
exec "$SCRIPT_DIR/review-one.sh" "$repo"
