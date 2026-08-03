#!/usr/bin/env bash
set -euo pipefail

AI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_ROOT="${PROJECTS_ROOT:-$(cd "$AI_ROOT/.." && pwd)}"
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

check_file "$AI_ROOT/WORKFLOW.md"
check_file "$AI_ROOT/VERSION"
check_file "$PROJECTS_ROOT/AGENTS.md"
check_file "$PROJECTS_ROOT/CLAUDE.md"

while IFS= read -r git_dir; do
  repo="${git_dir%/.git}"
  case "$repo" in
    "$AI_ROOT")
      continue
      ;;
  esac
  if [ -n "${AI_DOCTOR_IGNORE_REGEX:-}" ] && printf '%s\n' "$repo" | grep -Eq "$AI_DOCTOR_IGNORE_REGEX"; then
    continue
  fi
  if [ -f "$repo/.ai/project.md" ]; then
    echo "OK      project context: $repo"
  elif git -C "$repo" cat-file -e main:.ai/project.md 2>/dev/null; then
    echo "OK      project context on main (current branch not updated): $repo"
  else
    echo "WARN    no .ai/project.md: $repo"
    warnings=$((warnings + 1))
  fi
done < <(find "$PROJECTS_ROOT" -maxdepth 5 -type d -name .git -prune -print | sort)

echo
echo "Result: $errors error(s), $warnings warning(s)"
exit "$errors"
