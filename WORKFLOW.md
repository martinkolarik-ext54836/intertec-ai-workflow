# Shared AI Engineering Workflow

Version: 1.1.0

This is the canonical workflow for AI-assisted work in Martin's projects. It is
tool-neutral and applies to Codex, Claude Code, and other coding agents.

## Instruction order

Before acting in a repository:

1. Read this file completely.
2. Read the nearest repository `AGENTS.md` or `CLAUDE.md` instructions.
3. Read `<repo>/.ai/project.md` when it exists.
4. Read `<repo>/.ai/state/current.md` only for active governed features.
5. Preserve existing user changes and never treat a dirty tree as disposable.

The shared workflow controls lifecycle and safety. Repository files control
architecture, commands, deployment details, and stricter project exceptions.
Project instructions may be stricter but must not silently weaken safety rules.

## Classify work before creating artifacts

Use the lightest class that safely fits the request. Do not create specs, plans,
or reviews merely because a request contains words such as "fix" or "change".

### Class A: advisory or diagnostic

Use when the user asks a question, requests explanation, review, investigation,
or status and has not asked for a change.

- Inspect read-only evidence and answer directly.
- Do not create workflow artifacts.
- Do not mutate code, external systems, Git history, or production.
- If the diagnosis reveals a fix, explain it; implement only when requested.

### Class B: small safe change

Use only when all of the following are true:

- The desired result is clear and localized.
- The change is easy to review and reverse.
- It does not alter authentication, authorization, secrets, dependencies,
  database schema, public API contracts, production configuration, deployment,
  scheduled jobs, or external-system behavior.
- It does not delete data/files or require a product decision.

Examples: copy change, a narrow UI adjustment, a local validation fix, a test
expectation correction, or a small non-public refactor required by the fix.

Workflow:

1. Inspect the affected code and working tree.
2. State the intended small change briefly; no spec or plan file is required.
3. Implement only the requested scope.
4. Run relevant project checks and `git diff --check`.
5. Self-review the actual diff and fix non-controversial findings.
6. Report outcome, checks, files, and residual risk.

Do not create `.ai/specs`, `.ai/plans`, or `.ai/reviews` artifacts for Class B.
Commit or push only when the user requested it or `.ai/project.md` explicitly
authorizes automatic delivery for small changes.

If any Class B condition stops being true, reclassify as Class C before making
the risky or broad change.

### Class C: governed feature or risky change

Use for new features, multi-file behavioral changes, ambiguous work, broad
refactors, and anything involving a gate listed under "Stop and ask first".

#### Plan phase: one approval question

1. Scan repository structure, affected code, current state, and recent history.
2. Create `.ai/specs/YYYY-MM-DD-slug.md` from the shared spec template.
3. Create `.ai/plans/YYYY-MM-DD-slug.md` from the shared plan template.
4. Record assumptions, scope/non-scope, checks, risk, and rollback.
5. Update `.ai/state/current.md` to `awaiting_plan_approval`.
6. Ask exactly one implementation question: "Implement this plan?"

Do not implement before approval. Explicit user approval of the presented plan
is sufficient; do not ask for duplicate approval.

#### Build phase: autonomous after approval

1. Create or use the feature branch required by `.ai/project.md`.
2. Set state to `implementing`.
3. Implement the approved plan with focused tests and only necessary support.
4. Run the canonical project checks. Record true results; unavailable is
   `NOT_RUN`, never `PASSED`.
5. Write `.ai/reviews/YYYY-MM-DD-slug-self-review.md`.
6. Automatically fix non-controversial self-review findings and rerun checks.
7. Commit the completed implementation when project policy allows it.
8. Set state to `waiting_for_external_review` and record the exact commit SHA in
   `implementation_commit`. This state update may remain uncommitted until the
   automated reviewer records its report.

#### External review phase

- Review a committed SHA, not an uncommitted implementation.
- Prefer a fresh session/model that did not build the feature. The local
  automatic reviewer uses an ephemeral `gpt-5.6-terra` session with high
  reasoning, isolated from the builder conversation.
- Compare the committed diff with the approved spec and plan.
- Run the same canonical checks and record actual results.
- Save `.ai/reviews/YYYY-MM-DD-slug-external-review.md`.
- Findings use stable IDs and severities: `BLOCKER`, `IMPORTANT`, `MINOR`, `NOTE`.
- Verdict is `APPROVED`, `APPROVED_WITH_NOTES`, `CHANGES_REQUIRED`, or `BLOCKED`.
- Automatically resolve non-controversial findings. Escalate only changes to
  approved behavior, safety gates, accepted risks, or genuine product choices.

For repositories up to two directory levels below `/Users/martin/Projects`, the
installed review worker scans once per minute and acts only when all of these
are true:

- state is exactly `waiting_for_external_review`;
- `implementation_commit` resolves to a commit and equals current `HEAD`;
- no review has already completed for that repository and SHA.

The worker reviews the SHA in a disposable Git worktree. It never sends the
builder conversation to the reviewer. It may run checks and create temporary
artifacts only in that disposable worktree. It applies the report only if the
project still points to the reviewed SHA, then updates state to
`external_review_done`. Class A and Class B work never triggers this automation.

Manual trigger and service status:

```bash
/Users/martin/Projects/.ai/scripts/review-now.sh /path/to/repository
/Users/martin/Projects/.ai/scripts/reviewer-status.sh
```

#### Delivery phase

- PR creation requires explicit approval unless the user already requested the
  full PR workflow in the current task.
- Merge and production deployment always require explicit approval.
- Use only the repository's documented deploy command.
- Run the documented smoke check and record the deployed commit.
- Archive completed state at `.ai/state/archive/YYYY-MM-DD-slug.md`.

## One governed feature in flight

`.ai/state/current.md` represents one active Class C feature. Finish it before
starting another, or explicitly park it in `.ai/state/archive/` with status and
next action. Later ideas belong in `.ai/backlog.md`, not speculative detailed
plans that will become stale.

## Statuses

- `spec_created`
- `awaiting_plan_approval`
- `implementing`
- `changes_required`
- `waiting_for_external_review`
- `external_review_done`
- `awaiting_pr_approval`
- `pr_created`
- `awaiting_merge_approval`
- `merged`
- `deployed`
- `parked`

## Stop and ask first

Even after plan approval, stop before:

- destructive migrations, schema rebuilds, data deletion, or history rewrite;
- authentication, authorization, permissions, credentials, or secrets changes;
- adding, removing, or upgrading dependencies;
- production configuration, DNS, deployment, scheduler, or infrastructure work;
- public/consumed API or persisted-schema changes not explicitly approved;
- external messages, purchases, irreversible writes, or broad side effects;
- broad refactors outside approved scope;
- PR creation, merge, or deployment unless already explicitly requested;
- any unresolved user-visible product decision.

An approved spec may explicitly authorize a schema, API, dependency, or config
change. It does not implicitly authorize production deployment or destructive
operations.

## Git and worktree safety

- Inspect `git status` before editing.
- Preserve unrelated user changes and untracked files.
- Never use destructive Git commands to clean a tree.
- Keep feature diffs scoped; avoid formatting churn and opportunistic cleanup.
- Never claim work is committed, pushed, merged, clean, or deployed without
  verifying it.
- Before handoff, explicitly report remaining tracked and untracked changes.

## Security and production data

- Never commit `.env`, credentials, tokens, private keys, or production exports.
- Use read-only, minimum-data production inspection during diagnosis/review.
- Do not place customer PII or raw production rows in AI workflow artifacts.
- Sanitize logs, screenshots, fixtures, and review evidence.
- Production writes must be intentional, scoped, and explicitly authorized.

## Checks and reporting

- Prefer one canonical check script declared by `.ai/project.md`.
- Run only checks relevant to the change, except when project policy requires the
  full suite.
- Do not invent commands. If required verification is unavailable, record the
  gap and its consequence.
- Every final implementation report states: outcome, checks with true results,
  commit/branch when applicable, residual risk, and the next approval if any.

## Project-local artifacts

Shared policy and templates live in `/Users/martin/Projects/.ai`. The following
always belong to the repository that owns the change:

- `.ai/project.md`
- `.ai/backlog.md`
- `.ai/specs/`
- `.ai/plans/`
- `.ai/reviews/`
- `.ai/state/current.md`
- `.ai/state/archive/`
- `.ai/state/deployments.md`

Never store project feature history in the central workflow repository.
