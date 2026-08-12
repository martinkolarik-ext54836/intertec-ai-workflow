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

state_field() {
  awk -v wanted="$2" '
    index($0, ":") {
      key = substr($0, 1, index($0, ":") - 1)
      value = substr($0, index($0, ":") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key != wanted) next
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^`|`$/, "", value)
      print value
      exit
    }
  ' "$1"
}

check_file "$AI_ROOT/WORKFLOW.md"
check_file "$AI_ROOT/VERSION"
check_file "$PROJECTS_ROOT/AGENTS.md"
check_file "$PROJECTS_ROOT/CLAUDE.md"

shared_version=""
if [ -f "$AI_ROOT/VERSION" ]; then
  shared_version="$(tr -d '[:space:]' < "$AI_ROOT/VERSION")"
fi
documented_version=""
if [ -f "$AI_ROOT/WORKFLOW.md" ]; then
  documented_version="$(awk '/^Version: / { print $2; exit }' "$AI_ROOT/WORKFLOW.md")"
fi
if [ -n "$shared_version" ] && [ "$shared_version" != "$documented_version" ]; then
  echo "ERROR   VERSION ($shared_version) does not match WORKFLOW.md (${documented_version:-missing})"
  errors=$((errors + 1))
else
  echo "OK      workflow version: ${shared_version:-unknown}"
fi

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

  state_file="$repo/.ai/state/current.md"
  [ -f "$state_file" ] || continue

  project_version="$(state_field "$state_file" workflow_version)"
  if [ -n "$shared_version" ] && [ -n "$project_version" ] && \
     [ "$project_version" != "$shared_version" ]; then
    echo "WARN    workflow version drift ($project_version, shared is $shared_version): $repo"
    warnings=$((warnings + 1))
  fi

  # A handoff that points at a commit which is no longer HEAD is never picked up
  # by the reviewer, and nothing else reports it.
  state_status="$(state_field "$state_file" status | tr '[:upper:]' '[:lower:]')"
  if [ "$state_status" = "waiting_for_external_review" ]; then
    requested="$(state_field "$state_file" implementation_commit)"
    resolved="$(git -C "$repo" rev-parse --verify "$requested^{commit}" 2>/dev/null || true)"
    head_sha="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"
    if [ -z "$resolved" ] || [ "$resolved" != "$head_sha" ]; then
      echo "WARN    waiting for review but implementation_commit is not HEAD: $repo"
      warnings=$((warnings + 1))
    fi
  fi
done < <(find "$PROJECTS_ROOT" -maxdepth 5 -type d -name .git -prune -print | sort)

echo
echo "Result: $errors error(s), $warnings warning(s)"
exit "$errors"
