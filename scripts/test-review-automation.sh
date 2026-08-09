#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/shared-ai-review-test.XXXXXX")"
test_root="$(cd "$test_root" && pwd -P)"
runtime="$test_root/runtime"
logs="$test_root/logs"
fake_codex="$test_root/codex"
fake_calls="$test_root/codex-calls"
trap 'rm -rf "$test_root"' EXIT

create_fixture() {
  local name="$1"
  fixture_repo="$test_root/$name"
  mkdir -p "$fixture_repo/.ai/specs" "$fixture_repo/.ai/plans" \
    "$fixture_repo/.ai/reviews" "$fixture_repo/.ai/state"
  git -C "$fixture_repo" init -q -b main
  git -C "$fixture_repo" config user.name "AI Reviewer Test"
  git -C "$fixture_repo" config user.email "ai-reviewer-test@example.invalid"

  printf '%s\n' '# Project AI Context' '' \
    'No runtime checks are required by this fixture.' > "$fixture_repo/.ai/project.md"
  printf '%s\n' '# Feature Spec: review fixture' '' \
    '- [ ] Fixture change exists.' > "$fixture_repo/.ai/specs/review-fixture.md"
  printf '%s\n' '# Implementation Plan: review fixture' '' \
    '1. Add fixture.txt.' > "$fixture_repo/.ai/plans/review-fixture.md"
  cat > "$fixture_repo/.ai/state/current.md" <<'EOF'
# Current AI Workflow State

workflow_version: 1.3.0
feature_slug: review-fixture
class: C
status: implementing
implementation_commit:
spec: .ai/specs/review-fixture.md
plan: .ai/plans/review-fixture.md
external_review:
EOF
  printf '%s\n' 'fixture' > "$fixture_repo/fixture.txt"
  git -C "$fixture_repo" add .
  git -C "$fixture_repo" commit -q -m "feat: review fixture"
  fixture_sha="$(git -C "$fixture_repo" rev-parse HEAD)"
  sed -i.bak \
    "s/^status:.*/status: waiting_for_external_review/; s/^implementation_commit:.*/implementation_commit: $fixture_sha/" \
    "$fixture_repo/.ai/state/current.md"
  rm "$fixture_repo/.ai/state/current.md.bak"
}

review_identifier() {
  local repo="$1"
  local sha="$2"
  local repo_hash
  if command -v shasum >/dev/null 2>&1; then
    repo_hash="$(printf '%s' "$repo" | shasum -a 256 | awk '{print substr($1, 1, 16)}')"
  else
    repo_hash="$(printf '%s' "$repo" | sha256sum | awk '{print substr($1, 1, 16)}')"
  fi
  printf '%s-%s\n' "$repo_hash" "$sha"
}

run_review_one() {
  local repo="$1"
  local sha="$2"
  local verdict="$3"
  local auto_commit="$4"
  PROJECTS_ROOT="$test_root" \
  REVIEW_RUNTIME_ROOT="$runtime" \
  REVIEW_LOG_ROOT="$logs" \
  CODEX_BIN="$fake_codex" \
  REVIEW_SKIP_AUTH_CHECK=1 \
  REVIEW_AUTO_COMMIT="$auto_commit" \
  REVIEW_NOTIFY=0 \
  FAKE_CODEX_VERDICT="$verdict" \
  FAKE_REVIEWED_COMMIT="$sha" \
    "$SCRIPT_DIR/review-one.sh" "$repo"
}

cat > "$fake_codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "login" ]; then
  echo "Logged in using ChatGPT"
  exit 0
fi
calls=0
if [ -f "$FAKE_CODEX_CALLS" ]; then
  calls="$(cat "$FAKE_CODEX_CALLS")"
fi
printf '%s\n' "$((calls + 1))" > "$FAKE_CODEX_CALLS"
if [ "${FAKE_CODEX_EXIT:-0}" -ne 0 ]; then
  exit "$FAKE_CODEX_EXIT"
fi
output=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
cat > "$output" <<REPORT
# External Review: review-fixture

Verdict: ${FAKE_CODEX_VERDICT:-APPROVED}
Reviewed commit: $FAKE_REVIEWED_COMMIT
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

- Fixture-controlled.
REPORT
EOF
chmod +x "$fake_codex"
export FAKE_CODEX_CALLS="$fake_calls"

# Approved happy path without auto-commit.
create_fixture approved
approved_repo="$fixture_repo"
approved_sha="$fixture_sha"
before_fixture="$(git -C "$approved_repo" hash-object fixture.txt)"
run_review_one "$approved_repo" "$approved_sha" APPROVED 0
approved_review="$approved_repo/.ai/reviews/$(date '+%Y-%m-%d')-review-fixture-external-review.md"
test -s "$approved_review"
grep -q '^status: external_review_done$' "$approved_repo/.ai/state/current.md"
grep -q '^next_action: AWAIT_PR_APPROVAL$' "$approved_repo/.ai/state/current.md"
grep -q "^reviewed_commit: $approved_sha$" "$approved_repo/.ai/state/current.md"
test "$before_fixture" = "$(git -C "$approved_repo" hash-object fixture.txt)"
test -f "$runtime/completed/$(review_identifier "$approved_repo" "$approved_sha")"
test -z "$(find "$runtime/worktrees" -mindepth 1 -maxdepth 1 -print -quit)"

# Negative verdict maps to the documented workflow state.
create_fixture changes-required
changes_repo="$fixture_repo"
changes_sha="$fixture_sha"
run_review_one "$changes_repo" "$changes_sha" CHANGES_REQUIRED 0
grep -q '^status: changes_required$' "$changes_repo/.ai/state/current.md"
grep -q '^next_action: FIX_FINDINGS$' "$changes_repo/.ai/state/current.md"

# Scheduled retries stop at the configured maximum and leave a give-up marker.
create_fixture retry-limit
retry_repo="$fixture_repo"
retry_sha="$fixture_sha"
retry_identifier="$(review_identifier "$retry_repo" "$retry_sha")"
printf '0\n' > "$fake_calls"
for _attempt in 1 2 3; do
  PROJECTS_ROOT="$test_root" \
  REVIEW_RUNTIME_ROOT="$runtime" \
  REVIEW_LOG_ROOT="$logs" \
  CODEX_BIN="$fake_codex" \
  REVIEW_SKIP_AUTH_CHECK=1 \
  REVIEW_AUTO_COMMIT=0 \
  REVIEW_NOTIFY=0 \
  REVIEW_MAX_ATTEMPTS=2 \
  FAKE_CODEX_EXIT=5 \
  FAKE_REVIEWED_COMMIT="$retry_sha" \
    "$SCRIPT_DIR/review-worker.sh"
done
test "$(cat "$fake_calls")" = "2"
test "$(cat "$runtime/failures/$retry_identifier")" = "2"
test -f "$runtime/failures/$retry_identifier.giveup"
grep -q "GIVEUP repo=$retry_repo" "$logs/reviewer.log"

# A deliberate manual retry clears give-up state and makes a fresh attempt.
REVIEW_RUNTIME_ROOT="$runtime" \
REVIEW_LOG_ROOT="$logs" \
CODEX_BIN="$fake_codex" \
REVIEW_SKIP_AUTH_CHECK=1 \
REVIEW_AUTO_COMMIT=0 \
REVIEW_NOTIFY=0 \
REVIEW_MAX_ATTEMPTS=2 \
FAKE_CODEX_EXIT=5 \
FAKE_REVIEWED_COMMIT="$retry_sha" \
  "$SCRIPT_DIR/review-now.sh" "$retry_repo" || manual_status=$?
test "${manual_status:-0}" = "5"
test "$(cat "$fake_calls")" = "3"
test "$(cat "$runtime/failures/$retry_identifier")" = "1"
test ! -e "$runtime/failures/$retry_identifier.giveup"

# Auto-commit records only review output and workflow state when the index is clean.
create_fixture auto-commit
auto_repo="$fixture_repo"
auto_sha="$fixture_sha"
run_review_one "$auto_repo" "$auto_sha" APPROVED 1
test "$(git -C "$auto_repo" rev-parse HEAD^)" = "$auto_sha"
test "$(git -C "$auto_repo" log -1 --format=%s)" = \
  "docs: record external review for review-fixture"
test -z "$(git -C "$auto_repo" status --porcelain)"

# Preexisting staged changes prevent auto-commit and remain staged and untouched.
create_fixture staged-index
staged_repo="$fixture_repo"
staged_sha="$fixture_sha"
printf '%s\n' 'already staged' > "$staged_repo/preexisting.txt"
git -C "$staged_repo" add preexisting.txt
run_review_one "$staged_repo" "$staged_sha" APPROVED 1
test "$(git -C "$staged_repo" rev-parse HEAD)" = "$staged_sha"
test "$(git -C "$staged_repo" diff --cached --name-only)" = "preexisting.txt"
test -z "$(git -C "$staged_repo" diff --cached --name-only -- .ai/state/current.md .ai/reviews)"
grep -q "WARN repo=$staged_repo reason=preexisting-staged-changes" "$logs/reviewer.log"

echo "Automatic review integration tests passed."
