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

When working locally, follow `/Users/martin/Projects/.ai/WORKFLOW.md`.
Always read `.ai/project.md` for repository-specific commands and constraints.
Keep specs, plans, reviews, and workflow state inside this repository's `.ai/`.

If the shared workflow is unavailable, preserve user changes, use the lightest
safe workflow, require a plan approval for features or risky changes, run the
documented checks, and require explicit approval before PR, merge, or deploy.
EOF
  echo "Created AGENTS.md"
else
  echo "Kept existing AGENTS.md"
fi

if [ ! -f "$REPO_ROOT/CLAUDE.md" ]; then
  cat > "$REPO_ROOT/CLAUDE.md" <<'EOF'
# Repository AI Instructions

@/Users/martin/Projects/.ai/WORKFLOW.md
@.ai/project.md

Project feature artifacts remain in this repository's `.ai/` directory.
EOF
  echo "Created CLAUDE.md"
else
  echo "Kept existing CLAUDE.md"
fi

echo "Initialized: $REPO_ROOT"
