# HANDOFF Schema Reference

## HANDOFF.yaml

```yaml
project: <name>
id: <prefix>       # first 7 chars of project name, used for item IDs
updated: <YYYY-MM-DD>

items:
  - id: <prefix>-<n>          # sequential integer from 1, no leading zeros, never reuse
    name: <kebab-slug>        # immutable after creation
    priority: P0 | P1 | P2   # immutable after creation
    status: open | done | parked | blocked  # mutable
    title: <one-line>         # immutable after creation
    description: <detail>     # immutable after creation, null ok
    files: [<path>]           # immutable after creation, omit if empty
    completed: <YYYY-MM-DD>   # only when status: done
    extra:                    # append-only; never edit existing entries
      - date: <YYYY-MM-DD>
        type: note | blocker | decision | discovery | escalation | human-edit
        field: <field-name>   # human-edit only: which field was changed
        value: <new-value>    # human-edit only: the value set
        reviewed: <YYYY-MM-DD> # set by handoff skill after handon acknowledges it
        note: <text>

log:
  - date: <YYYY-MM-DD>
    summary: <one-liner of what happened>
    commits: [<short-hash>]   # optional
```

## Immutability Rules

Only `status` and `extra` may change after creation. For materially changed scope, create a
new item and park the old one.

| Field | Immutable? |
|---|---|
| `id` | yes |
| `name` | yes |
| `priority` | yes |
| `title` | yes |
| `description` | yes |
| `files` | yes |
| `status` | no — only mutable field |
| `extra` | append-only |
| `completed` | set once when status → done |

## Priority Guide

| Priority | Meaning |
|---|---|
| P0 | Broken, blocked, security, data loss — validate before acting |
| P1 | Known fix, clear scope, safe to execute |
| P2 | Safe to delegate, well-understood |

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
```

Extend freely with project-specific facts (e.g. `rust_edition`, `open_prs`, `last_deploy`).

## File Layout

| File | Location | Committed | Purpose |
|---|---|---|---|
| `HANDOFF.<project>.<base>.yaml` | repo root | yes | Tasks, items, log |
| `.ctx/HANDOFF.state.yaml` | `.ctx/` | no | Project snapshot |
| `.ctx/HANDOFF.md` | `.ctx/` | no | Generated reference doc |

`.ctx/` must be in `.gitignore`. Never commit anything under it.

## Naming Convention

`HANDOFF.<project>.<cwd-basename>.yaml`

- `project` = name from Cargo.toml / go.mod / pyproject.toml, fallback to repo root dir name
- `cwd-basename` = `basename $(pwd)` at time of invocation
