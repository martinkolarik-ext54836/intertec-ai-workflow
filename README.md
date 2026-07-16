# Martin's shared AI workflow

This directory is the canonical, tool-neutral workflow for repositories under
`/Users/martin/Projects`.

## Sources of truth

- `WORKFLOW.md` defines how AI work is classified and executed.
- `templates/` contains shared artifact templates.
- `scripts/init-project.sh` initializes project-local AI metadata without
  overwriting existing instructions.
- `scripts/doctor.sh` checks whether repositories inherit or declare the
  workflow correctly.
- `scripts/status.sh` shows Git and workflow state for one repository.
- `scripts/install-root-adapters.sh` restores the generated root entry points.
- `scripts/install-reviewer.sh` installs the macOS automatic review service.
- `scripts/review-now.sh` runs a pending review immediately.
- `scripts/reviewer-status.sh` shows the LaunchAgent and recent reviewer logs.

Project-specific architecture, commands, deployment rules, and exceptions live
in `<project>/.ai/project.md`. Feature specs, plans, reviews, and state always
stay in the project repository that owns the code.

`/Users/martin/Projects/AGENTS.md` is the Codex entry point and
`/Users/martin/Projects/CLAUDE.md` is the Claude Code entry point.

## Initialize a repository

```bash
/Users/martin/Projects/.ai/scripts/init-project.sh /path/to/repository
```

The initializer is additive. It creates missing directories and starter files,
but never replaces an existing `AGENTS.md`, `CLAUDE.md`, or `.ai/project.md`.

## Validate the installation

```bash
/Users/martin/Projects/.ai/scripts/doctor.sh
```

## Automatic external review

The macOS LaunchAgent checks repositories up to two directory levels below
`/Users/martin/Projects` once per minute. It reviews only governed features
whose `.ai/state/current.md` contains:

```yaml
status: waiting_for_external_review
implementation_commit: <exact commit SHA>
```

The reviewer uses the existing ChatGPT-authenticated Codex CLI, not an API key.
It runs `gpt-5.6-terra` with high reasoning in an isolated disposable worktree.

Install or refresh the service:

```bash
/Users/martin/Projects/.ai/scripts/install-reviewer.sh
```

Inspect it or trigger the current project immediately:

```bash
/Users/martin/Projects/.ai/scripts/reviewer-status.sh
/Users/martin/Projects/.ai/scripts/review-now.sh /path/to/repository
```

The generated report is stored in the owning project under `.ai/reviews/` and
state advances to `external_review_done`. The worker commits only those two
workflow artifacts when the project's Git index was otherwise empty. It never
pushes, fixes findings, creates a PR, merges, or deploys.

## Versioning

This directory is a standalone Git repository. Change `VERSION` and
`CHANGELOG.md` whenever workflow behavior changes materially.
