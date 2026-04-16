---
name: handoff
description: Use at end of a session to update HANDOFF.yaml with completed work, new gaps
  discovered, and current project state. Also use when asked to create a HANDOFF.yaml for
  a project that doesn't have one yet.
model: sonnet
effort: medium
argument-hint: "[project]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
---

# handoff — Session-End Handoff Writer

## Overview

`HANDOFF.yaml` is split in two: `items` are the committed short-lived context layer for
still-open work, while `log` is the durable one-line history of finished work. GitHub issues,
reconciled through `valerie` and `doob`, are the active-work source of truth. Non-Valerie
skills should use the local SQLite database via `handoff-db` plus HANDOFF YAML, never `doob`
directly. The scripted bridge from HANDOFF into the backlog is `handoff-reconcile`; use that
instead of reconstructing `doob` commands by hand. Project state (build, tests, branch) lives separately in
`.ctx/HANDOFF.<name>.<base>.state.yaml` — generated, never committed. A rendered reference doc
is also written to `.ctx/HANDOFF.md`.

See `references/schema.md` for the full YAML schema, immutability rules, priority guide,
and file layout.

## File Discovery

Use `handoff-detect` to resolve the HANDOFF.yaml path if available:

```bash
handoff-detect          # returns path if exists, expected path + exit 2 if not
handoff-detect --name   # expected filename only (e.g. HANDOFF.devkit.devkit.yaml)
handoff-detect --root   # repo root
handoff-detect --project # project name
```

If `handoff-detect` is not on PATH, fall back to globbing the repo root for `HANDOFF.*.yaml`.

Legacy fallback (read-only): if no HANDOFF.yaml exists and a `HANDOFF.md` exists at repo root,
read it as freeform. Do not convert unless asked.

## Steps

### 1. Get current state
```bash
git branch --show-current
git log --oneline -5
cargo check 2>&1 | tail -3   # or language equivalent
cargo test 2>&1 | tail -5
```

### 2. Read existing HANDOFF.yaml and .ctx/HANDOFF.<name>.<base>.state.yaml (if present)

### 3. Update HANDOFF.yaml

**`items`** — apply immutability rules (see `references/schema.md`):
- New gap → append with new `id`
- Completed or closed upstream → remove the item from `items` after recording the outcome in
  `log`
- Blocked → set `status: blocked`, append `extra` entry with `type: blocker`
- Do NOT edit title, description, priority, or files on existing items
- Do NOT retain done or parked items in committed `items`

**`human-edit` acknowledgement** — for any `extra` entry with `type: human-edit` and no
`reviewed` field that was surfaced by `handon` this session, add `reviewed: <today>` to that
entry.

**`log`** — prepend a new entry (newest first). This section is durable, not transient. Use one
line, past tense, and include commit hashes for finished work when known.

**`updated`** — set to today.

### 4. Write HANDOFF.yaml

Emit clean YAML. No anchors, no aliases.

### 5. Write .ctx/HANDOFF.<name>.<base>.state.yaml

Create `.ctx/` if it does not exist. Overwrite completely with current state from step 1.

Populate `touched_files` from files changed in commits since the session started. If session
boundary is unclear, use files changed since the last log entry date in HANDOFF.yaml:

```bash
git diff --name-only $(git log --format="%H" --since="<last-log-date>" | tail -1)..HEAD
```

Omit the field if empty.

### 6. Sync to SQLite

Run `handoff-db` (available on PATH via the plugin's `bin/`):

```bash
handoff-db upsert --project <project> --handoff <path-to-HANDOFF.yaml>
```

If the script is not found or exits non-zero, skip and note it in output.

Do not call `doob` from this skill. `valerie` owns `doob` and GitHub issue sync.

### 6b. Reconcile open HANDOFF items into the backlog

Run the scripted Valerie bridge:

```bash
handoff-reconcile sync --project <project> --handoff <path-to-HANDOFF.yaml>
```

This is required. A handoff update is not complete until every open or blocked HANDOFF item has
been reconciled into the configured `doob` backend through this command. Do not recreate this
flow with ad hoc `doob todo add` / `doob todo list` commands unless you are debugging the
reconciler itself.

If the script is not found or exits non-zero, stop and report the failure instead of silently
continuing.

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
- Items sorted P0 → P2, open before blocked
- Log: last 5 entries only
- No diagrams — those are for `/atelier:handover`

### 8. Ensure .gitignore covers .ctx/

Verify `.gitignore` has:
```
.ctx/*
!.ctx/HANDOFF.*.yaml
.ctx/HANDOFF.*.state.yaml
```

Add or update if not present. This pattern ignores all `.ctx/` contents except HANDOFF files.

### 9. Migration preflight

Before writing, check if the HANDOFF file is still at the repo root. If so, migrate it first:

```bash
migrate-handoff <repo-root> <old-root-path>
```

Then stage the rename and continue with the new `.ctx/` path.

### 10. Commit

```bash
git add <path-to-HANDOFF.yaml> .gitignore
git commit -m "docs: update handoff"
```

Stage only the durable HANDOFF file under `.ctx/` plus any `.gitignore` update required for the
managed block. Never stage `.ctx/HANDOFF.*.state.yaml` or `.ctx/HANDOFF.md`.

## Creating from Scratch

Bootstrap from git context:

```bash
git log --oneline -10
git status
```

Populate `log` from recent commits. Leave `items` empty or with one P1 if there's an obvious
open next step. Do not backfill closed work into `items`, but do preserve durable `log`
history. Write `.ctx/HANDOFF.<name>.<base>.state.yaml` from actual build/test output.

Place the new HANDOFF file at `.ctx/HANDOFF.<name>.<base>.yaml` where `<name>` is the
package/crate name from the nearest manifest and `<base>` is the repo root dir name.
Use `handoff-detect --name` to get the correct filename.

## Legacy HANDOFF.md

If `HANDOFF.md` exists at repo root and `HANDOFF.yaml` does not: read it as freeform context,
do not auto-convert. Note that a `HANDOFF.yaml` could be created.
