---
name: hook-diagnostics
description: This skill should be used when the user asks to "show hook status",
  "hook failures", "what hooks ran", "why did my hook fail", "hook overhead",
  "list active hooks", or wants visibility into Claude Code hook execution and failures.
---

# hook-diagnostics

Surface Claude Code hook execution status, failures, and overhead from the current session.

## Hook Sources

Active hooks come from two sources:

1. **Global CLAUDE.md hooks** (defined in `~/.claude/settings.json`):
   - rtk-rewrite.sh (PreToolUse/Bash)
   - pre-tool-course-correct.py (PreToolUse/Bash)
   - post-bash-redact.sh (PostToolUse/Bash)
   - post-tool-track-failures.py (PostToolUse/Bash)
   - post-edit-cargo-fmt.nu (PostToolUse/Edit|Write)
   - post-edit-cargo-check.nu (PostToolUse/Edit|Write)
   - sync_memory_to_vault.py (PostToolUse/Edit|Write)

2. **Plugin hooks** (joe-secrets SessionStart):
   - op-resolver-startup.sh (SessionStart)

## Checking Hook Status

To list currently loaded hooks, run in Claude Code:

```
/hooks
```

To check hook failure logs from post-tool-track-failures.py:

## Reading Failure Logs

Failure logs are written by `post-tool-track-failures.py` as JSON entries to a single file:

```bash
# Show last 10 failures
tail -n 10 $HOME/.claude/hooks/failures/failures.jsonl 2>/dev/null || echo "No failures recorded"
```

Each entry contains: `timestamp`, `hook_name`, `exit_code`, `command`, `stderr`.

## Diagnosing a Specific Hook Failure

1. Identify the hook name from the failure log
2. Find the hook script path: `ls $HOME/.claude/hooks/`
3. Run the hook directly with sample input:
   ```bash
   echo '{"tool_name": "Bash", "tool_input": {"command": "echo test"}}' | \
     bash $HOME/.claude/hooks/<hook-name>.sh
   echo "Exit: $?"
   ```
4. Check stderr for error messages

## Hook Overhead

To estimate hook overhead, check the `rtk gain` command:

```bash
rtk gain
```

This shows token savings from rtk-rewrite and command history. Hook execution time is
not directly measured, but `claude --debug` shows hook timing in the debug log.

## Common Failures

| Hook | Common Cause | Fix |
|------|-------------|-----|
| rtk-rewrite.sh | rtk binary not on PATH | `which rtk` — reinstall if missing |
| pre-tool-course-correct.py | Python not found | `which python3` |
| post-edit-cargo-fmt.nu | nu not on PATH | `which nu` |
| op-resolver-startup.sh | 1Password not authed | `op account list` |
