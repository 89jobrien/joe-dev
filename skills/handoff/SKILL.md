---
name: handoff
description: This skill should be used when the user asks to "write handoff", "end of session",
  "capture handoff", "save handoff", "update HANDOFF.yaml", or wants to record current project
  state and outstanding work for the next session.
---

# handoff

Write `HANDOFF.yaml` in the current repo with completed work, newly discovered gaps, and
current project state. Designed to be read by `handon` at the start of the next session.

## HANDOFF.yaml Format

Write to `<repo-root>/HANDOFF.yaml`:

```yaml
updated: "2026-04-03T18:30:00Z"
project: minibox
branch: feat/gc-images

completed:
  - "Implemented image GC loop in gc.rs"
  - "Added unit tests for retention policy"
  - "Fixed off-by-one in layer ref counting"

in_progress:
  - task: "Integration test for GC under load"
    notes: "Needs minibox running on VPS — blocked until SSH key rotated"
    priority: high

gaps:
  - "Layer dedup logic not yet implemented — see issue #38"
  - "GC does not handle concurrent pulls — race condition possible"

next_session:
  - "SSH key rotation (prerequisite for VPS integration test)"
  - "Review sentinel suggestions from today's review"
  - "Open PR once integration test passes"

blockers:
  - "SSH key rotation required before VPS test"
```

## Gathering Content

Before writing, collect:

1. **Completed:** Ask user "What did we finish this session?" or infer from git log:
   ```bash
   git log --oneline --since="8 hours ago"
   ```

2. **In progress:** What was started but not finished? Check git status for uncommitted work.

3. **Gaps:** What was discovered but not addressed? Pull from sentinel observations,
   TODOs in code, or explicit user mentions.

4. **Next session:** What should be picked up immediately next time?

5. **Blockers:** What is preventing progress?

## Writing the File

Write to the repo root, overwriting any existing HANDOFF.yaml:

```bash
# Confirm repo root
git rev-parse --show-toplevel
```

Write the YAML with current timestamp in ISO 8601 format.

## After Writing

Confirm with the user:

> "HANDOFF.yaml written to `<path>`. Commit it?"

If yes:
```bash
git add HANDOFF.yaml && git commit -m "chore: update handoff for session end"
```
