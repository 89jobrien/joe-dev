---
name: hook-diagnostics
description: This skill should be used when the user asks to "show hook status",
  "hook failures", "what hooks ran", "why did my hook fail", "hook overhead",
  "list active hooks", or wants visibility into Claude Code hook execution and failures.
model: haiku
effort: low
allowed-tools:
  - Read
  - Bash
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
2. Locate the hook script:

   ```bash
   ls $HOME/.claude/hooks/
   ```

3. Run the hook directly with sample input to reproduce the failure:

   ```bash
   echo '{"tool_name": "Bash", "tool_input": {"command": "echo test"}}' | \
     bash $HOME/.claude/hooks/<hook-name>.sh
   echo "Exit: $?"
   ```

4. For `.nu` hooks, run with `nu` instead of `bash`:

   ```bash
   echo '{"tool_name": "Edit", "tool_input": {"file_path": "/tmp/test.rs"}}' | \
     nu $HOME/.claude/hooks/<hook-name>.nu
   ```

5. Check stderr for error messages — most hooks write diagnostics to stderr

## Identifying False Positives

Pre-commit and pre-push hooks use pattern detection (grep, regex) that can false-positive
on test data, string literals, and documentation content.

When a hook blocks a commit unexpectedly:

1. Do NOT modify test/doc content to work around the hook
2. Run the hook chain with verbose output to identify the exact pattern match:
   ```bash
   bash -x $HOME/.claude/hooks/<hook-name>.sh < /dev/null 2>&1 | head -30
   ```
3. Add a minimum exclusion to the allowlist for the matched path
4. Never guess which hook is the culprit — identify it first

## Hook Overhead

```bash
rtk gain
```

Hook execution time is not directly measured, but `claude --debug` shows hook timing in
the debug output. The `rtk gain` command shows cumulative token savings from the
`rtk-rewrite.sh` hook.

## Common Hook Issues

| Hook | Symptom | Fix |
|---|---|---|
| `rtk-rewrite.sh` | "rtk: command not found" | `which rtk` — reinstall via dotfiles |
| `pre-tool-course-correct.py` | Blocks every Bash call | Check `course-correct-rules.json` for overly broad rules |
| `post-edit-cargo-fmt.nu` | "nu: command not found" | `which nu` — install via mise |
| `post-edit-cargo-check.nu` | Runs after every edit (slow) | Expected behavior — check output for actual errors |
| `op-resolver-startup.sh` | "op: not authed" | `op account list` — re-auth 1Password |

## Verifying Hook Registration

Hooks are registered in `~/.claude/settings.json`. To verify:

```bash
# Read the hooks section of settings.json
```

Use the Read tool on `$HOME/.claude/settings.json` — never cat it (may contain sensitive values
in redact-sensitive output).

## Additional Resources

- **`references/hooks-registry.md`** — full hook inventory (global + plugin), common failure
  causes, failure log format and path
