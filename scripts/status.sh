#!/usr/bin/env bash
set -euo pipefail

PROJECT="${1:-$PWD}"
AI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ]; then
  echo "Not a Git repository: $PROJECT" >&2
  exit 1
fi

echo "Repository: $ROOT"
echo "Workflow: $(cat "$AI_ROOT/VERSION")"
echo "Branch: $(git -C "$ROOT" branch --show-current 2>/dev/null || echo unknown)"
echo
echo "Git status:"
git -C "$ROOT" status --short || true

for item in \
  ".ai/project.md:Project context" \
  ".ai/state/current.md:Current state"; do
  path="${item%%:*}"
  label="${item#*:}"
  echo
  echo "$label:"
  if [ -f "$ROOT/$path" ]; then
    echo "$ROOT/$path"
  else
    echo "none"
  fi
done

echo
echo "Latest artifacts:"
for pair in "specs:*.md" "plans:*.md" "reviews:*-self-review.md" "reviews:*-external-review.md"; do
  dir="${pair%%:*}"
  pattern="${pair#*:}"
  latest="$(find "$ROOT/.ai/$dir" -maxdepth 1 -type f -name "$pattern" ! -name 'TEMPLATE.md' 2>/dev/null | sort | tail -n 1 || true)"
  echo "${dir}: ${latest:-none}"
done
