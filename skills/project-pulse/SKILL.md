---
name: project-pulse
description:
  This skill should be used when the user asks to "end session", "capture state",
  "session summary", "what changed this session", "summarize repos", "write session notes",
  or wants to capture multi-repo state at the end of a work session.
---

# project-pulse

Capture branch/commit/PR state across all active repos at session end. Write to both
memory files and the Obsidian daily note.

See `references/active-repos.md` for the default repo list, output paths, and session diff
format. Edit that file to add or remove repos without touching this skill.

## State Capture Per Repo

Run for each repo in the active-repos list:

```bash
git -C ~/dev/<repo> branch --show-current
git -C ~/dev/<repo> log --oneline -5
git -C ~/dev/<repo> status --short
gh -C ~/dev/<repo> pr list --state open --limit 3 2>/dev/null || true
```

Skip repos where `git -C <path> status` fails (not a git repo or missing).

## Determining Session Commits

To count commits made this session (since session start), use the earliest log entry from
the current session as a boundary. If session start time is unknown, use last 4 hours:

```bash
git -C ~/dev/<repo> log --oneline --since="4 hours ago"
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

Only write memory files for repos where something actually happened (commits, PRs, or
uncommitted changes). Skip repos with zero activity.

## Writing to Obsidian

Append under `## Session Pulse` in today's daily note:

```
$HOME/Documents/Obsidian Vault/Daily Notes/YYYY-MM-DD.md
```

```markdown
## Session Pulse

| Repo    | Branch         | Commits | Status |
| ------- | -------------- | ------- | ------ |
| minibox | feat/gc-images | +3      | clean  |
| devloop | main           | 0       | clean  |
```

If the daily note doesn't exist, create it with the pulse section only — do not add
other content or headers beyond `# YYYY-MM-DD`.

If a `## Session Pulse` section already exists in the daily note (from an earlier pulse
run today), replace it entirely rather than appending a second table.

## Repos with No Activity

Include repos with zero commits in the table with `0` in the Commits column. This confirms
the repo was checked, not skipped. Omit repos entirely only if the git command fails.

## Using the herald Agent

For narrative synthesis, invoke the `herald` agent after pulse:

> "Synthesize today's session into the Obsidian daily note"

`herald` produces prose narrative; `project-pulse` produces structured state tables.
Run pulse first to generate the table, then herald to wrap it in context.

## Pairing with handoff

After `project-pulse`, run `handoff` to write `HANDOFF.yaml` with actionable next steps.
Pulse captures what happened; handoff captures what's next.

## Additional Resources

- **`references/active-repos.md`** — default repo list, session diff format, output paths.
  Edit this file to add or remove repos without touching this skill.
