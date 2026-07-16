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

## Versioning

This directory is a standalone Git repository. Change `VERSION` and
`CHANGELOG.md` whenever workflow behavior changes materially.
