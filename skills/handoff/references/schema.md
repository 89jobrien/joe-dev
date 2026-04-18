# HANDOFF Schema Reference

## HANDOFF.yaml

HANDOFF splits active context from history. `items` are transient context for open work, while
`log` is durable completed-work history. GitHub issues, reconciled through `valerie` and
`doob`, are the authoritative backlog. SQLite via `handoff-db` is the local query/store used
by non-Valerie skills. `handoff-reconcile` is the scripted bridge that captures open HANDOFF
items into the authoritative backlog.

```yaml
project: <name>
id: <prefix> # first 7 chars of project name, used for item IDs
updated: <YYYYMMDD:HHMMSS> # ISO 8601 datetime, always with time and Z suffix

items:
  - id: <prefix>-<n> # sequential integer from 1, no leading zeros, never reuse
    name: <kebab-slug> # immutable after creation
    priority: P0 | P1 | P2 # immutable after creation
    status: open | done | parked | blocked | pending-validation
    # mutable; prune done/parked before commit
    # pending-validation: item is unblocked but depends on external validation before action
    title: <one-line> # immutable after creation
    description: <detail> # immutable after creation, null ok
    files: [<path>] # immutable after creation, omit if empty
    completed: <YYYYMMDD:HHMMSS> # only when status: done
    extra: # append-only; never edit existing entries
      - date: <YYYYMMDD:HHMMSS>
        type: note | blocker | decision | discovery | escalation | human-edit
        field: <field-name> # human-edit only: which field was changed
        value: <new-value> # human-edit only: the value set
        reviewed: <YYYYMMDD:HHMMSS> # set by handoff skill after handon acknowledges it
        note: <text>

log:
  - date: <YYYYMMDD:HHMMSS> # ISO 8601 datetime; use current time at session end
    session: <n> # monotonically increasing integer; increment from last log entry
    claude_session_id: <id> # optional; $CLAUDE_SESSION_ID env var if set
    summary: <one-liner of what finished or changed>
    commits: # optional, recommended for finished work
      - sha: <short-hash>
        branch: <branch-name> # branch the commit landed on (usually "main")
```

## Immutability Rules

Only `status` and `extra` may change after creation. For materially changed scope, create a
new item and park the old one.

Committed HANDOFF files should normally contain only `open` and `blocked` items. `done` and
`parked` are transitional states during reconciliation and should be pruned from `items`
after sync. Preserve `log` history.

| Field         | Immutable?                  |
| ------------- | --------------------------- |
| `id`          | yes                         |
| `name`        | yes                         |
| `priority`    | yes                         |
| `title`       | yes                         |
| `description` | yes                         |
| `files`       | yes                         |
| `status`      | no — only mutable field     |
| `extra`       | append-only                 |
| `completed`   | set once when status → done |

## Log Semantics

- `log` is durable and should remain in committed HANDOFF files
- Use one line per finished work item or meaningful session outcome
- `date` must be ISO 8601 with time (`YYYYMMDD:HHMMSS`) — bare dates are invalid
- `session` is required — increment from the previous log entry's session number
- Commits must use `{sha, branch}` object form — bare hash strings are invalid
- Do not treat `log` as transient state

## Priority Guide

| Priority | Meaning                                                       |
| -------- | ------------------------------------------------------------- |
| P0       | Broken, blocked, security, data loss — validate before acting |
| P1       | Known fix, clear scope, safe to execute                       |
| P2       | Safe to delegate, well-understood                             |

## human-edit Entries

When a human directly edits a field in HANDOFF.yaml outside a skill session:

```yaml
extra:
  - date: 2026-04-04
    type: human-edit
    field: status
    value: done
    note: "marked done manually — PR merged out of band"
```

- **Unreviewed** = no `reviewed` field on the entry
- **Acknowledged** = `handon` surfaced it, user confirmed; `handoff` stamps `reviewed: <today>`

## .ctx/HANDOFF.state.yaml

Fully overwritten each session. Never committed.

```yaml
updated: <YYYY-MM-DD>
branch: <git branch>
build: clean | failing | unknown
tests: "<N passing>" | "failing: N" | "unknown"
notes: <one-line or null>
touched_files: [<path>] # files modified this session; omit if empty
```

Extend freely with project-specific facts (e.g. `rust_edition`, `open_prs`, `last_deploy`).

## File Layout

| File                                          | Location | Committed | Purpose                        |
| --------------------------------------------- | -------- | --------- | ------------------------------ |
| `.ctx/HANDOFF.<name>.<base>.yaml`             | `.ctx/`  | yes       | Open-work context, items, log  |
| `.ctx/HANDOFF.<name>.<base>.state.yaml`       | `.ctx/`  | no        | Project/package snapshot       |
| `.ctx/HANDOFF.md`                             | `.ctx/`  | no        | Generated current-context doc  |
| `.ctx/.initialized`                           | `.ctx/`  | no        | Init token (date of last init) |
| `.ctx/handoff.<project>.config.toml`          | `.ctx/`  | no        | Local runtime vars (user-owned)|
| `.ctx/handoff.<project>.config.toml.example`  | `.ctx/`  | yes       | Committed template for config  |

`.gitignore` is managed by `handoff-init` between `# handoff-begin` / `# handoff-end` markers:

```
# handoff-begin
.ctx/*
!.ctx/HANDOFF.*.yaml
.ctx/HANDOFF.*.state.yaml
!.ctx/handoff.*.config.toml.example
.ctx/.initialized
# handoff-end
```

Do not edit this block manually — run `handoff-init --force` to regenerate it.

## Naming Convention

`HANDOFF.<name>.<base>.yaml` where:
- `<name>` = package/crate name from manifest (`Cargo.toml`, `pyproject.toml`, `go.mod`),
  fallback to dir basename
- `<base>` = repo root dir name (e.g. `atelier`, `doob`, `crux`) — constant for all files
  in a repo

Examples:
- Root of repo `atelier` with package `atelier`: `.ctx/HANDOFF.atelier.atelier.yaml`
- Crate `cruxai` in repo `crux`: `.ctx/HANDOFF.cruxai.crux.yaml`
- Nested crate `handoff` in repo `atelier`: `.ctx/HANDOFF.handoff.atelier.yaml`

State files follow the same `<name>.<base>` pattern with `.state.yaml` suffix.
