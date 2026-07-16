#!/usr/bin/env bash
set -euo pipefail

SHARED_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECTS_ROOT="$(cd "$SHARED_ROOT/.." && pwd)"

cp "$SHARED_ROOT/adapters/AGENTS.md" "$PROJECTS_ROOT/AGENTS.md"
cp "$SHARED_ROOT/adapters/CLAUDE.md" "$PROJECTS_ROOT/CLAUDE.md"

echo "Installed root adapters in $PROJECTS_ROOT"
