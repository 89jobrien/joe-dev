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

### 2. Read existing HANDOFF.yaml and .ctx/HANDOFF.state.yaml (if present)

### 3. Update HANDOFF.yaml

**`items`** — apply immutability rules (see `references/schema.md`):
- New gap → append with new `id`
- Completed → set `status: done`, add `completed: <today>`
- Blocked → set `status: blocked`, append `extra` entry with `type: blocker`
- Do NOT edit title, description, priority, or files on existing items
- Do NOT delete done items — prune only when list >15 and done items are >2 sessions old

**`human-edit` acknowledgement** — for any `extra` entry with `type: human-edit` and no
`reviewed` field that was surfaced by `handon` this session, add `reviewed: <today>` to that
entry.

**`log`** — prepend a new entry (newest first). One line, past tense. Include commit hashes.

**`updated`** — set to today.

### 4. Write HANDOFF.yaml

Emit clean YAML. No anchors, no aliases.

### 5. Write .ctx/HANDOFF.state.yaml

Create `.ctx/` if it does not exist. Overwrite completely with current state from step 1.

### 6. Sync to SQLite

Resolve and run `sync-sqlite.sh` from the plugin cache:

```bash
SCRIPT=$(ls $HOME/.claude/plugins/cache/local/atelier/*/skills/handoff/scripts/sync-sqlite.sh \
  2>/dev/null | sort -V | tail -1)
bash "$SCRIPT" --project <project> --handoff <path-to-HANDOFF.yaml>
```

If the script is not found or exits non-zero, skip and note it in output.

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

Populate `log` from recent commits. Leave `items` empty or with one P1 if there's an obvious
next step. Write `.ctx/HANDOFF.state.yaml` from actual build/test output.

## Legacy HANDOFF.md

If `HANDOFF.md` exists at repo root and `HANDOFF.yaml` does not: read it as freeform context,
do not auto-convert. Note that a `HANDOFF.yaml` could be created.
