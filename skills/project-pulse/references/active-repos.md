# Active Repos

Default repos checked by `project-pulse`. Edit this file to add or remove repos.

## Repo List

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

## State Capture Per Repo

```bash
git branch --show-current          # current branch
git log --oneline -5               # last 5 commits
git status --short                 # uncommitted changes
gh pr list --state open --limit 3  # open PRs (if gh available)
```

## Session Diff Format

```
REPO        BRANCH          COMMITS THIS SESSION   OPEN PRS
minibox     feat/gc-images  3 new commits          1 open
devloop     main            0                      0
doob        fix/sync        1 new commit           0
```

## Output Paths

| Destination | Path |
|---|---|
| Memory file | `~/.claude/projects/-Users-joe-dev-<repo>/memory/session_YYYY-MM-DD.md` |
| Obsidian daily note | `~/Documents/Obsidian Vault/Daily Notes/YYYY-MM-DD.md` |

Append under a `## Session Pulse` heading in the daily note. Create the note if absent.
