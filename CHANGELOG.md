# Changelog

## 1.1.0 - 2026-07-16

- Added automatic external review for governed Class C features.
- Added a macOS LaunchAgent that scans project state once per minute.
- Added isolated commit review with `gpt-5.6-terra`, high reasoning, ephemeral
  Codex sessions, locking, deduplication, and stale-HEAD protection.
- Added manual review, service status, installer, uninstaller, and a fake-Codex
  integration test that consumes no model usage.

## 1.0.0 - 2026-07-16

- Established one shared workflow for projects under `/Users/martin/Projects`.
- Based the full feature lifecycle on the intertec sales-agent workflow.
- Added three work classes: advisory, small safe change, and governed feature.
- Kept specs, plans, reviews, state, and project knowledge local to each repo.
- Added Codex and Claude Code entry points plus project init and doctor scripts.
