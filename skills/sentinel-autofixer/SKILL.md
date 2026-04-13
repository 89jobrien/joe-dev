---
name: sentinel-autofixer
description:
  This skill should be used when the user asks to "apply review fixes",
  "fix sentinel suggestions", "auto-fix review", "apply code review", "batch apply
  sentinel fixes", or wants to automatically apply suggestion-level fixes from a
  sentinel code review report.
model: sonnet
effort: medium
allowed-tools:
  - Read
  - Edit
  - Grep
  - Glob
  - Bash
---

# sentinel-autofixer

Read a sentinel code review report, triage issues by severity, and apply
suggestion-level fixes in a single batch commit. Never auto-apply blocking issues.

## Triage Rules

Sentinel reports contain three categories:

| Category         | Action                                                             |
| ---------------- | ------------------------------------------------------------------ |
| **Blocking**     | Surface to user — do NOT auto-apply. Require explicit instruction. |
| **Suggestions**  | Apply automatically after dry-run confirmation.                    |
| **Observations** | Inform user — no action unless requested.                          |

## Workflow

1. Read the sentinel report from the current conversation or ask the user to paste it
2. Extract all suggestion-level items
3. Present a dry-run diff of proposed changes:
   ```
   SUGGESTION 1: [description]
   File: src/handler.rs:42
   - old code
   + new code
   ```
4. Ask: "Apply N suggestions? (yes/no/select)"
5. If yes: apply all changes, run `cargo check --workspace` to verify
6. If select: apply only confirmed items
7. Commit all applied fixes in one batch commit:
   ```bash
   git add -A && git commit -m "fix: apply sentinel suggestion-level fixes"
   ```

## Blocking Issues

When blocking issues are present, always surface them first:

> "Sentinel found N blocking issue(s) that require manual review:
>
> 1. [issue description] — [file:line]
>    These will NOT be auto-applied."

Do not proceed with suggestion fixes until the user acknowledges blocking issues.

## After Applying

After committing, run `cargo-gate` to verify the workspace still builds cleanly.
Report any regressions introduced by the applied fixes.

## Using the sentinel Agent

To generate a fresh sentinel report before auto-fixing, invoke the `sentinel` agent:

> "Review [file or diff] for issues"

The sentinel agent will produce a structured report that this skill can consume.

## Additional Resources

- **`references/report-format.md`** — sentinel report structure, severity taxonomy,
  dry-run diff format, selective application workflow, post-apply verification
