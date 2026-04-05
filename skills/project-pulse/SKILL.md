---
name: project-pulse
description: This skill should be used when the user asks to "end session", "capture state",
  "session summary", "what changed this session", "summarize repos", "write session notes",
  or wants to capture multi-repo state at the end of a work session.
---

# project-pulse

Capture branch/commit/PR state across all active repos at session end. Write to both
memory files and the Obsidian daily note.

See `references/active-repos.md` for the default repo list, output paths, and session diff
format. Edit that file to add or remove repos without touching this skill.

## State Capture Per Repo

```bash
git branch --show-current
git log --oneline -5
git status --short
gh pr list --state open --limit 3
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

Append under `## Session Pulse` in today's daily note:

```
$HOME/Documents/Obsidian Vault/Daily Notes/YYYY-MM-DD.md
```

```markdown
## Session Pulse

| Repo | Branch | Commits | Status |
|------|--------|---------|--------|
| minibox | feat/gc-images | +3 | clean |
| devloop | main | 0 | clean |
```

If the daily note doesn't exist, create it with the pulse section.

## Using the herald Agent

For narrative synthesis, invoke the `herald` agent after pulse:

> "Synthesize today's session into the Obsidian daily note"

`herald` produces prose; `project-pulse` produces structured state tables. Run pulse first,
herald second.

## Pairing with handoff

After `project-pulse`, run `handoff` to write `HANDOFF.yaml` with actionable next steps.
Pulse captures what happened; handoff captures what's next.
