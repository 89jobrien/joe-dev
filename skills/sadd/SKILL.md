---
name: sadd
description: This skill should be used when the user asks to "run subagent-driven development",
  "execute plan with subagents", "dispatch implementer agents", "use sdd workflow", "sadd",
  or wants to implement a plan using parallel subagents with spec and quality review loops.
---

# Subagent-Driven Development (sadd)

Execute an implementation plan by dispatching fresh subagents per task, with two-stage review
after each: spec compliance first, then code quality.

**Core principle:** Fresh subagent per task + spec review + quality review = high-quality,
fast iteration with no context pollution between tasks.

## When to Use

Use sadd when:
- An implementation plan with mostly-independent tasks exists
- Work should happen in the current session (not handed off)
- Tasks can be reviewed for spec compliance and code quality independently

For parallel sessions instead, use `superpowers:executing-plans`.

## The Process

### Setup

1. Read the plan once; extract all tasks with full text and context.
2. Create a TodoWrite entry per task.
3. Set up a git worktree if not already on a feature branch (`superpowers:using-git-worktrees`).

### Per Task Loop

For each task, in sequence:

1. **Dispatch implementer subagent** using `references/implementer-prompt.md`.
   - Provide full task text (do not make subagent read the plan file).
   - Provide scene-setting context: where this fits, dependencies, architecture.
2. **Handle implementer status:**
   - `DONE` → proceed to spec review.
   - `DONE_WITH_CONCERNS` → read concerns; if correctness risk, address first; else proceed.
   - `NEEDS_CONTEXT` → provide missing info and re-dispatch.
   - `BLOCKED` → diagnose: add context, upgrade model, or break task down. Escalate to user
     only if none of those unblock.
3. **Dispatch spec compliance reviewer** using `references/spec-reviewer-prompt.md`.
   - ✅ compliant → proceed to quality review.
   - ❌ issues found → dispatch implementer (same subagent type) to fix; re-review until ✅.
4. **Dispatch code quality reviewer** using `references/code-quality-reviewer-prompt.md`.
   - ✅ approved → mark task complete in TodoWrite.
   - ❌ issues → dispatch implementer to fix; re-review until ✅.
5. Repeat for next task. Never dispatch two implementers in parallel — they conflict.

### Wrap-Up

After all tasks pass both reviews:
1. Dispatch a final code reviewer over the entire implementation (all commits).
2. Run `superpowers:finishing-a-development-branch`.

## Model Selection

| Task type | Model |
|---|---|
| Isolated function, 1-2 files, clear spec | `haiku` (fast/cheap) |
| Multi-file integration, pattern matching | `sonnet` (standard) |
| Architecture, design, broad codebase | `opus` (most capable) |

## Prompt Templates

Full prompt templates live in `references/`:

- **`references/implementer-prompt.md`** — dispatch template for implementer subagent
- **`references/spec-reviewer-prompt.md`** — dispatch template for spec compliance reviewer
- **`references/code-quality-reviewer-prompt.md`** — dispatch template for code quality reviewer

## Red Flags

**Never:**
- Start implementation on `main`/`master` without user consent.
- Skip either review stage (spec compliance AND code quality both required).
- Proceed past a review that found issues without fixing them.
- Dispatch multiple implementers in parallel.
- Pass plan file path to subagent — paste full task text instead.
- Accept "close enough" on spec compliance.
- Skip re-review after a fix.

**Always:**
- Answer implementer questions before allowing them to proceed.
- Verify implementer committed before dispatching reviewer.
- Provide BASE_SHA and HEAD_SHA to the code quality reviewer.
