#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=review-common.sh
source "$SCRIPT_DIR/review-common.sh"

usage() {
  cat <<'USAGE'
Usage: review-one.sh [--force] /path/to/repository

  --force  Review the current implementation commit again even when a review
           has already been recorded for it, and clear any give-up state.
USAGE
}

force=0
if [ "${REVIEW_FORCE:-0}" = "1" ]; then
  force=1
fi
requested_repo=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) usage >&2; exit 2 ;;
    *) requested_repo="$1"; shift ;;
  esac
done

repo="$requested_repo"
if [ -z "$repo" ] || [ ! -d "$repo" ]; then
  usage >&2
  exit 2
fi
repo="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo" ]; then
  echo "Not a Git repository: $requested_repo" >&2
  exit 2
fi

# Anything that does not identify itself is treated as the unattended worker,
# so a caller can never accidentally re-enable unbounded retries.
trigger="${REVIEW_TRIGGER:-worker}"

state_file="$repo/.ai/state/current.md"
if [ ! -f "$state_file" ]; then
  log_review "SKIP repo=$repo reason=no-state-file"
  exit 3
fi

status="$(state_value "$state_file" status | tr '[:upper:]' '[:lower:]')"
if [ "$status" != "waiting_for_external_review" ]; then
  log_review "SKIP repo=$repo reason=status value=${status:-missing}"
  exit 3
fi

requested_commit="$(state_value "$state_file" implementation_commit)"
if [ -z "$requested_commit" ]; then
  log_review "SKIP repo=$repo reason=missing-implementation-commit"
  exit 3
fi
reviewed_sha="$(git -C "$repo" rev-parse --verify "$requested_commit^{commit}" 2>/dev/null || true)"
if [ -z "$reviewed_sha" ]; then
  log_review "SKIP repo=$repo reason=invalid-implementation-commit value=$requested_commit"
  exit 3
fi
current_head="$(git -C "$repo" rev-parse HEAD)"
if [ "$current_head" != "$reviewed_sha" ]; then
  log_review "SKIP repo=$repo reason=head-mismatch expected=$reviewed_sha actual=$current_head"
  exit 3
fi

slug="$(state_value "$state_file" feature_slug)"
if ! printf '%s' "$slug" | grep -Eq '^[a-z0-9][a-z0-9._-]*$'; then
  slug="review-${reviewed_sha:0:12}"
fi

spec_rel="$(safe_project_path "$(state_value_any "$state_file" spec spec_path 2>/dev/null || true)" 2>/dev/null || true)"
plan_rel="$(safe_project_path "$(state_value_any "$state_file" plan plan_path 2>/dev/null || true)" 2>/dev/null || true)"
if [ -z "$spec_rel" ] || [ -z "$plan_rel" ]; then
  log_review "SKIP repo=$repo reason=missing-or-unsafe-spec-plan slug=$slug"
  exit 3
fi
case "$spec_rel" in .ai/specs/*.md) ;; *) log_review "SKIP repo=$repo reason=invalid-spec-path"; exit 3 ;; esac
case "$plan_rel" in .ai/plans/*.md) ;; *) log_review "SKIP repo=$repo reason=invalid-plan-path"; exit 3 ;; esac
# Workflow artifacts are local development notes and are not versioned, so they
# are read from the working tree rather than from the reviewed commit.
if [ ! -f "$repo/$spec_rel" ] || [ ! -f "$repo/$plan_rel" ]; then
  log_review "SKIP repo=$repo reason=spec-plan-not-found slug=$slug sha=$reviewed_sha"
  exit 3
fi
self_review_rel="$(safe_project_path "$(state_value_any "$state_file" self_review self_review_path 2>/dev/null || true)" 2>/dev/null || true)"
case "$self_review_rel" in
  .ai/reviews/*.md) ;;
  *) self_review_rel="" ;;
esac

review_rel="$(safe_project_path "$(state_value_any "$state_file" external_review external_review_path 2>/dev/null || true)" 2>/dev/null || true)"
if [ -z "$review_rel" ]; then
  review_rel=".ai/reviews/$(date '+%Y-%m-%d')-$slug-external-review.md"
fi
case "$review_rel" in .ai/reviews/*.md) ;; *) log_review "SKIP repo=$repo reason=invalid-review-path"; exit 3 ;; esac
if [ -f "$repo/$review_rel" ] && ! grep -q "^Reviewed commit: $reviewed_sha$" "$repo/$review_rel"; then
  review_rel=".ai/reviews/$(date '+%Y-%m-%d')-$slug-external-review-${reviewed_sha:0:12}.md"
fi

identifier="$(repo_id "$repo")-$reviewed_sha"
lock_dir="$RUNTIME_ROOT/locks/$identifier"
completed_file="$RUNTIME_ROOT/completed/$identifier"
failure_file="$RUNTIME_ROOT/failures/$identifier"
giveup_file="$RUNTIME_ROOT/failures/$identifier.giveup"
stalled_file="$RUNTIME_ROOT/failures/$identifier.stalled"
result_file="$RUNTIME_ROOT/results/$identifier.md"
worktree="$RUNTIME_ROOT/worktrees/$identifier"

if [ "$trigger" != "worker" ] || [ "$force" = "1" ]; then
  rm -f "$failure_file" "$giveup_file" "$stalled_file"
  log_review "RESET repo=$repo reason=manual-retry force=$force sha=$reviewed_sha"
fi
if [ "$force" = "1" ]; then
  rm -f "$completed_file"
fi

# Reaching this point means the project still asks for a review. A completed
# marker for the same commit therefore means the handoff is stuck, not done.
if [ -f "$completed_file" ]; then
  if [ -f "$stalled_file" ]; then
    log_review "SKIP repo=$repo reason=already-completed sha=$reviewed_sha"
  else
    {
      printf 'repo=%s\n' "$repo"
      printf 'slug=%s\n' "$slug"
      printf 'sha=%s\n' "$reviewed_sha"
      printf 'detected=%s\n' "$(timestamp)"
    } > "$stalled_file"
    log_review "STALL repo=$repo reason=completed-but-still-waiting sha=$reviewed_sha"
    notify_review "$slug" \
      "A review is already recorded for this commit but the project still waits for one."
  fi
  exit 0
fi
if [ -f "$giveup_file" ]; then
  log_review "SKIP repo=$repo reason=attempts-exhausted sha=$reviewed_sha"
  exit 0
fi
cooldown_remaining="$(environment_cooldown_remaining)"
if [ "$trigger" = "worker" ] && [ "$cooldown_remaining" -gt 0 ]; then
  log_review "SKIP repo=$repo reason=environment-cooldown seconds_remaining=$cooldown_remaining"
  exit 3
fi
if ! acquire_lock "$lock_dir"; then
  log_review "SKIP repo=$repo reason=already-running sha=$reviewed_sha"
  exit 0
fi

cleanup() {
  if [ -d "$worktree" ]; then
    git -C "$repo" worktree remove --force "$worktree" >/dev/null 2>&1 || true
  fi
  rm -rf "$lock_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

record_failure() {
  local reason="$1"
  local notification="$2"
  local attempts=0
  if [ -f "$failure_file" ]; then
    attempts="$(cat "$failure_file" 2>/dev/null || true)"
  fi
  case "$attempts" in
    ''|*[!0-9]*) attempts=0 ;;
  esac
  attempts=$((attempts + 1))
  printf '%s\n' "$attempts" > "$failure_file"
  log_review "ERROR repo=$repo reason=$reason attempt=$attempts max_attempts=$REVIEW_MAX_ATTEMPTS sha=$reviewed_sha"
  if [ "$attempts" -ge "$REVIEW_MAX_ATTEMPTS" ]; then
    {
      printf 'repo=%s\n' "$repo"
      printf 'slug=%s\n' "$slug"
      printf 'sha=%s\n' "$reviewed_sha"
      printf 'attempts=%s\n' "$attempts"
    } > "$giveup_file"
    log_review "GIVEUP repo=$repo reason=$reason attempts=$attempts sha=$reviewed_sha"
    notify_review "$slug" "$notification"
  fi
}

# The reviewing environment is shared by every repository, so its failures pause
# all work for a growing interval instead of exhausting one commit's attempts.
record_environment_problem() {
  local reason="$1"
  local notification="$2"
  local recorded failures delay
  recorded="$(record_environment_failure "$reason")"
  failures="${recorded%% *}"
  delay="${recorded##* }"
  log_review "ENVIRONMENT repo=$repo reason=$reason failures=$failures cooldown_seconds=$delay sha=$reviewed_sha"
  if [ "$failures" = "1" ]; then
    notify_review "$slug" "$notification"
  fi
}

codex_bin="$(find_codex || true)"
if [ -z "$codex_bin" ]; then
  record_environment_problem "codex-not-found" "Codex CLI was not found."
  exit 4
fi
if [ "${REVIEW_SKIP_AUTH_CHECK:-0}" != "1" ]; then
  if ! "$codex_bin" login status 2>&1 | grep -q 'Logged in using ChatGPT'; then
    record_environment_problem "codex-not-chatgpt-authenticated" \
      "Codex is not signed in with ChatGPT."
    exit 4
  fi
fi
clear_environment_failure

mkdir -p "$(dirname "$worktree")"
if [ -d "$worktree" ]; then
  git -C "$repo" worktree remove --force "$worktree" >/dev/null 2>&1 || rm -rf "$worktree"
fi
git -C "$repo" worktree prune >/dev/null 2>&1 || true
git -C "$repo" worktree add --detach "$worktree" "$reviewed_sha" >/dev/null

# The disposable worktree holds the reviewed commit, which does not carry the
# unversioned workflow artifacts. Copy the ones the reviewer must read.
copy_local_artifact() {
  local relative="$1"
  [ -n "$relative" ] || return 0
  [ -f "$repo/$relative" ] || return 0
  mkdir -p "$worktree/$(dirname "$relative")"
  cp "$repo/$relative" "$worktree/$relative"
}
copy_local_artifact "$spec_rel"
copy_local_artifact "$plan_rel"
copy_local_artifact "$self_review_rel"

prompt="You are the independent external reviewer. Review only commit $reviewed_sha in this repository. Read $AI_ROOT/WORKFLOW.md, $spec_rel, $plan_rel, .ai/project.md when present, and the self-review at $self_review_rel when that path is set. The workflow artifacts under .ai/ are unversioned local notes copied into this worktree, so never report their absence from the commit as a finding. Do not modify source files. You may run relevant checks in this disposable worktree. Focus on correctness, regressions, security, privacy, data loss, external side effects, compatibility, rollback, and missing tests. Ignore style-only preferences. The runner has already verified the live handoff state and exact implementation SHA; the workflow intentionally permits that state update to remain uncommitted, so do not report committed .ai/state/current.md handoff values as a finding. Return one complete Markdown report following $AI_ROOT/templates/external-review.md. The report must contain exactly one verdict line using APPROVED, APPROVED_WITH_NOTES, CHANGES_REQUIRED, or BLOCKED. Use stable finding IDs and include true check outcomes; unavailable checks are NOT_RUN, never PASSED. Reviewed commit must be the full SHA $reviewed_sha."

log_review "START repo=$repo slug=$slug sha=$reviewed_sha model=$REVIEW_MODEL reasoning=$REVIEW_REASONING"
rm -f "$result_file"
set +e
(cd "$worktree" && "$codex_bin" exec \
  --model "$REVIEW_MODEL" \
  --ephemeral \
  -c "model_reasoning_effort=\"$REVIEW_REASONING\"" \
  -c 'sandbox_mode="workspace-write"' \
  -o "$result_file" \
  "$prompt") >>"$LOG_ROOT/codex.log" 2>&1
codex_status=$?
set -e

if [ "$codex_status" -ne 0 ] || [ ! -s "$result_file" ]; then
  record_failure "codex-failed-exit-$codex_status" "External review failed."
  exit 5
fi
perl -pi -e 's/[ \t]+$//' "$result_file"
if ! grep -Eq '^Verdict: (APPROVED|APPROVED_WITH_NOTES|CHANGES_REQUIRED|BLOCKED)[[:space:]]*$' "$result_file"; then
  record_failure "invalid-review-contract" "External review returned no valid verdict."
  exit 5
fi

if [ "$(git -C "$repo" rev-parse HEAD)" != "$reviewed_sha" ]; then
  log_review "STALE repo=$repo reason=head-changed sha=$reviewed_sha result=$result_file"
  notify_review "$slug" "Review finished but HEAD moved; the result was not applied."
  exit 6
fi

mkdir -p "$repo/$(dirname "$review_rel")"
cp "$result_file" "$repo/$review_rel"

verdict="$(awk -F': ' '/^Verdict: / {print $2; exit}' "$result_file" | sed 's/[[:space:]]*$//')"
case "$verdict" in
  APPROVED|APPROVED_WITH_NOTES)
    review_status="external_review_done"
    next_action="AWAIT_PR_APPROVAL"
    ;;
  CHANGES_REQUIRED)
    review_status="changes_required"
    next_action="FIX_FINDINGS"
    ;;
  BLOCKED)
    review_status="blocked"
    next_action="RESOLVE_REVIEW_BLOCKER"
    ;;
esac
state_set "$state_file" status "$review_status"
state_set "$state_file" external_review "$review_rel"
state_set "$state_file" reviewed_commit "$reviewed_sha"
state_set "$state_file" last_updated "$(date '+%Y-%m-%d')"
state_set "$state_file" next_action "$next_action"

# Workflow artifacts are not versioned by default, so nothing is committed
# unless a project deliberately opts in.
if [ "${REVIEW_AUTO_COMMIT:-0}" = "1" ]; then
  if git -C "$repo" diff --cached --quiet; then
    git -C "$repo" add -- "$review_rel" .ai/state/current.md
    if git -C "$repo" diff --cached --check && \
       git -C "$repo" commit -m "docs: record external review for $slug" >>"$LOG_ROOT/reviewer.log" 2>&1; then
      log_review "COMMIT repo=$repo slug=$slug sha=$(git -C "$repo" rev-parse HEAD)"
    else
      git -C "$repo" restore --staged -- "$review_rel" .ai/state/current.md >/dev/null 2>&1 || true
      log_review "WARN repo=$repo reason=review-auto-commit-failed"
    fi
  else
    log_review "WARN repo=$repo reason=preexisting-staged-changes review-left-uncommitted"
  fi
fi

printf '%s\n' "$reviewed_sha" > "$completed_file"
rm -f "$failure_file" "$giveup_file" "$stalled_file"
# The report now lives in the repository, so the runtime copy is redundant.
rm -f "$result_file"
log_review "DONE repo=$repo slug=$slug reviewed_sha=$reviewed_sha verdict=$verdict review=$review_rel"
notify_review "$slug" "External review: $verdict"
