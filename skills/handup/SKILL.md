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

### 1. Sweep for HANDOFF files

Glob from cwd downward for `HANDOFF.*.yaml` and `HANDOFF.md`:

```bash
find . -maxdepth 5 \( -path "*/.ctx/HANDOFF.*.yaml" -o -name "HANDOFF.md" \) 2>/dev/null \
  | grep -v -E "(target/|\.git/|node_modules/)" | sort
```

For each file found:
- Read `items` list (YAML) or relevant sections (MD)
- Filter to `status: open` or `status: blocked`
- Note the repo root (nearest ancestor containing `.git`)
- Read `.ctx/HANDOFF.state.yaml` alongside if present — extract `branch`, `build`, `tests`

Skip files under `.git/`, `target/`, `node_modules/`.

### 2. Sweep for inline TODO/FIXME markers

Search source files from cwd downward for `TODO`, `FIXME`, `HACK`, `XXX` comments:

```bash
grep -rn --include="*.rs" --include="*.sh" --include="*.py" --include="*.toml" \
  -E "(TODO|FIXME|HACK|XXX)(\(.*\))?:" . 2>/dev/null | head -100
```

Group by file. Omit matches inside `target/`, `.git/`, generated files.

Only surface these if no HANDOFF.yaml exists for that subtree, or if the count is
notably high (>5 per project). They are supplementary context, not primary items.

### 3. Group by project

For each distinct repo root found (or subdirectory if no `.git`), build a project block:

```
### <project-name> — <relative path>
Branch: <branch> | Build: <build> | Tests: <tests>   (omit if .ctx absent)

  P0  [id] title                     (status: blocked or urgent keywords)
  P1  [id] title
  P2  [id] title
  ...
  TODO  src/foo.rs:42  TODO: fix borrow issue
```

Sort projects: those with P0 items first, then by P1 count descending.

### 4. Render summary

Output the full survey, then a recommendation block:

```
## handup — <cwd> (<date>)

<project blocks>

---
## Where to next?

Highest urgency: <project> — <reason> (e.g. "1 P0 item: broken build")
Suggested: cd <path> && /atelier:handon
```

If cwd is itself a git repo with a HANDOFF.yaml, include it first as "current project"
before sweeping subdirs.

If nothing is found anywhere: report "No open handoff items or TODO markers found under
`<cwd>`." and stop.

### 5. No writes

Do not modify any file. Do not commit. Do not update SQLite. Do not run builds or tests.
State data (branch, build, tests) comes only from `.ctx/HANDOFF.state.yaml` written by
a prior `handoff` session — never from live shell commands.

## Edge Cases

**Only inline TODOs, no HANDOFF files:** Surface the TODO sweep grouped by file. Note
that no structured handoff exists; suggest `/atelier:handoff` to create one.

**Deeply nested monorepo:** Respect `maxdepth 4` to avoid thrashing. If the user wants
deeper, they can `cd` into a subdir and re-run.

**Single project at cwd:** Behaves like a read-only `handon` summary — shows items but
does not act on them.
