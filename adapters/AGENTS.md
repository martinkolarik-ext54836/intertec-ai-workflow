# Shared AI Workflow Entry Point

These instructions apply to repositories under `__PROJECTS_ROOT__`.

Before acting, read `__WORKFLOW_PATH__` completely. Use its
three work classes and the lightest safe workflow. Then read the nearest
repository `.ai/project.md` and any more specific `AGENTS.md`.

Shared workflow configuration belongs in `__WORKFLOW_ROOT__`. Project architecture,
commands, specs, plans, reviews, state, and deployment history belong in the
repository that owns the code.

Never overwrite or discard unrelated dirty worktree changes. More specific
project instructions may add constraints but must not silently weaken shared
safety, secret, production, or approval gates.
