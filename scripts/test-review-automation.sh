#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d /tmp/shared-ai-review-test.XXXXXX)"
test_root="$(cd "$test_root" && pwd -P)"
repo="$test_root/project"
runtime="$test_root/runtime"
logs="$test_root/logs"
fake_codex="$test_root/codex"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$repo/.ai/specs" "$repo/.ai/plans" "$repo/.ai/reviews" "$repo/.ai/state"
git -C "$repo" init -q -b main
git -C "$repo" config user.name "AI Reviewer Test"
git -C "$repo" config user.email "ai-reviewer-test@example.invalid"

cat > "$repo/.ai/project.md" <<'EOF'
# Project AI Context

No runtime checks are required by this fixture.
EOF
cat > "$repo/.ai/specs/2026-07-16-review-fixture.md" <<'EOF'
# Feature Spec: review fixture

- [ ] Fixture change exists.
EOF
cat > "$repo/.ai/plans/2026-07-16-review-fixture.md" <<'EOF'
# Implementation Plan: review fixture

1. Add fixture.txt.
EOF
cat > "$repo/.ai/state/current.md" <<'EOF'
# Current AI Workflow State

workflow_version: 1.2.0
feature_slug: review-fixture
class: C
status: implementing
implementation_commit:
spec: .ai/specs/2026-07-16-review-fixture.md
plan: .ai/plans/2026-07-16-review-fixture.md
external_review:
EOF
printf '%s\n' 'fixture' > "$repo/fixture.txt"
git -C "$repo" add .
git -C "$repo" commit -q -m "feat: review fixture"
sha="$(git -C "$repo" rev-parse HEAD)"
sed -i.bak "s/^status:.*/status: waiting_for_external_review/; s/^implementation_commit:.*/implementation_commit: $sha/" "$repo/.ai/state/current.md"
rm "$repo/.ai/state/current.md.bak"

cat > "$fake_codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "login" ]; then
  echo "Logged in using ChatGPT"
  exit 0
fi
output=""
commit=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    --commit) commit="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat > "$output" <<REPORT
# External Review: review-fixture

Verdict: APPROVED
Reviewed commit: $commit
Reviewed against: fixture-parent

## Checks

| Check | Result | Evidence |
|---|---|---|
| Fixture inspection | PASSED | fixture.txt exists |

## Findings

None.

## Completion Contract

- [x] Every spec requirement is satisfied.

## Residual Risk

- None.

## Next Action

- AWAIT_PR_APPROVAL
REPORT
EOF
chmod +x "$fake_codex"

before_fixture="$(git -C "$repo" hash-object fixture.txt)"
PROJECTS_ROOT="$test_root" \
REVIEW_RUNTIME_ROOT="$runtime" \
REVIEW_LOG_ROOT="$logs" \
CODEX_BIN="$fake_codex" \
REVIEW_SKIP_AUTH_CHECK=1 \
REVIEW_AUTO_COMMIT=0 \
REVIEW_NOTIFY=0 \
  "$SCRIPT_DIR/review-worker.sh"

review="$repo/.ai/reviews/$(date '+%Y-%m-%d')-review-fixture-external-review.md"
test -s "$review"
grep -q '^Verdict: APPROVED$' "$review"
grep -q '^status: external_review_done$' "$repo/.ai/state/current.md"
grep -q "^reviewed_commit: $sha$" "$repo/.ai/state/current.md"
test "$before_fixture" = "$(git -C "$repo" hash-object fixture.txt)"
test -f "$runtime/completed/$(printf '%s' "$repo" | shasum -a 256 | awk '{print substr($1, 1, 16)}')-$sha"
test -z "$(find "$runtime/worktrees" -mindepth 1 -maxdepth 1 -print -quit)"

echo "Automatic review integration test passed."
