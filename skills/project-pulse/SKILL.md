---
name: project-pulse
description: This skill should be used when the user asks to "end session", "capture state",
  "session summary", "what changed this session", "summarize repos", "write session notes",
  or wants to capture multi-repo state at the end of a work session.
---

# project-pulse

Capture branch/commit/PR state across all active repos at session end. Write to both
memory files and the Obsidian daily note.

## Active Repos

Default active repos to check:

```
~/dev/minibox
~/dev/maestro
~/dev/devloop
~/dev/doob
~/dev/devkit
~/dev/magi
~/dev/mcpipe
~/dev/braid
```

Add or remove repos based on what was active in the current session.

## State Capture Per Repo

For each repo, capture:

```bash
cd <repo>
git branch --show-current          # current branch
git log --oneline -5               # last 5 commits
git status --short                 # uncommitted changes
gh pr list --state open --limit 3  # open PRs (if gh available)
```

## Session Diff

Compare against session-start state (if known) to produce a diff:

```
REPO        BRANCH          COMMITS THIS SESSION   OPEN PRS
minibox     feat/gc-images  3 new commits          1 open
devloop     main            0                      0
doob        fix/sync        1 new commit           0
```

## Writing to Memory

Write session state to the project memory file:

```
~/.claude/projects/-Users-joe-dev-<repo>/memory/session_YYYY-MM-DD.md
```

Format:

```markdown
---
name: session-2026-04-03
description: Session state snapshot for 2026-04-03
type: project
---

## Session State — 2026-04-03

**Branch:** feat/gc-images
**Commits this session:** 3
**Last commit:** abc1234 fix: clean up GC loop

**Open PRs:**
- #42 feat: image GC (draft)

**Uncommitted changes:** none
```

## Writing to Obsidian

Append a section to today's daily note:

```
$HOME/Documents/Obsidian Vault/Daily Notes/YYYY-MM-DD.md
```

Append under a `## Session Pulse` heading:

```markdown
## Session Pulse

| Repo | Branch | Commits | Status |
|------|--------|---------|--------|
| minibox | feat/gc-images | +3 | clean |
| devloop | main | 0 | clean |
```

If the daily note doesn't exist, create it with the pulse section.

## Using the herald Agent

For a richer narrative synthesis (vs. raw state capture), invoke the `herald` agent:

> "Synthesize today's session into the Obsidian daily note"

`herald` produces prose summaries; `project-pulse` produces structured state tables.
Use both for complete session-end coverage: pulse first (structured), herald second (narrative).

## Pairing with handoff

After `project-pulse`, run `handoff` to write `HANDOFF.yaml` with actionable next steps.
The two skills complement each other: pulse captures what happened, handoff captures what's next.
