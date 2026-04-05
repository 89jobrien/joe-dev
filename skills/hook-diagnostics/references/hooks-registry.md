# Hooks Registry

Active hooks across all sources. Update this file when hooks are added or removed.

## Global Hooks (`~/.claude/settings.json`)

| Hook | Event | Script |
|---|---|---|
| rtk-rewrite.sh | PreToolUse/Bash | `~/.claude/hooks/rtk-rewrite.sh` |
| rtk-rewrite.nu | PreToolUse/Bash | `~/.claude/hooks/nu/pre/rtk-rewrite.nu` |
| pre-tool-course-correct.py | PreToolUse/Bash | `~/.claude/hooks/pre-tool-course-correct.py` |
| post-bash-redact.sh | PostToolUse/Bash | `~/.claude/hooks/post-bash-redact.sh` |
| post-tool-track-failures.py | PostToolUse/Bash | `~/.claude/hooks/post-tool-track-failures.py` |
| post-edit-cargo-fmt.nu | PostToolUse/Edit\|Write | `~/.claude/hooks/post-edit-cargo-fmt.nu` |
| post-edit-cargo-check.nu | PostToolUse/Edit\|Write | `~/.claude/hooks/post-edit-cargo-check.nu` |
| sync_memory_to_vault.py | PostToolUse/Edit\|Write | `~/.claude/hooks/sync_memory_to_vault.py` |

## Plugin Hooks

| Hook | Event | Plugin | Script |
|---|---|---|---|
| op-resolver-startup.sh | SessionStart | sanctum | `~/dev/sanctum/hooks/op-resolver-startup.sh` |

## Common Failure Causes

| Hook | Common Cause | Fix |
|---|---|---|
| `rtk-rewrite.sh` | rtk binary not on PATH | `which rtk` — reinstall if missing |
| `rtk-rewrite.nu` | nu not on PATH | `which nu` |
| `pre-tool-course-correct.py` | Python not found | `which python3` |
| `post-edit-cargo-fmt.nu` | nu not on PATH | `which nu` |
| `op-resolver-startup.sh` | 1Password not authed | `op account list` |

## Failure Log

Failures are written by `post-tool-track-failures.py` as JSON entries:

```
~/.claude/hooks/failures/failures.jsonl
```

Each entry: `timestamp`, `hook_name`, `exit_code`, `command`, `stderr`.
