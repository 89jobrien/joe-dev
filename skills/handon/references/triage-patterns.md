# Triage Patterns Reference

## Priority Classification Guide

Use these signals when inferring priority from freeform `HANDOFF.md` text:

| Signal words | Inferred priority |
|---|---|
| "broken", "fails", "segfault", "panic", "security", "blocked", "urgent", "can't deploy" | P0 |
| "fix", "implement", "specific file mentioned + known fix", "small change", "refactor X" | P1 |
| "explore", "consider", "nice to have", "someday", "low priority", "when time permits" | P2 |

When uncertain between P0 and P1: prefer P0. When uncertain between P1 and P2: prefer P1.
Never over-triage P2 items — they should be delegatable without user review.

## P0 Validation Sequence

Run in this order for each P0 item:

1. `git status --short` — check for uncommitted changes that might be the blocker
2. Language-appropriate check:
   - Rust: `cargo check --workspace 2>&1 | tail -10`
   - Go: `go build ./...`
   - Node: `npm run build 2>&1 | tail -10`
3. Relevant test run (scope to the affected module if possible)
4. Report finding verbatim — do not interpret or guess
5. Wait for explicit user go/no-go before taking action

A P0 is never acted on autonomously. Present findings and ask.

## P1 Autonomous Execution Rules

Execute P1 items without asking when ALL of these are true:

- The item description specifies a concrete change (file + fix)
- No destructive operations are required (no `rm`, `git reset --hard`, `DROP TABLE`)
- Fewer than 4 files need to change
- Tests pass after the change

Stop and surface to user when ANY of these occur:

- Scope expands: more files than described, or adjacent changes discovered
- Tests fail unexpectedly (not the known failure the item describes)
- A config/secret/credential change would be needed
- Another item's behavior would be affected

## P2 Subagent Dispatch Template

Each P2 subagent must receive an explicit task description. Template:

```
Task: <title from HANDOFF item>
Description: <description from HANDOFF item>
Files: <files from HANDOFF item, if any>
Allowed tools: Read, Grep, Glob, Bash, Edit, Write
Constraints:
  - Run git branch --show-current before every commit
  - Run cargo check --workspace after any Rust changes
  - Do not commit to main
  - Cap subagent chain at 1 level deep (no nested subagents)
```

Cap at 5 concurrent subagents. If more than 5 P2 items exist, queue the remainder and
dispatch as slots free up.

## Multi-Repo Sweep

When invoked from `~/dev` or another workspace root with no `.git`:

```bash
# Pattern to glob for
ls ~/dev/*/HANDOFF.*.yaml 2>/dev/null
```

Triage each repo's HANDOFF independently. Surface a combined report:

```
## Workspace Triage — ~/dev

### minibox
  P0: (none)
  P1: minibox-7 "Fix test flake in gc_loop"
  P2: minibox-8 "Add retry on upload timeout"

### devloop
  P0: devloop-2 "CI broken — clippy errors"
  ...
```

Ask the user which repo to focus on before executing P1 items across multiple repos.
Never execute P1 autonomously across >1 repo in a single invocation.

## Human-Edit Review Patterns

When surfacing `human-edit` entries for review:

- Show the original value (from git history if available) and the new value
- Group by item if multiple fields were edited on the same item
- Do not ask for approval to review — just present and proceed
- Record reviewed items internally; `handoff` skill stamps `reviewed: <today>` at session end

Example output:

```
## Review on Wake

- minibox-4 "Handler Coverage" — human edited `status` → `done` on 2026-04-03
  (note: PR merged out of band)

- minibox-6 "Log Rotation" — human edited `priority` → `P0` on 2026-04-05
```

After presenting: "Acknowledged. Proceeding to P0 triage."

## SQLite Sync Conflict Resolution

When SQLite status differs from YAML status for the same item:

| YAML status | SQLite status | Resolution |
|---|---|---|
| open | done | Trust SQLite — mark done in memory |
| done | open | Trust YAML — SQLite likely stale; note discrepancy |
| open | blocked | Trust SQLite — more recent signal |
| blocked | open | Trust YAML — SQLite may not have the blocker info |

General rule: trust SQLite for `done` and `blocked` (terminal states set by tools).
Trust YAML for `open` (YAML is the canonical source). Do not write back to YAML here.

## Edge: All Items Done or Parked

Report cleanly and stop:

```
## Handoff Triage — <repo>

All items are done or parked. No action needed.

Last log entry: <date> — <summary>
```

Offer to create new items if the user has work in mind.

## Edge: Blocked Items

Never attempt blocked items. Always report the blocker verbatim:

```
## P0 — BLOCKED

- minibox-3 "Publish crate to crates.io"
  BLOCKED: waiting on crates.io API token from team lead
  → No action possible. Awaiting external dependency.
```
