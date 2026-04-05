---
name: onboard
description: Use when a user says "onboard me", "how do I set up atelier", "what does this plugin
  do", "walk me through setup", or invokes /atelier:onboard. Also suggested by handon when neither
  atelier nor sanctum appear to have been verified in a live session before.
---

# onboard

Walk through atelier + sanctum installation, verify both plugins are working, and confirm
the SessionStart hook chain fires correctly.

## Step 1: Overview

Introduce the two-plugin setup:

> **atelier** — personal dev workflow: Rust gates, code review, CI safety, multi-repo pulse,
> session handoffs.
>
> **sanctum** — secrets and env management: 1Password auth validation, `.envrc` chain tracing,
> `op://` conflict detection.
>
> Both must be installed for the full session-start experience. sanctum's SessionStart hook
> runs first (secrets), then invokes atelier's `handon` skill (work orientation).

## Step 2: Verify Prerequisites

```bash
which claude op direnv
```

- `claude` — Claude Code CLI (required)
- `op` — 1Password CLI (required for sanctum)
- `direnv` — optional; sanctum degrades gracefully without it

If `op` is missing: `brew install 1password-cli` and sign in with `op signin`.

## Step 3: Install Both Plugins

```bash
claude --plugin-dir ~/dev/atelier --plugin-dir ~/dev/sanctum
```

Or if installed to `~/.claude/plugins/`:

```bash
claude --plugin-dir ~/.claude/plugins/atelier --plugin-dir ~/.claude/plugins/sanctum
```

## Step 4: Smoke Test — Skills

In the new Claude session, trigger each skill to confirm it loads:

| Skill | Test phrase |
|-------|-------------|
| onboard | `/atelier:onboard` |
| handon | "what's outstanding" |
| cargo-gate | "run gates" |
| hook-diagnostics | "show hook status" |
| git-guard | "safe to commit" |
| op-resolver | `/sanctum:op-resolver` |

Expected: Claude responds using the skill content, not a generic answer.

## Step 5: Smoke Test — SessionStart Hook

Start a fresh Claude session (close and reopen or `claude` in a new terminal). Within the
first response, Claude should output a `[sanctum session-start]` summary block showing:

```
1Password: 2 account(s) authed.
Direnv chain: N .envrc file(s) found, N op:// refs.
```

If this block is absent, check:

```bash
# Confirm hook script is executable
ls -l ~/dev/sanctum/hooks/op-resolver-startup.sh

# Confirm plugin is loaded
claude --list-plugins 2>/dev/null || echo "check plugin-dir flag"
```

## Step 6: Smoke Test — Agents

Run `/forge` and `/sentinel` to confirm agent delegation to devkit is wired:

- `/forge` — should open a dev companion session
- `/sentinel` — should open a code review session

If either fails with "unknown command", devkit may not be installed or accessible.

## Step 7: Verify Handoff Setup

```bash
ls ~/dev/*/HANDOFF.*.yaml 2>/dev/null | head -10
```

If no HANDOFF files exist, run `/hand:off` at session end to create the first one.

## Onboarding Complete

> atelier and sanctum are installed and verified. At every new session:
> 1. sanctum validates 1Password auth and traces your `.envrc` chain
> 2. handon surfaces outstanding HANDOFF items across active repos
>
> Run `/atelier:onboard` again any time to re-verify the setup.
