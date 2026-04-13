---
name: handon
description:
  Use at the start of a session to triage and execute outstanding work in the current
  git repo. Reads the repo's HANDOFF.yaml, triages items by priority, and acts according
  to risk level without asking for approval on P1/P2 work. Single-repo only — use
  handup to survey nested or multi-project handoffs first.
---

# handon — Session-Start Handoff Reader

## Overview

Find the current repo's HANDOFF file, parse items by priority, and act:

| Priority | Action                                                                            |
| -------- | --------------------------------------------------------------------------------- |
| P0       | Validate current state immediately. Report to user. Ask before touching anything. |
| P1       | Execute autonomously. Stop only if scope expands or something unexpected happens. |
| P2       | Delegate to subagents. Cap at 5 concurrent.                                       |

## Steps

### 1. Find handoff file

```bash
handoff-detect          # returns path if exists, expected path + exit 2 if not
```

- Exit 0 → file exists, path printed — read it
- Exit 2 → file missing, expected path printed — offer to create via `/atelier:handoff`
- Exit 1 → not in a git repo — report and stop

If `handoff-detect` is not on PATH, fall back to globbing the repo root for `HANDOFF.*.yaml`.

If not inside a git repo (no `.git` found walking up from cwd), stop and report:
"Not in a git repo. Use `/atelier:handup` to survey nested projects from here."

If only a legacy `HANDOFF.md` exists at repo root, read it as freeform. Do not convert unless
asked.

### 2. Read .ctx/HANDOFF.state.yaml

After locating the HANDOFF file, read `.ctx/HANDOFF.state.yaml` from the same repo root if it
exists. Extract `branch`, `build`, `tests`, `notes`, `touched_files` and surface them in the
triage header:

```
## Handoff Triage — <path/to/repo>

Branch: <branch> | Build: <build> | Tests: <tests>
<notes if non-null>
Recently touched: <touched_files as comma-separated list, omit if absent>
```

If the file is absent, omit the state line rather than guessing.

### 3. Pull latest state from SQLite

Before parsing the local file, check the local SQLite database for status overrides written
outside this session (e.g. by another tool or a manual update):

```bash
SCRIPT=$(ls $HOME/.claude/plugins/cache/local/atelier/*/skills/handoff/scripts/sync-sqlite.sh \
  2>/dev/null | sort -V | tail -1)
bash "$SCRIPT" --project <project> --query 2>/dev/null
```

For each row returned, if the SQLite `status` differs from the YAML `status`, prefer SQLite and
update the in-memory copy before triaging. Do not write back to HANDOFF.yaml here — that happens
in step 9.

If the script is not found or `sqlite3` is not on PATH, skip and continue with the local file.

### 4. Review on wake

Before triaging by priority, scan all items for unreviewed `human-edit` entries — any `extra`
entry with `type: human-edit` and no `reviewed` field (or `reviewed` is absent).

Surface these first, regardless of item priority:

```
## Review on Wake

- [id] "[title]" — human edited `<field>` → `<value>` on <date>
  <note if present>
```

Do not act on these items automatically. Present to user and wait for acknowledgement before
proceeding to P0 triage. After the user acknowledges, note which items were reviewed —
`/atelier:handoff` will stamp `reviewed: <today>` on those entries at session end.

### 5. Parse items

From `HANDOFF.yaml`: read `items` list directly. Filter to `status: open` or `status: blocked`.
Apply any SQLite overrides from step 3 before triaging.

From `HANDOFF.md`: read the "Known Gaps", "Next Up", "Parked", or "Remaining Work" sections.
Infer priority:

- P0: "broken", "fails", "blocked", "urgent", "security"
- P1: specific file + known fix mentioned
- P2: everything else that's safe

### 6. Triage P0 items

For each P0:

1. Run relevant validation (`cargo check`, `git status`, test run)
2. Report finding to user with current state
3. Ask for go/no-go before acting

Do not proceed to P1/P2 until all P0s are acknowledged by user.

### 7. Execute P1 items

Work through each open P1 without asking. Stop and surface to user when:

- Scope expands beyond what the item described
- Tests fail unexpectedly (not the known failure)
- More than 3 files need changing beyond what was described
- Any destructive operation would be needed

### 8. Delegate P2 items

Dispatch one subagent per P2 item (cap 5 concurrent). Each subagent must:

- Receive explicit `--allowedTools` list
- Verify `git status` is clean before starting
- Commit its own changes
- Report back with result

### 9. Report and update

After all work:

```
## Handoff Triage — <path/to/repo>

P0:
  - [id] [name] "[title]" → [state found] → [action / question]

P1:
  - [id] [name] "[title]" → done | blocked: <reason>

P2:
  - [id] [name] "[title]" → delegated | skipped: <reason>
```

Then update `HANDOFF.yaml`:

- Mark done items `status: done`, add `completed: <today>`
- Add `log` entry for this session (one-liner, prepend to list)
- Upsert all items to SQLite via `sync-sqlite.sh` (see handoff skill step 6)
- Commit: `git add HANDOFF.yaml && git commit -m "docs: update handoff"`

## Edge Cases

**No handoff file found:** Report "No HANDOFF.yaml found in `<path>`." Offer to create one via
`/atelier:handoff`.

**HANDOFF.md only:** Read it, triage as normal, note at end: "Consider migrating to HANDOFF.yaml
for structured triage."

**All items done or parked:** Report clean state, no action needed.

**Blocked item:** Do not attempt. Report the blocker to user verbatim from the `description`
field.
