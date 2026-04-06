# doob CLI Reference

## Todo Commands

```bash
# Add
doob todo add "<description>" \
  [--priority <1-5>] \
  [-p <project>] \
  [-t <tag1,tag2>] \
  [--due YYYY-MM-DD]

# List
doob todo list \
  [--status pending|in_progress|completed|cancelled] \
  [-p <project>] \
  [-t <tag>] \
  [-l <limit>] \
  [--json]

# Complete
doob todo complete <id> [<id>...]

# Undo completion
doob todo undo <id> [<id>...]

# Remove
doob todo remove <id> [<id>...]

# Set due date
doob todo due <id> [YYYY-MM-DD|clear]

# Kanban board
doob kan [-p <project>] [--status pending,in_progress]
```

## Note Commands

```bash
doob note add "<content>" [-p <project>] [-t <tags>]
doob note list [-p <project>] [-l <limit>]
```

## Output Flags

Append `--json` to any command for machine-readable output.

## Priority Scale

| Value | Meaning |
|-------|---------|
| 5 | Critical — blocks other work, security/correctness issue |
| 4 | High — meaningful, should be done soon |
| 3 | Medium — good to have, fits in sprint |
| 2 | Low — nice to have |
| 1 | Unscored / someday |

## Project Inference

Doob uses the repo root basename as the project key by default. To confirm:

```bash
git rev-parse --show-toplevel | xargs basename
```

## JSON Output Shape

```json
{
  "id": "<uuid>",
  "description": "...",
  "priority": 3,
  "status": "pending",
  "project": "<project>",
  "tags": ["tag1", "tag2"],
  "due": null,
  "created_at": "..."
}
```
