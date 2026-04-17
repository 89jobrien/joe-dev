---
name: minion
description:
  Use when you need to dispatch one or more fast, cheap subagents for parallel or
  sequential work — research, summarize, transform, verify, batch-process, or any
  task that doesn't require a specialized agent. Invoke via the Agent tool with
  subagent_type "atelier:minion".
model: haiku
agent: minion
effort: low
argument-hint: "[task description]"
allowed-tools:
  - Agent(minion)
  - Read
  - Bash
---

# minion — Adaptive Subagent Dispatcher

## Overview

`atelier:minion` is a fast haiku-powered agent that adapts to any task. Use this skill
to decide when and how to dispatch minions, how many to run in parallel, and how to
synthesize their results.

## When to Use a Minion

| Situation | Use minion? |
|---|---|
| Quick read + summarize of 1–5 files | Yes |
| Batch task across N independent items | Yes (one per item) |
| Verify a condition (file exists, test passes, etc.) | Yes |
| Transform or reformat content | Yes |
| Complex multi-step implementation | No — use forge |
| Code review | No — use sentinel or oxidizer |
| Handoff / session management | No — use handoff/handon |

## Dispatching a Single Minion

```
Agent(
  subagent_type: "atelier:minion",
  prompt: "<clear, self-contained task description>"
)
```

The prompt must be fully self-contained — minion has no prior context. Include:
- What to do
- Where to find inputs (file paths, glob patterns, commands to run)
- What to return

## Dispatching Parallel Minions

Send multiple `Agent` tool calls in a single message. Cap at 5 concurrent.

```
Agent(subagent_type: "atelier:minion", prompt: "Summarize /path/to/file-a.md")
Agent(subagent_type: "atelier:minion", prompt: "Summarize /path/to/file-b.md")
Agent(subagent_type: "atelier:minion", prompt: "Summarize /path/to/file-c.md")
```

## Prompt Template

```
Task: <one sentence>

Input: <file paths, commands, or data>

Output: <exactly what to return — format, length, structure>

Constraints:
- <any tool restrictions, read-only, etc.>
```

## Synthesizing Results

After minions return, synthesize in the parent context — don't dispatch another minion
to summarize minion output unless the synthesis is itself a large batch job.

## Rules

- Keep prompts short and unambiguous — haiku works best with clear scope
- Prefer one focused minion over one vague minion
- If a task requires >5 sequential minion steps, consider forge instead
- Never dispatch a minion to do something you can do in one tool call yourself
