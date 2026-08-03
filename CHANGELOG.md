# Changelog

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
