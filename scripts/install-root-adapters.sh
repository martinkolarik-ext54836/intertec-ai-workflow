#!/usr/bin/env bash
set -euo pipefail

SHARED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_ROOT="$(cd "$SHARED_ROOT/.." && pwd)"

WORKFLOW_PATH="$SHARED_ROOT/WORKFLOW.md" \
WORKFLOW_ROOT="$SHARED_ROOT" \
PROJECTS_ROOT_VALUE="$PROJECTS_ROOT" \
  perl -pe 's/__WORKFLOW_PATH__/$ENV{WORKFLOW_PATH}/g; s/__WORKFLOW_ROOT__/$ENV{WORKFLOW_ROOT}/g; s/__PROJECTS_ROOT__/$ENV{PROJECTS_ROOT_VALUE}/g' \
  "$SHARED_ROOT/adapters/AGENTS.md" > "$PROJECTS_ROOT/AGENTS.md"
cp "$SHARED_ROOT/adapters/CLAUDE.md" "$PROJECTS_ROOT/CLAUDE.md"

echo "Installed root adapters in $PROJECTS_ROOT"
