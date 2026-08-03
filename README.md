# Shared AI Engineering Workflow

A tool-neutral workflow for using coding agents safely across multiple Git
repositories. It supports Codex, Claude Code, and other agents that can read
repository instruction files.

The workflow separates small work from risky features, keeps project knowledge
inside each project, preserves dirty worktrees, records real verification
results, and can optionally run an independent Codex review in a disposable Git
worktree.

## What to share

Send the recipient this repository URL:

```text
https://github.com/martinkolarik-ext54836/intertec-ai-workflow
```

If the repository is private, first grant the recipient GitHub access. They do
not need any of your application repositories, local logs, credentials, or
project data. This repository contains only the shared workflow, templates, and
installer/reviewer scripts.

## How it is organized

Install the repository as `.ai` directly under a directory containing projects:

```text
<projects-root>/
├── .ai/                 # this repository
├── AGENTS.md            # generated root adapter for Codex
├── CLAUDE.md            # generated root adapter for Claude Code
├── project-a/
│   ├── AGENTS.md        # project adapter for Codex
│   ├── CLAUDE.md        # project adapter for Claude Code
│   └── .ai/
│       ├── project.md
│       ├── specs/
│       ├── plans/
│       ├── reviews/
│       └── state/
└── project-b/
    ├── AGENTS.md
    ├── CLAUDE.md
    └── .ai/
        └── project.md
```

Shared policy stays in this repository. Architecture, commands, decisions,
feature plans, reviews, and deployment history stay in the project that owns
the code.

## Requirements

Core workflow:

- Git
- Bash
- Perl
- Codex, Claude Code, or another coding agent that reads instruction files

Optional automatic reviewer:

- macOS with `launchd`, or Windows with Task Scheduler and Git for Windows
- Codex CLI installed and authenticated through ChatGPT
- access to the configured review model

The automatic reviewer uses the recipient's own local Codex authentication. No
API key or credential is stored in this repository.

## Install

Choose the directory under which the recipient keeps Git repositories. This
example uses `~/Projects`:

```bash
export PROJECTS_ROOT="$HOME/Projects"
mkdir -p "$PROJECTS_ROOT"
git clone https://github.com/martinkolarik-ext54836/intertec-ai-workflow.git \
  "$PROJECTS_ROOT/.ai"
cd "$PROJECTS_ROOT/.ai"
./scripts/install-root-adapters.sh
./scripts/doctor.sh
```

`install-root-adapters.sh` writes `AGENTS.md` and `CLAUDE.md` in
`<projects-root>`. Inspect or merge those files manually first if files with
those names already contain custom root-level instructions.

The checkout may technically use another name, but `.ai` is recommended and is
required by the supplied root `CLAUDE.md` adapter.

## Initialize a project

Run the additive initializer for every repository that should use the workflow:

```bash
"$PROJECTS_ROOT/.ai/scripts/init-project.sh" "/path/to/repository"
```

The initializer creates missing project-local directories and starter files.
It does not replace an existing project `AGENTS.md`, `CLAUDE.md`, or
`.ai/project.md`.

Then edit `<repository>/.ai/project.md` and record verified project facts:

- architecture and important directories;
- canonical fast, full, frontend, and deployment commands;
- project-specific safety and UI conventions;
- delivery policy;
- production and data restrictions.

Commit the generated project-local files to that project's repository so every
collaborator and agent sees the same context.

## How agents use it

At the beginning of work, the agent reads:

1. `WORKFLOW.md` from this repository;
2. the nearest project `AGENTS.md` or `CLAUDE.md`;
3. `<project>/.ai/project.md`;
4. `<project>/.ai/state/current.md` only when continuing an active governed
   feature.

Work is classified into three levels:

| Class | Use for | Required process |
|---|---|---|
| A | Questions, inspection, diagnosis | Read-only investigation and answer |
| B | Clear, localized, low-risk changes | Implement, run relevant checks, self-review |
| C | Features, risky or broad changes | Spec, plan approval, implementation, checks, independent review, delivery |

For Class C, the normal lifecycle is:

```text
request → spec/plan → one approval → implementation → self-review
→ committed SHA → independent review → PR/merge → deployment → archive
```

The agent must record unavailable checks as `NOT_RUN`, preserve unrelated user
changes, avoid committing secrets or production data, and never claim that a
commit, merge, or deployment happened without verification.

The complete rules and approval boundaries are in [WORKFLOW.md](WORKFLOW.md).

## Project artifacts

The workflow uses this project-local structure. The initializer creates the
required directories and starter context; feature-specific files appear only
when needed:

```text
.ai/
├── project.md
├── backlog.md                 # optional future ideas
├── specs/                     # approved feature requirements
├── plans/                     # implementation plans and checks
├── reviews/                   # self-review and external review reports
└── state/
    ├── current.md             # at most one active governed feature
    ├── archive/               # completed or parked features
    └── deployments.md         # optional deployment history
```

Templates are available in this repository's `templates/` directory.

## Useful commands

```bash
# Initialize or inspect a project
./scripts/init-project.sh /path/to/repository
./scripts/status.sh /path/to/repository

# Validate the shared installation and initialized repositories
./scripts/doctor.sh

# Test the automatic-review orchestration without model usage
./scripts/test-review-automation.sh
```

To omit known unrelated repositories from `doctor.sh`, provide an extended
regular expression:

```bash
AI_DOCTOR_IGNORE_REGEX='/vendor/|/archive/' ./scripts/doctor.sh
```

## Optional automatic external review

The reviewer is not required to use the core workflow. On macOS and Windows, it
can scan repositories directly below `<projects-root>` or one directory deeper
once per minute. It acts only when `.ai/state/current.md` contains both:

```yaml
status: waiting_for_external_review
implementation_commit: <exact current HEAD SHA>
```

Before installing it, verify the Codex CLI login:

```bash
codex login status
```

### macOS (`launchd`)

Install with the default model and reasoning level:

```bash
./scripts/install-reviewer.sh
```

Or select a model available to that Codex installation:

```bash
REVIEW_MODEL="gpt-5.6-terra" REVIEW_REASONING="high" \
  ./scripts/install-reviewer.sh
```

Operate the reviewer:

```bash
./scripts/reviewer-status.sh
./scripts/review-now.sh /path/to/repository
./scripts/uninstall-reviewer.sh
```

### Windows (Task Scheduler)

Install Git for Windows and run these commands from PowerShell. The installer
uses Git Bash for the shared review engine and registers a per-user scheduled
task; administrator rights are not required. Like the macOS user LaunchAgent,
the task runs only while that user is signed in.

```powershell
cd "$env:USERPROFILE\Projects\.ai"
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\install-reviewer-windows.ps1
```

To select another project root, model, or reasoning level:

```powershell
.\scripts\install-reviewer-windows.ps1 `
  -ProjectsRoot "D:\Projects" `
  -Model "gpt-5.6-terra" `
  -Reasoning "high"
```

Operate the Windows reviewer:

```powershell
.\scripts\reviewer-status-windows.ps1
.\scripts\review-now-windows.ps1 -Repository "D:\Projects\my-project"
.\scripts\uninstall-reviewer-windows.ps1
```

The Windows installer stores non-secret settings, logs, locks, and completed
review markers under `%LOCALAPPDATA%\SharedAIReviewer`. It stores no ChatGPT
credentials or API keys. Set `BASH_EXE` before installation only when Git Bash
is installed in a non-standard location.

The reviewer:

- uses an ephemeral Codex session separate from the implementing conversation;
- reviews one exact committed SHA in a disposable Git worktree;
- writes the report into the owning project's `.ai/reviews/` directory;
- may commit only the review and workflow state when the Git index was already
  empty;
- never pushes, fixes source, creates a PR, merges, or deploys.

Its defaults can also be controlled with `PROJECTS_ROOT`, `REVIEW_MODEL`,
`REVIEW_REASONING`, `REVIEW_RUNTIME_ROOT`, `REVIEW_LOG_ROOT`, `CODEX_BIN`,
`REVIEW_NOTIFY`, `REVIEW_AUTO_COMMIT`, `REVIEW_SERVICE_LABEL`, and
`REVIEW_SERVICE_PLIST`.

## Updating an installation

```bash
cd "$PROJECTS_ROOT/.ai"
git pull --ff-only
./scripts/install-root-adapters.sh
./scripts/doctor.sh
```

If automatic review is installed and reviewer scripts or settings changed,
refresh its service definition. On macOS run:

```bash
./scripts/install-reviewer.sh
```

On Windows run:

```powershell
.\scripts\install-reviewer-windows.ps1
```

Existing project `.ai/project.md` files are intentionally not overwritten by an
upgrade. Compare them with `templates/project.md` when adopting new fields.

## Troubleshooting

- **Agent ignores the workflow:** confirm the root and project instruction files
  exist and run `./scripts/doctor.sh`.
- **Reviewer does not start:** run `./scripts/reviewer-status.sh` on macOS or
  `.\scripts\reviewer-status-windows.ps1` on Windows, then inspect the printed
  runtime and log locations.
- **Git Bash is not found on Windows:** install Git for Windows or set
  `BASH_EXE` to its `bash.exe` before running the installer.
- **Review is skipped:** verify that state is exactly
  `waiting_for_external_review`, `implementation_commit` equals `git rev-parse
  HEAD`, and the spec and plan are committed under `.ai/`.
- **Codex is not found:** set `CODEX_BIN` to an executable Codex CLI path and
  reinstall the reviewer.
- **Configured model is unavailable:** reinstall with a supported
  `REVIEW_MODEL`.
- **Repository already has AI instructions:** merge the shared entry-point
  requirements into those files rather than deleting project-specific rules.

## Versioning this workflow

Behavior changes require all three:

1. update the version in `WORKFLOW.md` and `VERSION`;
2. add an entry to `CHANGELOG.md`;
3. run shell syntax checks, the integration test, and `git diff --check` before
   committing.

Project feature history and confidential project context must never be added to
this shared repository.
