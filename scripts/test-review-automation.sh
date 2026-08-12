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

# A broken environment pauses every repository instead of consuming one
# commit's attempt budget.
create_fixture environment
environment_repo="$fixture_repo"
environment_sha="$fixture_sha"
environment_identifier="$(review_identifier "$environment_repo" "$environment_sha")"
empty_home="$test_root/empty-home"
mkdir -p "$empty_home"
printf '0\n' > "$fake_calls"
set +e
PATH=/usr/bin:/bin \
HOME="$empty_home" \
PROJECTS_ROOT="$test_root" \
REVIEW_RUNTIME_ROOT="$runtime" \
REVIEW_LOG_ROOT="$logs" \
REVIEW_NOTIFY=0 \
REVIEW_TRIGGER=worker \
  "$SCRIPT_DIR/review-one.sh" "$environment_repo"
environment_status=$?
set -e
test "$environment_status" = "4"
test -f "$runtime/environment-cooldown"
test ! -e "$runtime/failures/$environment_identifier"
grep -q "ENVIRONMENT repo=$environment_repo reason=codex-not-found" "$logs/reviewer.log"

# The scheduled worker starts no review while the cooldown is active.
PROJECTS_ROOT="$test_root" \
REVIEW_RUNTIME_ROOT="$runtime" \
REVIEW_LOG_ROOT="$logs" \
CODEX_BIN="$fake_codex" \
REVIEW_SKIP_AUTH_CHECK=1 \
REVIEW_AUTO_COMMIT=0 \
REVIEW_NOTIFY=0 \
FAKE_REVIEWED_COMMIT="$environment_sha" \
  "$SCRIPT_DIR/review-worker.sh"
test "$(cat "$fake_calls")" = "0"
grep -q "reason=environment-cooldown" "$logs/reviewer.log"

# Once the cooldown expires the worker resumes on its own and clears it.
sed -i.bak 's/^until=.*/until=0/' "$runtime/environment-cooldown"
rm -f "$runtime/environment-cooldown.bak"
run_review_one "$environment_repo" "$environment_sha" APPROVED 0
test ! -e "$runtime/environment-cooldown"
grep -q '^status: external_review_done$' "$environment_repo/.ai/state/current.md"

# A recorded review while the project still waits is reported, not skipped.
create_fixture stalled
stalled_repo="$fixture_repo"
stalled_sha="$fixture_sha"
stalled_identifier="$(review_identifier "$stalled_repo" "$stalled_sha")"
printf '%s\n' "$stalled_sha" > "$runtime/completed/$stalled_identifier"
printf '0\n' > "$fake_calls"
run_review_one "$stalled_repo" "$stalled_sha" APPROVED 0
test "$(cat "$fake_calls")" = "0"
test -f "$runtime/failures/$stalled_identifier.stalled"
grep -q "STALL repo=$stalled_repo reason=completed-but-still-waiting" "$logs/reviewer.log"

# --force reviews a commit whose review was already recorded.
REVIEW_RUNTIME_ROOT="$runtime" \
REVIEW_LOG_ROOT="$logs" \
CODEX_BIN="$fake_codex" \
REVIEW_SKIP_AUTH_CHECK=1 \
REVIEW_AUTO_COMMIT=0 \
REVIEW_NOTIFY=0 \
FAKE_CODEX_VERDICT=APPROVED \
FAKE_REVIEWED_COMMIT="$stalled_sha" \
  "$SCRIPT_DIR/review-now.sh" --force "$stalled_repo"
test "$(cat "$fake_calls")" = "1"
test ! -e "$runtime/failures/$stalled_identifier.stalled"
grep -q '^status: external_review_done$' "$stalled_repo/.ai/state/current.md"

# A lock held by a live process is respected.
create_fixture locked
locked_repo="$fixture_repo"
locked_sha="$fixture_sha"
locked_identifier="$(review_identifier "$locked_repo" "$locked_sha")"
mkdir -p "$runtime/locks/$locked_identifier"
printf '%s|\n' "$$" > "$runtime/locks/$locked_identifier/owner"
printf '0\n' > "$fake_calls"
run_review_one "$locked_repo" "$locked_sha" APPROVED 0
test "$(cat "$fake_calls")" = "0"
grep -q "reason=already-running" "$logs/reviewer.log"

# A lock whose owner is gone is reclaimed.
printf '%s|\n' "4194305" > "$runtime/locks/$locked_identifier/owner"
run_review_one "$locked_repo" "$locked_sha" APPROVED 0
test "$(cat "$fake_calls")" = "1"

# A lock whose PID was reused by a different process is reclaimed.
create_fixture reused-pid
reused_repo="$fixture_repo"
reused_sha="$fixture_sha"
reused_identifier="$(review_identifier "$reused_repo" "$reused_sha")"
mkdir -p "$runtime/locks/$reused_identifier"
printf '%s|Thu Jan 1 00:00:00 1970\n' "$$" > "$runtime/locks/$reused_identifier/owner"
printf '0\n' > "$fake_calls"
run_review_one "$reused_repo" "$reused_sha" APPROVED 0
test "$(cat "$fake_calls")" = "1"

# Logs rotate and expired runtime markers are deleted.
prune_runtime_root="$test_root/prune-runtime"
prune_log_root="$test_root/prune-logs"
mkdir -p "$prune_runtime_root/completed" "$prune_log_root"
printf 'expired\n' > "$prune_runtime_root/completed/expired"
touch -t 200001010000 "$prune_runtime_root/completed/expired"
printf 'fresh\n' > "$prune_runtime_root/completed/fresh"
head -c 4096 /dev/zero | tr '\0' 'x' > "$prune_log_root/reviewer.log"
REVIEW_RUNTIME_ROOT="$prune_runtime_root" \
REVIEW_LOG_ROOT="$prune_log_root" \
REVIEW_LOG_MAX_BYTES=1024 \
REVIEW_LOG_KEEP=2 \
REVIEW_RETENTION_DAYS=30 \
  "$SCRIPT_DIR/prune-runtime.sh" >/dev/null
test ! -e "$prune_runtime_root/completed/expired"
test -f "$prune_runtime_root/completed/fresh"
test -f "$prune_log_root/reviewer.log.1"
test ! -s "$prune_log_root/reviewer.log"

echo "Automatic review integration tests passed."
