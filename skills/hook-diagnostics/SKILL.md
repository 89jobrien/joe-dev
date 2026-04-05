---
name: hook-diagnostics
description: This skill should be used when the user asks to "show hook status",
  "hook failures", "what hooks ran", "why did my hook fail", "hook overhead",
  "list active hooks", or wants visibility into Claude Code hook execution and failures.
---

# hook-diagnostics

Surface Claude Code hook execution status, failures, and overhead from the current session.

## Hook Sources

See `references/hooks-registry.md` for the full hook inventory, failure causes, and log path.

## Checking Hook Status

To list currently loaded hooks, run in Claude Code:

```
/hooks
```

## Reading Failure Logs

```bash
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

```bash
rtk gain
```

Hook execution time is not directly measured, but `claude --debug` shows hook timing in the
debug log.
