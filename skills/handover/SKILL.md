---
name: handover
description: >
  This skill should be used when the user runs "/atelier:handover", asks to "visualize the handoff",
  "show handoff diagrams", "generate a handoff report", "explore the handoff", or provides
  a path to a HANDOFF file. Reads HANDOFF.*.{yaml,json,md} files and produces a prose
  summary plus Mermaid diagrams for project orientation.
version: 0.1.0
---

# handover — Handoff Visualizer

Generate a concise orientation report and Mermaid diagrams from a HANDOFF file.

## File Resolution

Resolve the target file in this order:

1. **Explicit path argument** — accept only if filename matches `HANDOFF.*.{yaml|json|md}` (case-insensitive).
   Reject any other filename with: `error: only HANDOFF.*.{yaml|json|md} files are accepted`.
2. **No argument** — use `handoff-detect` to find the file for the current directory:
   ```bash
   handoff-detect
   ```
   If `handoff-detect` is not on PATH, fall back to globbing the repo root for `HANDOFF.*.yaml`.
   If exit code 2 (no file exists), report: `no HANDOFF file found in this repo` and stop.

Never read arbitrary files. Never accept paths that don't match the naming pattern.

## Modes

Controlled by optional flags (default: all modes run):

| Flag | Output |
|---|---|
| *(none)* | Full report + all diagrams |
| `--report` | Prose summary only |
| `--diagrams` | All diagrams only |
| `--items` | Item table + status flowchart only |
| `--log` | Session log + sequence diagram only |

## Output File

Write all output to `.ctx/HANDOVER.md` at the repo root (same directory as the HANDOFF file's
repo). Create `.ctx/` if it does not exist.

```bash
mkdir -p <repo-root>/.ctx
# write to <repo-root>/.ctx/HANDOVER.md
```

After writing, print a single confirmation line to the user:
```
wrote .ctx/HANDOVER.md
```

The file is generated output — add `.ctx/HANDOVER.md` to `.gitignore` if not already present.

## Output Structure (default / full)

Emit sections in this order, omitting any section where data is absent:

1. **Review on Wake** — unreviewed human-edit entries (see below)
2. **State** — one-line build/test/notes summary
3. **Items table** — markdown table: ID | Priority | Status | Title
4. **Log** — last 5 log entries as a compact list
5. **Diagrams** — all Mermaid diagrams (see below)

### Review on Wake

Scan all items for `extra` entries with `type: human-edit` and no `reviewed` field. If any exist,
emit this section before everything else:

```
## Review on Wake

- minibox-4 "Handler Coverage" — human edited `status` → `done` on 2026-04-03
  marked done manually — PR merged out of band
```

Mark these rows in the items table with a `*` suffix on the status field (e.g. `done*`).
Omit this section entirely if no unreviewed human-edits exist.

Keep prose minimal. No headers longer than 3 words. No HTML. No emoji.

## Mermaid Diagrams

Run `skills/handover/scripts/generate-diagrams.py` from the repo root to produce all diagrams:

```bash
uv run skills/handover/scripts/generate-diagrams.py --handoff <path-to-HANDOFF.yaml>
```

Embed the full stdout output verbatim into the Diagrams section of `.ctx/HANDOVER.md`.

If the script fails (non-zero exit or not found), fall back to generating diagrams inline
using the rules below. Record the fallback in a comment at the top of the Diagrams section:
`<!-- generate-diagrams.py unavailable — diagrams generated inline -->`.

The script emits four diagram types (dependency, sprint, coverage, blocked). Each is a fenced
Mermaid block with a `### <Name>` header. Only non-empty diagrams are included in the output.

### Fallback: Inline Diagram Rules

Use only if the script is unavailable or exits non-zero.

Apply these rules to **every node label**:

- 2–3 words maximum
- No newlines (`\n`) inside node labels
- No HTML tags
- No parentheses (use square brackets or quotes if needed)
- Abbreviate freely: `Auth Policy Gate` → `Auth Gate`

#### 1. Item Flow (flowchart LR)

Show items grouped by priority flowing into status buckets.

```
flowchart LR
  P0 --> open1[Auth Gate]
  P1 --> open2[CI Enforce]
  P1 --> open3[Bench Toggles]
  open1 --> S_open[Open]
  open2 --> S_open
  open3 --> S_open
  vz[VZ Bug] --> S_blocked[Blocked]
```

#### 2. Item Status (stateDiagram-v2)

Show the status state machine with item counts in each state.

```
stateDiagram-v2
  [*] --> Open
  Open --> Done
  Open --> Blocked
  Open --> Parked
  Done --> [*]
  Blocked --> Open
  Parked --> Open
```

Annotate transitions with counts if >1 item. Example: `Open --> Done : 3 items`.

#### 3. Session Timeline (sequenceDiagram)

Map log entries as a timeline. Use date as the actor label on the left, one `Note over` per
entry.

```
sequenceDiagram
  participant Apr03 as 2026-04-03
  participant Apr02 as 2026-04-02
  Note over Apr03: Bench timeout fix
  Note over Apr02: Tier 1 wins
```

Only emit this diagram when `log` has ≥2 entries.

#### 4. Item-File ER (erDiagram)

Show which items reference which files. Only emit when items have non-empty `files` arrays.

```
erDiagram
  ITEM ||--o{ FILE : references
  ITEM {
    string id
    string priority
    string status
  }
  FILE {
    string path
  }
```

Follow with a compact table of item→file mappings (max 10 rows; truncate with `... N more`).

#### 5. Priority/Status Matrix (quadrantChart) — optional

Emit only when there are ≥6 items. Map priority (P0=high, P2=low) vs status
(open/blocked=active, done/parked=inactive).

```
quadrantChart
  title Items by Priority and Status
  x-axis Low Priority --> High Priority
  y-axis Inactive --> Active
```

## Reading State

After resolving the HANDOFF file, also read `.ctx/HANDOFF.state.yaml` from the same repo root if
it exists. This file holds build/tests/branch/notes — it is not in HANDOFF.yaml itself.

```
<repo-root>/.ctx/HANDOFF.state.yaml   # project snapshot — may not exist
<repo-root>/HANDOFF.*.yaml            # tasks/items/log
```

If `.ctx/HANDOFF.state.yaml` is absent, omit the State section from output rather than guessing.

## YAML Parsing

Read with the Read tool and extract fields manually — do not shell out to a YAML parser.

From `HANDOFF.yaml`:
- `items[*].{id, priority, status, title, files, extra}`
- `log[*].{date, summary, commits}`
- `updated`

From `.ctx/HANDOFF.state.yaml`:
- `build`, `tests`, `branch`, `notes`

For `.json`, same approach via Read tool.

For `.md` (legacy HANDOFF.md), read as freeform text and infer structure from markdown headers
and tables. No `.ctx/HANDOFF.state.yaml` will exist for legacy files.

## Tone and Formatting

- Section headers: `##` max, 1–3 words
- No filler text ("Here is your report…")
- Lead with the state line, then items, then diagrams
- Mermaid blocks: fenced with ` ```mermaid `

## Additional Resources

- **`references/diagram-patterns.md`** — abbreviation guide, subgraph patterns for ≥3 items per
  priority, complex multi-item examples, and the full common-mistakes reference with before/after
  fixes for all four Mermaid pitfalls (long labels, newlines, colon IDs, parentheses)
