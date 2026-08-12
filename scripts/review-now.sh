#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

force=0
repo=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    -h|--help)
      cat <<'USAGE'
Usage: review-now.sh [--force] [/path/to/repository]

  --force  Review the current implementation commit again even when a review
           has already been recorded for it.
USAGE
      exit 0
      ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) repo="$1"; shift ;;
  esac
done

REVIEW_TRIGGER=manual REVIEW_FORCE="$force" \
  exec "$SCRIPT_DIR/review-one.sh" "${repo:-$PWD}"
