#!/usr/bin/env bash
set -euo pipefail

SHARED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${1:-$PWD}"

if [ ! -d "$PROJECT" ]; then
  echo "Project directory does not exist: $PROJECT" >&2
  exit 1
fi

PROJECT="$(cd "$PROJECT" && pwd)"
if ! git -C "$PROJECT" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "Not a Git repository: $PROJECT" >&2
  exit 1
fi

REPO_ROOT="$(git -C "$PROJECT" rev-parse --show-toplevel)"
mkdir -p "$REPO_ROOT/.ai/specs" "$REPO_ROOT/.ai/plans" \
  "$REPO_ROOT/.ai/reviews" "$REPO_ROOT/.ai/state/archive"

# Specs, plans, reviews, and state are local development notes, not deliverables.
# Only the project context and the agent adapters belong in the repository.
ensure_ignored() {
  local pattern="$1"
  local ignore_file="$REPO_ROOT/.gitignore"
  if [ -f "$ignore_file" ] && grep -qxF "$pattern" "$ignore_file"; then
    return 0
  fi
  if [ -s "$ignore_file" ] && [ -n "$(tail -c 1 "$ignore_file")" ]; then
    printf '\n' >> "$ignore_file"
  fi
  if ! grep -qxF '# Local AI workflow artifacts (not deliverables)' "$ignore_file" 2>/dev/null; then
    printf '%s\n' '# Local AI workflow artifacts (not deliverables)' >> "$ignore_file"
  fi
  printf '%s\n' "$pattern" >> "$ignore_file"
  echo "Ignored $pattern"
}

ensure_ignored '.ai/specs/'
ensure_ignored '.ai/plans/'
ensure_ignored '.ai/reviews/'
ensure_ignored '.ai/state/'

if [ ! -f "$REPO_ROOT/.ai/project.md" ]; then
  cp "$SHARED_ROOT/templates/project.md" "$REPO_ROOT/.ai/project.md"
  project_name="$(basename "$REPO_ROOT")"
  remote="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || echo "$REPO_ROOT")"
  PROJECT_NAME="$project_name" PROJECT_REMOTE="$remote" \
    perl -0pi -e 's/<name>/$ENV{PROJECT_NAME}/; s/<remote or local path>/$ENV{PROJECT_REMOTE}/' \
    "$REPO_ROOT/.ai/project.md"
  echo "Created .ai/project.md"
else
  echo "Kept existing .ai/project.md"
fi

if [ ! -f "$REPO_ROOT/AGENTS.md" ]; then
  cat > "$REPO_ROOT/AGENTS.md" <<'EOF'
# Repository AI Instructions

When working locally, follow `__WORKFLOW_PATH__`.
Always read `.ai/project.md` for repository-specific commands and constraints.
Keep specs, plans, reviews, and workflow state inside this repository's `.ai/`.

If the shared workflow is unavailable, preserve user changes, use the lightest
safe workflow, require a plan approval for features or risky changes, run the
documented checks, and require explicit approval before PR, merge, or deploy.
EOF
  WORKFLOW_PATH="$SHARED_ROOT/WORKFLOW.md" \
    perl -0pi -e 's/__WORKFLOW_PATH__/$ENV{WORKFLOW_PATH}/g' "$REPO_ROOT/AGENTS.md"
  echo "Created AGENTS.md"
else
  echo "Kept existing AGENTS.md"
fi

if [ ! -f "$REPO_ROOT/CLAUDE.md" ]; then
  cat > "$REPO_ROOT/CLAUDE.md" <<'EOF'
# Repository AI Instructions

@__WORKFLOW_PATH__
@.ai/project.md

Project feature artifacts remain in this repository's `.ai/` directory.
EOF
  WORKFLOW_PATH="$SHARED_ROOT/WORKFLOW.md" \
    perl -0pi -e 's/__WORKFLOW_PATH__/$ENV{WORKFLOW_PATH}/g' "$REPO_ROOT/CLAUDE.md"
  echo "Created CLAUDE.md"
else
  echo "Kept existing CLAUDE.md"
fi

echo "Initialized: $REPO_ROOT"
