---
name: handdown
description:
  Write cross-project analysis context back into nested HANDOFF docs after a handup survey
  or any multi-project analysis session. Appends extra entries (discovery/escalation/note)
  and a log entry to each touched HANDOFF.yaml, syncs to SQLite, and commits. The write-back
  counterpart to handup.
---

# handdown — Analysis Write-Back

## Overview

`handdown` is the write-back counterpart to `handup`. After a cross-project survey surfaces
open items, blockers, and inter-project relationships, those insights exist only in the
conversation — the next session starts cold. `handdown` persists the analysis by appending
`extra` entries and a `log` entry to each affected HANDOFF.yaml, so future sessions start
with the context already baked in.

Typical insights worth persisting:

- "Identified as highest-urgency in cross-project survey — blocks Maestro CI"
- "Cross-project dependency discovered: rascal-1 unblocks fmtx-2 and rascal-4"
- "Recommended next focus from handup — natural follow-on to minibox-28 completion"
- "Blocked by Apple VZ bug — confirm still blocked before acting"

`handdown` never creates items, never changes `status`, and never modifies immutable fields.
It only appends `extra` entries and `log` entries.

## Scope

- **No args** — use findings from `$CWD/.ctx/HANDUP.json` (written by `handup`)
- **Named projects** — `handdown minibox rascal` restricts write-back to those project names only

## Steps

### 1. Resolve CWD and load HANDUP.json

```bash
CWD=$(pwd)
BASENAME=$(basename "$CWD")
HANDUP="$HOME/.ctx/handoffs/$BASENAME/HANDUP.json"
```

Use `$CWD` as the absolute base for all paths. Never use relative paths.

**If `$HANDUP` exists and `generated` matches today's date:** read it directly. Extract the
`projects` array — each entry has `name`, `handoff_path` (absolute), `repo_root` (absolute),
`branch`, `build`, `items`, and `todos`. Use this as the project list for all subsequent steps.

**If `$HANDUP` is absent or stale (generated on a prior date):** fall back to sweeping:

```bash
fd -t f -d 5 'HANDOFF\..*\.yaml' "$CWD" --full-path 2>/dev/null \
  | grep -v -E "(target/|\.git/|node_modules/)" | sort
```

For each file found, read `items`, `log`, and `project:` field; find repo root via
`git -C "$(dirname <file>)" rev-parse --show-toplevel`; read
the matching state file (same `<name>.<base>` as the HANDOFF file + `.state.yaml`) if present.

If named-project scope was given, discard projects whose `name` field does not match.

### 2. Build cross-project picture

With all HANDOFF files loaded, synthesize the following signals. Record each finding as a
(project, item-id, entry-type, note) tuple for step 3.

**Unblocking relationships**: If project A has an item that just moved to `status: done` and
project B has an open item whose `description` or `extra[].note` references A's item ID or
title (e.g. "Depends on rascal-1"), mark B's item with a `discovery` entry:
"rascal-1 is now done — this item's blocker has been resolved."

**Cross-project dependencies not yet noted**: Scan all open items' `description` and
`extra[].note` for references to other projects' item IDs. If a dependency exists but no
`extra` entry of type `discovery` mentions it yet, create one on both sides:
- The dependent item: "Depends on <other-id> — <short title of that item>"
- The dependency item: "Unblocks <dependent-id> in <project>"

**Escalations from this session**: If the current conversation's handup analysis named an
item as highest urgency or recommended next, append an `escalation` entry on that item:
"Surfaced as highest urgency in cross-project handup survey (<date>). <one-sentence rationale>."

**State-file notes not yet in extra**: If the matching `.state.yaml` has a `notes` field with
content that describes a constraint or caveat not captured in any item's `extra`, append a
`note` entry to the most relevant open item.

**Confirmed blockers**: If a `blocked` item's `extra` list has no recent (within 14 days)
entry confirming the blocker is still active, append a `note`:
"Blocker confirmed still active as of <date>. <source or observation>."

### 3. Filter duplicates

Before writing anything, check existing `extra` entries on each target item:

- Skip if any `extra` entry dated today has the same `type` and substantially the same
  content (same item IDs referenced, same key phrase).
- Skip if the proposed note is purely redundant with the item's `description` itself.

A conservative write is better than a noisy one. When uncertain, skip.

### 4. Write extra entries

For each (project, item-id, entry-type, note) tuple that survived step 3, append to the
item's `extra` list in the HANDOFF.yaml (append-only — never edit existing entries):

```yaml
extra:
  - date: <YYYY-MM-DD>
    type: discovery | escalation | note
    note: >
      <One or two sentences. Concrete and actionable. No vague prose.>
```

Entry type guide:

| Type        | When to use                                                              |
| ----------- | ------------------------------------------------------------------------ |
| `discovery` | Cross-project dependency or unblocking relationship newly identified     |
| `escalation`| Item identified as highest-priority in cross-project analysis            |
| `note`      | General analysis context — confirmed blocker, recommended next, caveat   |

### 5. Write log entry

For each HANDOFF.yaml that received at least one new `extra` entry, prepend a log entry:

```yaml
log:
  - date: <YYYY-MM-DD>
    summary: >
      handdown analysis pass — <N> item(s) annotated.
      <One-liner on the most significant insight from this pass.>
```

Do not add a log entry to files where nothing was written.

### 6. Update .ctx/HANDOFF.<name>.<base>.state.yaml notes (conditional)

If the analysis surfaced a new recommended focus or a newly resolved blocker that materially
changes the project's next action, update the `notes` field in the matching `.state.yaml`.

Only update if the change is substantial. Leave the file untouched otherwise — state files
are not committed and will be regenerated by the next `handoff` session.

### 7. Sync to SQLite

After writing each HANDOFF.yaml, sync the project to the local SQLite database:

```bash
handoff-db upsert --project <project-name> --handoff "<absolute-handoff-path>" 2>/dev/null
```

If the script is not found or `sqlite3` is not on PATH, skip silently and note it in the
output.

### 8. Commit

For each repo root that had at least one HANDOFF.yaml modified, stage and commit only that
HANDOFF file. Use the absolute `repo_root` from the project record:

```bash
git -C "<absolute-repo-root>" add "<absolute-handoff-path>"
git -C "<absolute-repo-root>" commit -m "chore(handoff): handdown analysis pass $(date +%Y-%m-%d)"
```

If the working tree is dirty beyond the HANDOFF file, stage only the HANDOFF file explicitly.
If git exits non-zero (detached HEAD, merge conflict, etc.), report the error and skip that
repo's commit — do not block the others.

### 9. Render summary

After all writes and commits, output a structured report following the format in
`references/HANDDOWN.template.json`. The rendered form is:

```
## handdown — <cwd> (<date>)

### <project-name>
- [<item-id>] <type>: <one-line note>
- [<item-id>] <type>: <one-line note>
  Committed: <short-hash>

### <project-name>
  (no new context — skipped)

---
<N> project(s) updated, <M> item(s) annotated.
```

**Field rules:**

- **project-name**: the `project:` field from the HANDOFF.yaml
- **item-id**: the item's `id` field, e.g. `rascal-2`
- **type**: one of `discovery`, `escalation`, or `note` — matches the `type` written to `extra`
- **one-line note**: first sentence of the `note` field (truncate at 100 chars if needed)
- **Committed**: short git hash from the commit made in step 8; omit the line if commit was skipped
- **skipped projects**: list every project that was inspected but received no new annotations —
  do not silently omit them, as "skipped" is useful signal that the context is already current
- **footer**: always include `<N> project(s) updated, <M> item(s) annotated` where N counts
  repos with at least one write and M counts the total number of new `extra` entries written

## Immutability Rules

`handdown` must never:

- Create new items (only `handoff` creates items)
- Change `status` or `completed` (only `handon` and `handoff` do this)
- Modify `id`, `name`, `priority`, `title`, `description`, or `files`
- Edit existing `extra` entries — only append new ones
- Commit `.ctx/` files

## Edge Cases

**No HANDOFF files found:** Report "No HANDOFF.yaml files found under `<cwd>`." and stop.

**No new context to write:** Report "Nothing new to annotate — all cross-project context
already captured." Do not create empty log entries.

**Dirty working tree in target repo:** Stage only the HANDOFF.yaml file. If git refuses
(merge conflict, detached HEAD), report the error and skip that repo's commit without
failing the others.

**SQLite not available:** Skip sync step, note in output, continue. YAML is the source of truth.
