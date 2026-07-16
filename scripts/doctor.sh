#!/usr/bin/env bash
set -euo pipefail

PROJECTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
errors=0
warnings=0

check_file() {
  if [ -f "$1" ]; then
    echo "OK      $1"
  else
    echo "ERROR   missing $1"
    errors=$((errors + 1))
  fi
}

check_file "$PROJECTS_ROOT/.ai/WORKFLOW.md"
check_file "$PROJECTS_ROOT/.ai/VERSION"
check_file "$PROJECTS_ROOT/AGENTS.md"
check_file "$PROJECTS_ROOT/CLAUDE.md"

while IFS= read -r git_dir; do
  repo="${git_dir%/.git}"
  case "$repo" in
    "$PROJECTS_ROOT/.ai"|"$PROJECTS_ROOT/old/"*|"$PROJECTS_ROOT/pen/share/"*)
      continue
      ;;
  esac
  origin="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  if [ -n "$origin" ] && [[ "$origin" != *martinkolarik* ]] && [[ "$origin" != *topanka2000* ]]; then
    continue
  fi
  if [ -f "$repo/.ai/project.md" ]; then
    echo "OK      project context: $repo"
  else
    echo "WARN    no .ai/project.md: $repo"
    warnings=$((warnings + 1))
  fi
done < <(find "$PROJECTS_ROOT" -maxdepth 5 -type d -name .git -prune -print | sort)

echo
echo "Result: $errors error(s), $warnings warning(s)"
exit "$errors"
