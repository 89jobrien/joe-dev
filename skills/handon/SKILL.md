---
name: handon
description: This skill should be used when the user asks to "start session", "orient to work",
  "what's outstanding", "read handoff", "what was I working on", "pick up where I left off",
  or at session start when the joe-secrets SessionStart hook fires to surface outstanding work.
---

# handon

Read `HANDOFF.yaml` files across active repos, triage items by priority, and present
outstanding work at session start. Invoked automatically by the `joe-secrets` SessionStart hook.

## Active Repos to Scan

Scan for HANDOFF.yaml in:

```
~/dev/minibox
~/dev/maestro
~/dev/devloop
~/dev/doob
~/dev/devkit
~/dev/magi
~/dev/mcpipe
~/dev/braid
```

Also check the current working directory repo.

## Reading HANDOFF.yaml

For each repo with a HANDOFF.yaml:

```bash
for f in ~/dev/*/HANDOFF.yaml; do [ -f "$f" ] && echo "$f"; done
```

Read each file and extract: `in_progress`, `next_session`, `blockers`, `updated`.

## Triage and Presentation

Sort by:
1. `blockers` non-empty — surface first
2. `in_progress` items with `priority: high`
3. `next_session` items
4. `in_progress` items with other priorities

Present as a brief orientation table:

```
SESSION ORIENTATION — 2026-04-03

BLOCKERS
  minibox: SSH key rotation required before VPS integration test

HIGH PRIORITY
  minibox [feat/gc-images]: Integration test for GC under load
    Note: Needs VPS — blocked until SSH rotated

NEXT UP
  minibox: SSH key rotation → VPS test → open PR
  devloop: Review snapshot failures from yesterday's nextest run

LAST UPDATED
  minibox: 3 hours ago
  devloop: 1 day ago
```

## When No HANDOFF.yaml Exists

If no HANDOFF.yaml files are found:

> "No HANDOFF.yaml found in active repos. Starting fresh session.
> Run `handoff` at session end to capture state for next time."

## Automatic Invocation

This skill is invoked automatically by the `joe-secrets` SessionStart hook after op-resolver
completes. No manual trigger needed at session start — it fires on every new Claude session.
