---
name: triage
description: This skill should be used when the user asks to "triage", "what needs fixing",
  "what's broken", "prioritize issues", "run triage", or wants a P0/P1/P2 issue breakdown
  across one or more repos.
---

# Triage Workflow

Scan HANDOFF files and GitHub issues, categorize by priority, and spawn parallel subagents
for fixes.

## Steps

### 1. Read current state

```bash
# Find HANDOFF files for the current repo
ls .ctx/HANDOFF*.yaml 2>/dev/null || ls HANDOFF*.yaml 2>/dev/null
```

Read each `HANDOFF.*.yaml` found. Focus on `items` with `status: open` or `status: blocked`.

### 2. Check GitHub issues

```bash
gh issue list --repo <repo> --state open --limit 50 --json number,title,labels,assignees
```

Use the repo dirname (not 'workspace') as `<repo>`. Do NOT use Linear — GitHub is the issue
tracker for this workspace.

### 3. Categorize P0/P1/P2

| Priority | Criteria |
|----------|----------|
| P0 | broken, fails, blocked, urgent, security, CI red |
| P1 | specific file + known fix, test failing with known cause |
| P2 | enhancements, cleanup, anything safe to defer |

Merge HANDOFF items and GitHub issues into a single prioritized list. Present summary:

```
## Triage — <repo>

P0 (act now):
  - [id] <title> — <why urgent>

P1 (autonomous fix):
  - [id] <title> — <file> → <known fix>

P2 (delegate / defer):
  - [id] <title>
```

### 4. On user selection, execute

- **P0**: Validate state, ask go/no-go before acting.
- **P1**: Fix autonomously. Stop if scope expands beyond the described fix or >3 files change.
- **P2**: Spawn one subagent per item (cap 5 concurrent). Each subagent must: receive explicit
  `--allowedTools`, verify clean `git status`, commit its own changes.

### 5. Validate with nextest

```bash
cargo nextest run          # filter tests
cargo nextest run <filter> # run specific tests
```

Use `cargo nextest`, not `cargo test`, for test filtering and parallel execution.

### 6. Commit with handoff updates

After fixes:

```bash
git add .ctx/HANDOFF.*.yaml
git commit -m "fix: <summary> — closes #<issue>"
```

Update HANDOFF items to `status: done` and prepend a `log` entry. Do not edit HANDOFF manually
for status if `doob` sync is active — use `handoff-db upsert` instead.
