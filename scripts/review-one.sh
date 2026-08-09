#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=review-common.sh
source "$SCRIPT_DIR/review-common.sh"

repo="${1:-}"
if [ -z "$repo" ] || [ ! -d "$repo" ]; then
  echo "Usage: review-one.sh /path/to/repository" >&2
  exit 2
fi
repo="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$repo" ]; then
  echo "Not a Git repository: $1" >&2
  exit 2
fi

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
if ! git -C "$repo" cat-file -e "$reviewed_sha:$spec_rel" 2>/dev/null || \
   ! git -C "$repo" cat-file -e "$reviewed_sha:$plan_rel" 2>/dev/null; then
  log_review "SKIP repo=$repo reason=spec-plan-not-in-commit slug=$slug sha=$reviewed_sha"
  exit 3
fi

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
result_file="$RUNTIME_ROOT/results/$identifier.md"
worktree="$RUNTIME_ROOT/worktrees/$identifier"

if [ "${REVIEW_TRIGGER:-manual}" != "worker" ]; then
  rm -f "$failure_file" "$giveup_file"
  log_review "RESET repo=$repo reason=manual-retry sha=$reviewed_sha"
fi

if [ -f "$completed_file" ]; then
  log_review "SKIP repo=$repo reason=already-completed sha=$reviewed_sha"
  exit 0
fi
if [ -f "$giveup_file" ]; then
  log_review "SKIP repo=$repo reason=attempts-exhausted sha=$reviewed_sha"
  exit 0
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

codex_bin="$(find_codex || true)"
if [ -z "$codex_bin" ]; then
  record_failure "codex-not-found" "Codex CLI nebol nájdený."
  exit 4
fi
if [ "${REVIEW_SKIP_AUTH_CHECK:-0}" != "1" ]; then
  if ! "$codex_bin" login status 2>&1 | grep -q 'Logged in using ChatGPT'; then
    record_failure "codex-not-chatgpt-authenticated" "Codex nie je prihlásený cez ChatGPT."
    exit 4
  fi
fi

mkdir -p "$(dirname "$worktree")"
if [ -d "$worktree" ]; then
  git -C "$repo" worktree remove --force "$worktree" >/dev/null 2>&1 || rm -rf "$worktree"
fi
git -C "$repo" worktree prune >/dev/null 2>&1 || true
git -C "$repo" worktree add --detach "$worktree" "$reviewed_sha" >/dev/null

prompt="You are the independent external reviewer. Review only commit $reviewed_sha in this repository. Read $AI_ROOT/WORKFLOW.md, $spec_rel, $plan_rel, .ai/project.md when present, and the self-review referenced by state when present. Do not modify source files. You may run relevant checks in this disposable worktree. Focus on correctness, regressions, security, privacy, data loss, external side effects, compatibility, rollback, and missing tests. Ignore style-only preferences. The runner has already verified the live handoff state and exact implementation SHA; the workflow intentionally permits that state update to remain uncommitted, so do not report committed .ai/state/current.md handoff values as a finding. Return one complete Markdown report following $AI_ROOT/templates/external-review.md. The report must contain exactly one verdict line using APPROVED, APPROVED_WITH_NOTES, CHANGES_REQUIRED, or BLOCKED. Use stable finding IDs and include true check outcomes; unavailable checks are NOT_RUN, never PASSED. Reviewed commit must be the full SHA $reviewed_sha."

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
  record_failure "codex-failed-exit-$codex_status" "External review zlyhalo."
  exit 5
fi
perl -pi -e 's/[ \t]+$//' "$result_file"
if ! grep -Eq '^Verdict: (APPROVED|APPROVED_WITH_NOTES|CHANGES_REQUIRED|BLOCKED)[[:space:]]*$' "$result_file"; then
  record_failure "invalid-review-contract" "Review nemá platný verdict."
  exit 5
fi

if [ "$(git -C "$repo" rev-parse HEAD)" != "$reviewed_sha" ]; then
  log_review "STALE repo=$repo reason=head-changed sha=$reviewed_sha result=$result_file"
  notify_review "$slug" "Review dokončené, ale HEAD sa zmenil; výsledok nebol aplikovaný."
  exit 6
fi

mkdir -p "$repo/$(dirname "$review_rel")"
cp "$result_file" "$repo/$review_rel"
state_set "$state_file" status external_review_done
state_set "$state_file" external_review "$review_rel"
state_set "$state_file" reviewed_commit "$reviewed_sha"
state_set "$state_file" last_updated "$(date '+%Y-%m-%d')"

verdict="$(awk -F': ' '/^Verdict: / {print $2; exit}' "$result_file" | sed 's/[[:space:]]*$//')"
case "$verdict" in
  APPROVED|APPROVED_WITH_NOTES) next_action="AWAIT_PR_APPROVAL" ;;
  CHANGES_REQUIRED) next_action="FIX_FINDINGS" ;;
  BLOCKED) next_action="RESOLVE_REVIEW_BLOCKER" ;;
esac
state_set "$state_file" next_action "$next_action"

if [ "${REVIEW_AUTO_COMMIT:-1}" = "1" ]; then
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
rm -f "$failure_file" "$giveup_file"
log_review "DONE repo=$repo slug=$slug reviewed_sha=$reviewed_sha verdict=$verdict review=$review_rel"
notify_review "$slug" "External review: $verdict"
