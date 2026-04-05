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
4. **Diagrams** — all Mermaid diagrams (see below)
5. **Log** — full history, oldest-first, as a compact dated list

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

Locate and run `generate-diagrams.py` by resolving the script path at runtime:

```bash
SCRIPT=$(ls $HOME/.claude/plugins/cache/local/atelier/*/skills/handover/scripts/generate-diagrams.py \
  2>/dev/null | sort -V | tail -1)
uv run "$SCRIPT" --handoff <path-to-HANDOFF.yaml>
```

This picks the highest installed version automatically. If no match is found, fall back to inline generation.

Embed the full stdout output verbatim into the Diagrams section of `.ctx/HANDOVER.md`.

If the script fails (non-zero exit or not found), fall back to generating diagrams inline
using the rules below. Record the fallback in a comment at the top of the Diagrams section:
`<!-- generate-diagrams.py unavailable — diagrams generated inline -->`.

The script emits up to five diagram types, each gated on having sufficient data:

| Name | Type | Gate |
|------|------|------|
| `dependency` | flowchart TD | items with inferred deps |
| `burn` | pie | ≥3 items |
| `velocity` | xychart-beta bar | ≥2 log entries, ≥1 completed item |
| `hotspots` | xychart-beta bar | ≥3 items with files, ≥3 distinct files |
| `blocked` | flowchart TD | blocked items exist |

Each is a fenced Mermaid block with a `### <Name>` header. Only non-empty diagrams are included.

### Fallback: Inline Diagram Rules

Use only if the script is unavailable or exits non-zero.

Apply these rules to **every node label**:

- 2–3 words maximum
- No newlines (`\n`) inside node labels
- No HTML tags
- No parentheses (use square brackets or quotes if needed)
- Abbreviate freely: `Auth Policy Gate` → `Auth Gate`

#### 1. Burn (pie) — gate: ≥3 items

```
pie title Work Distribution
  "done" : 7
  "open" : 3
  "blocked" : 1
```

Skip slices with count 0.

#### 2. Velocity (xychart-beta bar) — gate: ≥2 log entries, ≥1 completed item

x-axis = dates from log (sorted), y-axis = items completed per date.

```
xychart-beta
  title "Items Completed"
  x-axis ["2026-04-03", "2026-04-05"]
  y-axis "Items" 0 --> 3
  bar [0, 3]
```

#### 3. Hotspots (xychart-beta bar) — gate: ≥3 items with files, ≥3 distinct files

Top 8 files by item reference count. Use basename; disambiguate duplicates with parent dir.

```
xychart-beta
  title "File Hotspots"
  x-axis ["handler.rs", "ci.yml", "todos.rs"]
  y-axis "Items" 0 --> 5
  bar [5, 3, 2]
```

#### 4. Dependency (flowchart TD) — gate: items with inferred deps

Only emit items that have deps or are depended upon.

#### 5. Blocked chain (flowchart TD) — gate: blocked items exist

Show blocked items and their root blockers.

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
test content
