---
name: handoff
description: Use at end of a session to update HANDOFF.yaml with completed work, new gaps
  discovered, and current project state. Also use when asked to create a HANDOFF.yaml for
  a project that doesn't have one yet.
---

# handoff — Session-End Handoff Writer

## Overview

`HANDOFF.yaml` is the committed source of truth for task/workflow tracking. Item status is also
mirrored to a local SQLite database for cross-session queries without parsing YAML.
Project state (build, tests, branch) lives separately in `.ctx/HANDOFF.state.yaml` — generated,
never committed. A rendered reference doc is also written to `.ctx/HANDOFF.md`.

## File Layout

| File | Location | Committed | Purpose |
|---|---|---|---|
| `HANDOFF.<project>.<base>.yaml` | repo root | yes | Tasks, items, log — committed source of truth |
| `.ctx/HANDOFF.state.yaml` | `.ctx/` | no | Project snapshot — build/tests/branch/notes |
| `.ctx/HANDOFF.md` | `.ctx/` | no | Generated reference doc (rendered view of both) |

`.ctx/` must be in `.gitignore`. Never commit anything under it.

## File Discovery

Use `handoff-detect` to resolve the HANDOFF.yaml path if available:

```bash
handoff-detect          # returns path if exists, expected path + exit 2 if not
handoff-detect --name   # expected filename only (e.g. HANDOFF.devkit.devkit.yaml)
handoff-detect --root   # repo root
handoff-detect --project # project name
```

If `handoff-detect` is not on PATH, fall back to globbing the repo root for `HANDOFF.*.yaml`.

File naming convention: `HANDOFF.<project>.<cwd-basename>.yaml`
- `project` = name from Cargo.toml / go.mod / pyproject.toml, fallback to repo root dir name
- `cwd-basename` = `basename $(pwd)` at time of invocation

Legacy fallback (read-only): if no HANDOFF.yaml exists and a `HANDOFF.md` exists at repo root,
read it as freeform. Do not convert unless asked.

## HANDOFF.yaml Schema

Task/workflow tracking only. No build state — that goes in `.ctx/HANDOFF.state.yaml`.

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

### Item immutability rules

Only `status` and `extra` may change after creation. For materially changed scope, create a new
item and park the old one.

### human-edit entries

When a human directly edits a field in HANDOFF.yaml outside of a skill session, record it
explicitly:

```yaml
extra:
  - date: 2026-04-04
    type: human-edit
    field: status
    value: done
    note: "marked done manually — PR merged out of band"
```

Rules:
- **Unreviewed** = no `reviewed` field on the entry, or `reviewed` is absent.
- **Acknowledged** = `handon` has surfaced it and the user has seen it; `handoff` sets
  `reviewed: <today>` on the entry at session end and updates the SQLite record to match.
- Any field can be human-edited this way, but `status` is the most common case.

## .ctx/HANDOFF.state.yaml Schema

Fully overwritten each session. No append rules, no doob sync.

```yaml
updated: <YYYY-MM-DD>
branch: <git branch>
build: clean | failing | unknown
tests: "<N passing>" | "failing: N" | "unknown"
notes: <one-line or null>
```

Extend freely with project-specific facts (e.g. `rust_edition`, `open_prs`, `last_deploy`).

## Priority Guide

| Priority | Meaning |
|---|---|
| P0 | Broken, blocked, security, data loss — validate before acting |
| P1 | Known fix, clear scope, safe to execute |
| P2 | Safe to delegate, well-understood |

## Steps

### 1. Get current state
```bash
git branch --show-current
git log --oneline -5
cargo check 2>&1 | tail -3   # or language equivalent
cargo test 2>&1 | tail -5
```

### 2. Read existing HANDOFF.yaml and .ctx/HANDOFF.state.yaml (if present)

### 3. Update HANDOFF.yaml

**`items`** — apply immutability rules:
- New gap → append with new `id` (no `doob_uuid` yet)
- Completed → set `status: done`, add `completed: <today>`
- Blocked → set `status: blocked`, append `extra` entry with `type: blocker`
- Do NOT edit title, description, priority, or files on existing items
- Do NOT delete done items — prune only when list >15 and done items are >2 sessions old

**`human-edit` acknowledgement** — for any `extra` entry with `type: human-edit` and no
`reviewed` field that was surfaced by `handon` this session, add `reviewed: <today>` to that
entry. This signals to the next sync that doob should accept the human-set value as canonical.

**`log`** — prepend a new entry (newest first). One line, past tense. Include commit hashes.

**`updated`** — set to today.

### 4. Write HANDOFF.yaml

Emit clean YAML. No anchors, no aliases.

### 5. Write .ctx/HANDOFF.state.yaml

Create `.ctx/` if it does not exist. Overwrite completely with current state from step 1.

### 6. Sync to SQLite

Write item status to the local handoff database:

```bash
DB="$HOME/.local/share/atelier/handoff.db"
mkdir -p "$(dirname $DB)"
sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS items (
  project TEXT NOT NULL,
  id TEXT NOT NULL,
  name TEXT,
  priority TEXT,
  status TEXT,
  completed TEXT,
  updated TEXT,
  PRIMARY KEY (project, id)
);"
```

For each item in `items`, upsert:

```bash
sqlite3 "$DB" "INSERT INTO items (project, id, name, priority, status, completed, updated)
  VALUES ('<project>', '<id>', '<name>', '<priority>', '<status>', '<completed>', '<today>')
  ON CONFLICT(project, id) DO UPDATE SET
    status=excluded.status,
    completed=excluded.completed,
    updated=excluded.updated;"
```

Skip if `sqlite3` is not on PATH and note it in output.

### 7. Generate .ctx/HANDOFF.md

Render a combined reference doc from both files. Overwrite completely.

```markdown
# Handoff — <project> (<updated>)

**Branch:** <branch> | **Build:** <build> | **Tests:** <tests>
<notes if non-null>

## Items

| ID | P | Status | Title |
|---|---|---|---|
| <id> | <P> | <status> | <title> |

## Log

- <date>: <summary> [<commits>]
```

Rules:
- Items sorted P0 → P2, open before done/parked/blocked
- Log: last 5 entries only
- No diagrams — those are for `/atelier:handover`

### 8. Ensure .gitignore covers .ctx/

Add `.ctx/` to `.gitignore` if not present.

### 9. Commit
```bash
git add HANDOFF.yaml
git commit -m "docs: update handoff"
```

Stage only `HANDOFF.yaml`. Never stage anything under `.ctx/`.

## Creating from Scratch

Bootstrap from git context:

```bash
git log --oneline -10
git status
```

Populate `log` from recent commits. Leave `items` empty or with one P1 if there's an obvious next
step. Write `.ctx/HANDOFF.state.yaml` from actual build/test output.

## Legacy HANDOFF.md

If `HANDOFF.md` exists at repo root and `HANDOFF.yaml` does not: read it as freeform context, do
not auto-convert. Note that a `HANDOFF.yaml` could be created.
