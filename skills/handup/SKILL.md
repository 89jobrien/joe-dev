---
name: handup
description:
  Surveys the current working directory and all nested subdirectories for outstanding
  work — HANDOFF.yaml files, TODO/FIXME markers, and open items. Read-only orientation
  view across projects. Use before handon to decide where to focus.
---

# handup — Nested Handoff and TODO Survey

## Overview

`handup` is a read-only orientation tool. It sweeps cwd and all subdirectories for
signals of outstanding work, groups them by project, and renders a prioritized summary.
It does **not** execute, commit, or modify anything. The output tells you where to go
next; `handon` is how you get there.

## Steps

### 1. Resolve CWD

```bash
CWD=$(pwd)
```

Use `$CWD` as the absolute base for all paths in this skill. Never use relative paths.

### 2. Sweep for HANDOFF files

```bash
find "$CWD" -maxdepth 5 \( -path "*/.ctx/HANDOFF.*.yaml" -o -name "HANDOFF.md" \) 2>/dev/null \
  | grep -v -E "(target/|\.git/|node_modules/)" | sort
```

For each file found:
- Read `items` list (YAML) or relevant sections (MD)
- Filter to `status: open` or `status: blocked`
- Find repo root: `git -C "$(dirname <file>)" rev-parse --show-toplevel 2>/dev/null`
- Read `<repo-root>/.ctx/HANDOFF.state.yaml` if present — extract `branch`, `build`, `tests`

Skip files under `.git/`, `target/`, `node_modules/`.

### 3. Sweep for inline TODO/FIXME markers

```bash
grep -rn --include="*.rs" --include="*.sh" --include="*.py" --include="*.toml" \
  -E "(TODO|FIXME|HACK|XXX)(\(.*\))?:" "$CWD" 2>/dev/null | head -100
```

Group by absolute file path. Omit matches inside `target/`, `.git/`, generated files.

Only surface these if no HANDOFF.yaml exists for that subtree, or if the count is
notably high (>5 per project). They are supplementary context, not primary items.

### 4. Group by project

For each distinct repo root found (or subdirectory if no `.git`), build a project block:

```
### <project-name> — <absolute-path>
Branch: <branch> | Build: <build> | Tests: <tests>   (omit if .ctx absent)

  P0  [id] title                     (status: blocked or urgent keywords)
  P1  [id] title
  P2  [id] title
  ...
  TODO  /abs/path/to/src/foo.rs:42  TODO: fix borrow issue
```

Sort projects: those with P0 items first, then by P1 count descending.

### 5. Write .ctx/HANDUP.json

Write findings to `$CWD/.ctx/HANDUP.json`. Create `$CWD/.ctx/` if it does not exist.
This file is gitignored (covered by `.ctx/*`) — do not commit it.

Schema:

```json
{
  "generated": "<YYYY-MM-DD>",
  "cwd": "<absolute-path>",
  "projects": [
    {
      "name": "<project-name>",
      "path": "<absolute-path-to-project>",
      "repo_root": "<absolute-repo-root>",
      "handoff_path": "<absolute-path-to-HANDOFF.yaml>",
      "branch": "<branch or null>",
      "build": "<clean|failing|unknown|null>",
      "tests": "<summary or null>",
      "items": [
        { "id": "<id>", "priority": "<P0|P1|P2>", "status": "<status>", "title": "<title>" }
      ],
      "todos": ["<absolute-path>:<line>  <text>"]
    }
  ],
  "recommendation": { "project": "<name>", "reason": "<one-line rationale>" }
}
```

Overwrite any existing `HANDUP.json` from a prior run.

### 6. Render summary

Output the full survey, then a recommendation block:

```
## handup — <cwd> (<date>)

<project blocks>

---
## Where to next?

Highest urgency: <project> — <reason> (e.g. "1 P0 item: broken build")
Suggested: cd <absolute-path> && /atelier:handon

Findings written to: <cwd>/.ctx/HANDUP.json
```

If cwd is itself a git repo with a HANDOFF.yaml, include it first as "current project"
before sweeping subdirs.

If nothing is found anywhere: report "No open handoff items or TODO markers found under
`<cwd>`." and stop (still write an empty `HANDUP.json` with `"projects": []`).

## Edge Cases

**Only inline TODOs, no HANDOFF files:** Surface the TODO sweep grouped by file. Note
that no structured handoff exists; suggest `/atelier:handoff` to create one.

**Deeply nested monorepo:** Respect `maxdepth 4` to avoid thrashing. If the user wants
deeper, they can `cd` into a subdir and re-run.

**Single project at cwd:** Behaves like a read-only `handon` summary — shows items but
does not act on them.
