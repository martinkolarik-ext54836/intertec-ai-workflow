# Shared AI Engineering Workflow

Version: 1.8.0

This is the canonical workflow for AI-assisted work in a shared projects
directory. It is tool-neutral and applies to Codex, Claude Code, and other
coding agents.

In this document, `<workflow-root>` means the directory containing this file
and `<projects-root>` means its parent directory. The recommended checkout path
is `<projects-root>/.ai`.

## Instruction order

Before acting in a repository:

1. Read this file completely.
2. Read the nearest repository `AGENTS.md` or `CLAUDE.md` instructions.
3. Read `<repo>/.ai/project.md` when it exists.
4. Read `<repo>/.ai/state/current.md` only for active governed features.
5. Preserve existing user changes and never treat a dirty tree as disposable.

The shared workflow controls lifecycle and safety. Repository files control
architecture, commands, deployment details, and stricter project exceptions.
Project instructions may be stricter but must not silently weaken safety rules
or disable the default delivery lifecycle except for a documented technical or
safety constraint. The user can always explicitly limit delivery for the
current request.

## Classify work by user intent

Default to direct execution. A normal request to change, fix, build, or add
something authorizes the complete documented delivery lifecycle by default:
implementation, checks, commit, push, PR, merge, deployment, and production
verification. The user opts out by explicitly forbidding or limiting delivery.
Do not create specs, plans, state, reviews, or security audits merely because
work is multi-file, behavioral, or substantial.

Standalone operational words remain literal when no code or configuration
change was requested:

- `run` or `continue` means run or continue the existing operation;
- `commit` means commit the requested changes only;
- `push` means push the requested branch only;
- `merge` means merge the requested change only;
- `deploy` means deploy through the documented project command only.

### Class A: advisory or diagnostic

Use when the user asks a question, requests explanation, review, investigation,
or status and has not asked for a change.

- Inspect read-only evidence and answer directly.
- Do not create workflow artifacts.
- Do not mutate code, external systems, Git history, or production.
- If the diagnosis reveals a fix, explain it; implement only when requested.

### Class B: direct execution (default)

Use for every requested change or operation that is not an explicitly requested
new feature and does not cross a stop-and-ask safety boundary. Size, file count,
and behavioral impact alone do not promote work to Class C.

Examples include bug fixes, maintenance, refactors, UI changes, existing-script
work, operational commands, branch cleanup, and explicit commit/push/merge/
deploy requests.

Workflow:

1. Inspect the affected code and working tree.
2. State the intended action briefly; no workflow artifact is required.
3. Implement only the requested scope.
4. Run relevant project checks and `git diff --check`.
5. Inspect the actual diff or result for obvious mistakes.
6. Complete the repository's documented delivery lifecycle through production
   deployment and verification unless the user explicitly opts out.
7. Report outcome, checks, files, delivery state, and residual risk.

Do not create `.ai/specs`, `.ai/plans`, `.ai/reviews`, or `.ai/state` artifacts
for Class B. Do not start an external reviewer or security cycle. A requested
change includes automatic commit, push, PR, merge, and documented deployment;
skip only stages that do not exist for that repository or that the user has
explicitly prohibited.

### Class C: explicit new feature or governed work

Use only when one of these is true:

- the user explicitly asks to create, build, or add a new feature;
- the user explicitly requests a plan, governed workflow, independent review,
  security audit, or full delivery lifecycle;
- the work crosses a stop-and-ask boundary such as destructive data changes,
  authentication/authorization, secrets, dependencies, schema, public API,
  production configuration, infrastructure, or scheduling.

Do not use Class C merely because a fix is broad, touches many files, changes
behavior, or needs careful implementation. If classification is genuinely
ambiguous, prefer Class B unless a stop-and-ask boundary is involved.

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
7. For an explicit new feature or requested independent review, commit the
   completed implementation locally so an exact SHA can be reviewed.
8. When independent review is required, set state to
   `waiting_for_external_review` and record the exact commit SHA in
   `implementation_commit`. State is never committed; see "Retention".

#### External review phase

Run this phase only for an explicitly requested new feature, when the user asks
for review/audit/full lifecycle, or when an approved plan explicitly requires
it. Never trigger it for Class B work.

- Review a committed SHA, not an uncommitted implementation.
- Prefer a fresh session/model that did not build the feature. The optional
  local automatic reviewer uses an ephemeral, separately configured Codex
  session isolated from the builder conversation.
- Compare the committed diff with the approved spec and plan.
- Run the same canonical checks and record actual results.
- Save `.ai/reviews/YYYY-MM-DD-slug-external-review.md`.
- Findings use stable IDs and severities: `BLOCKER`, `IMPORTANT`, `MINOR`, `NOTE`.
- Verdict is `APPROVED`, `APPROVED_WITH_NOTES`, `CHANGES_REQUIRED`, or `BLOCKED`.
- Automatically resolve non-controversial findings. Escalate only changes to
  approved behavior, safety gates, accepted risks, or genuine product choices.

For repositories up to two directory levels below `<projects-root>`, the
optional installed review worker scans once per minute and acts only when all
of these are true:

- state is exactly `waiting_for_external_review`;
- `implementation_commit` resolves to a commit and equals current `HEAD`;
- the referenced spec and plan exist in the working tree;
- no review has already completed for that repository and SHA.

The worker reviews the SHA in a disposable Git worktree. It never sends the
builder conversation to the reviewer. It may run checks and create temporary
artifacts only in that disposable worktree. It applies the report only if the
project still points to the reviewed SHA, then updates state to
`external_review_done`, `changes_required`, or `blocked` according to the
verdict. Class A and Class B work never triggers this automation.

Failures are bounded and are attributed to their real cause. A commit whose
review keeps failing is abandoned after `REVIEW_MAX_ATTEMPTS` attempts and
reported as a give-up entry. A broken reviewing environment, such as a missing
or signed-out Codex CLI, instead pauses every repository for a growing interval
and resumes on its own once the environment works again. A commit that already
has a recorded review while its project still asks for one is reported as a
stalled handoff rather than skipped silently.

Manual trigger and service status:

```bash
<workflow-root>/scripts/review-now.sh /path/to/repository
<workflow-root>/scripts/review-now.sh --force /path/to/repository
<workflow-root>/scripts/reviewer-status.sh
```

On Windows PowerShell:

```powershell
<workflow-root>\scripts\review-now-windows.ps1 -Repository C:\path\to\repository
<workflow-root>\scripts\review-now-windows.ps1 -Repository C:\path\to\repository -Force
<workflow-root>\scripts\reviewer-status-windows.ps1
```

A manual trigger is always a deliberate retry: it clears give-up state and
ignores the environment cooldown. `--force` additionally reviews a commit whose
review was already recorded.

#### Delivery phase

- Approval to implement a change authorizes its complete documented delivery
  lifecycle through production verification unless the user explicitly opts
  out of one or more stages.
- Commit the scoped change, push its branch, create the PR, merge after required
  checks/reviews pass, and deploy automatically when those mechanisms exist.
- Never include unrelated dirty work in a commit or deployment. Use a clean
  worktree or another repository-documented isolation mechanism when needed.
- Use only the repository's documented deploy command. If none exists, report
  deployment as blocked instead of inventing one.
- A failed check, review, merge, deployment, or smoke test stops the lifecycle;
  diagnose and safely repair it when possible, otherwise report the blocker.
- Standalone requests such as `commit`, `push`, `merge`, or `deploy`, without an
  accompanying change request, authorize only the named operation.
- After the final delivery stage completes, reset
  `.ai/state/current.md` to the empty template. Do not copy it anywhere; see
  "Retention".

## Retention

Specs, plans, reviews, and state are development scaffolding, not deliverables.
They stay on the machine doing the work and are never committed. What the
repository records is the change itself: the code, the tests, the commit
messages, the PR, and the merge.

Keep out of version control, via `.gitignore`:

```gitignore
.ai/specs/
.ai/plans/
.ai/reviews/
.ai/state/
```

Keep in version control, because every agent and collaborator needs them:

- `.ai/project.md`
- `AGENTS.md` and `CLAUDE.md`

Consequences to respect:

- Never make committing a workflow artifact a review, merge, or deploy gate.
- Never reconstruct history from these files; use Git history for that.
- Delete a spec, plan, or review as soon as its feature is delivered.
- `.ai/state/archive/` is only for a feature deliberately parked while
  unfinished. Delete the file when that work resumes or is abandoned.
- The reviewer reads the spec and plan from the working tree, copies them into
  its disposable worktree, and commits nothing by default.
- The reviewer's runtime directory is a disposable cache. Nothing in it is a
  source of truth, its logs rotate, and its markers and leftover reports expire
  after `REVIEW_RETENTION_DAYS`.

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
- `blocked`
- `waiting_for_external_review`
- `external_review_done`
- `awaiting_pr_approval`
- `pr_created`
- `awaiting_merge_approval`
- `merged`
- `deployed`
- `parked`

## Next actions

`next_action` is a machine-readable enum, so automation and humans read the
same handoff. Put any explanation in `next_action_note`, never in the field
itself.

- `NONE`
- `AWAIT_PLAN_APPROVAL`
- `IMPLEMENT`
- `FIX_FINDINGS`
- `RESOLVE_REVIEW_BLOCKER`
- `AWAIT_EXTERNAL_REVIEW`
- `AWAIT_PR_APPROVAL`
- `AWAIT_MERGE_APPROVAL`
- `DEPLOY`
- `VERIFY_DEPLOYMENT`

## Stop and ask first

Even after plan approval, stop before:

- destructive migrations, schema rebuilds, data deletion, or history rewrite;
- authentication, authorization, permissions, credentials, or secrets changes;
- adding, removing, or upgrading dependencies;
- production configuration, DNS, scheduler, or infrastructure changes outside
  the repository's already documented deployment procedure;
- public/consumed API or persisted-schema changes not explicitly approved;
- external messages, purchases, irreversible writes, or broad side effects;
- broad refactors outside approved scope;
- a delivery step that would bypass required checks, branch protection, or the
  repository's documented deployment procedure;
- any unresolved user-visible product decision.

An approved spec may explicitly authorize a schema, API, dependency, or config
change. It does not implicitly authorize destructive operations or an unrelated
production/data mutation. Approval to implement does include the normal scoped
push, PR, merge, deployment, and verification lifecycle defined above.

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
- Do not start a security audit or security-review cycle for ordinary work.
  Run one only when the user asks for it or the requested change directly
  affects authentication, authorization, permissions, credentials, secrets, or
  another explicitly security-sensitive boundary.
- Use read-only, minimum-data production inspection during diagnosis/review.
- Do not place customer PII or raw production rows in AI workflow artifacts.
- Sanitize logs, screenshots, fixtures, and review evidence.
- Production writes must be intentional and scoped. A user-requested change
  authorizes its normal documented deployment, but not unrelated data mutation.

## External design tools are opt-in only

- Use Figma or another external design workspace only when the user explicitly
  requests that tool or supplies its design as an input/reference.
- A frontend, UI, styling, layout, component, or visual code change does not by
  itself authorize or require Figma.
- Never add a Figma deliverable to a spec, plan, completion contract, review
  gate, merge gate, or deployment gate unless the user explicitly requested it.
- If a generic tool instruction recommends Figma for UI work but the user did
  not request Figma, follow this project workflow and complete the code change
  without Figma.

## Checks and reporting

- Prefer one canonical check script declared by `.ai/project.md`.
- Run only checks relevant to the change, except when project policy requires the
  full suite.
- Do not invent commands. If required verification is unavailable, record the
  gap and its consequence.
- Every final implementation report states: outcome, checks with true results,
  commit/branch and deployment when applicable, residual risk, and any blocker.

## Project-local artifacts

Shared policy and templates live in `<workflow-root>`. The following
always belong to the repository that owns the change:

- `.ai/project.md` (versioned)
- `.ai/backlog.md` (versioned)
- `.ai/specs/` (local only)
- `.ai/plans/` (local only)
- `.ai/reviews/` (local only)
- `.ai/state/current.md` (local only)
- `.ai/state/archive/` (local only, parked features)
- `.ai/state/deployments.md` (local only)

Never store project feature history in the central workflow repository.
