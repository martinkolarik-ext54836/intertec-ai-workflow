# Changelog

## 1.5.0 - 2026-08-12

- Separated environment failures from commit failures: a missing or signed-out
  Codex CLI now pauses all repositories for a growing interval and resumes on
  its own, instead of permanently abandoning every waiting commit.
- Reported a recorded review whose project still waits for one as a stalled
  handoff instead of skipping it silently forever.
- Made the unattended worker the default trigger, so no caller can accidentally
  restore unbounded retries, and added `--force` for a deliberate re-review.
- Made lock acquisition fail closed and made it survive PID reuse.
- Added runtime retention: rotating logs, expiring markers, deletion of review
  copies already committed to their repository, and `scripts/prune-runtime.sh`.
- Recorded that Git is the single source of truth: completed features are no
  longer archived into `.ai/state/archive/`, and superseded specs, plans, and
  reviews may be deleted from the working tree.
- Defined `next_action` as an enum with a separate `next_action_note`.
- Reported workflow version drift and unreachable review handoffs in
  `doctor.sh`, and environment cooldown and stalled handoffs in reviewer status.
- Extended CI to macOS and added PowerShell parsing and PSScriptAnalyzer checks.
- Translated the remaining Slovak reviewer notifications to English and allowed
  `REVIEW_MAX_ATTEMPTS=0` to mean no retry.

## 1.4.0 - 2026-08-09

- Bounded automatic reviewer failures to three attempts by default, with
  visible give-up markers and deliberate manual retry support.
- Mapped `CHANGES_REQUIRED` and `BLOCKED` verdicts to the corresponding
  `changes_required` and `blocked` workflow states.
- Added CI for Bash syntax, ShellCheck, and expanded reviewer automation tests
  covering failure limits, manual retries, verdict state, and auto-commit
  safety.

## 1.3.0 - 2026-08-03

- Added a Windows Task Scheduler installer, status command, manual review
  command, and uninstaller for the optional automatic reviewer.
- Reused the same Git Bash review engine on Windows so commit validation,
  locking, disposable worktrees, and stale-result protection remain identical
  across supported operating systems.
- Documented both project-level agent adapters in the recommended directory
  structure.
- Updated project and state templates to workflow version 1.3.0.

## 1.2.0 - 2026-08-03

- Made the workflow repository portable across users and project roots instead
  of generating user-specific absolute paths.
- Added a complete installation, onboarding, operating, updating, sharing, and
  troubleshooting guide.
- Made automatic-review model and reasoning settings configurable at install
  time while retaining the previous defaults.
- Updated project and state templates to workflow version 1.2.0.
- Made external design tools, including Figma, strictly opt-in.
- Clarified that approved Class C work proceeds through review and normal
  delivery without repeated approval prompts, while standalone production
  deployment still requires explicit authorization.

## 1.1.0 - 2026-07-16

- Added automatic external review for governed Class C features.
- Added a macOS LaunchAgent that scans project state once per minute.
- Bounded discovery to direct and one-level-nested project roots so background
  scans never traverse repository contents or mounted data.
- Added isolated commit review with `gpt-5.6-terra`, high reasoning, ephemeral
  Codex sessions, locking, deduplication, and stale-HEAD protection.
- Added manual review, service status, installer, uninstaller, and a fake-Codex
  integration test that consumes no model usage.

## 1.0.0 - 2026-07-16

- Established one shared workflow for repositories under a projects directory.
- Based the full feature lifecycle on an existing production workflow.
- Added three work classes: advisory, small safe change, and governed feature.
- Kept specs, plans, reviews, state, and project knowledge local to each repo.
- Added Codex and Claude Code entry points plus project init and doctor scripts.
