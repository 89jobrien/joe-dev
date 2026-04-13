---
name: onboard
description:
  Use when a user says "onboard me", "how do I set up atelier", "what does this plugin
  do", "walk me through setup", or invokes /atelier:onboard. Also suggested by handon when neither
  atelier nor sanctum appear to have been verified in a live session before.
model: haiku
effort: low
allowed-tools:
  - Read
  - Bash
---

# onboard — atelier + sanctum setup

## Overview

Four local plugins form the full dev workflow:

| Plugin          | Purpose                                                                       |
| --------------- | ----------------------------------------------------------------------------- |
| **atelier**     | Rust gates, code review, CI safety, multi-repo pulse, session handoffs        |
| **sanctum**     | 1Password auth validation, `.envrc` chain tracing, `op://` conflict detection |
| **hand**        | Standalone session handoff toolkit (HANDOFF.yaml + SQLite)                   |
| **orca-strait** | Parallel TDD sub-agent orchestrator for Rust workspaces                       |

atelier + sanctum are the core pair. hand and orca-strait are opt-in.

## Step 1: Prerequisites

```bash
which claude op direnv sqlite3 just
```

- `claude` — Claude Code CLI (required)
- `op` — 1Password CLI (required for sanctum): `brew install 1password-cli && op signin`
- `direnv` — optional; sanctum degrades gracefully without it
- `sqlite3` — local handoff DB (ships with macOS)
- `just` — task runner for init scripts: `brew install just`

## Step 2: Clone and Init All Plugins

Each plugin repo has a `just init` recipe that wires hooks, checks prerequisites, and installs
the plugin. Run with user approval for any missing tool.

```bash
# Core pair (always install both)
git clone https://github.com/89jobrien/atelier ~/dev/atelier
git clone https://github.com/89jobrien/sanctum ~/dev/sanctum
cd ~/dev/atelier && just init
cd ~/dev/sanctum && just init

# Optional
git clone https://github.com/89jobrien/hand ~/dev/hand
git clone https://github.com/89jobrien/orca-strait ~/dev/orca-strait
cd ~/dev/hand && just init
cd ~/dev/orca-strait && just init
```

Each `just init` will:

1. Set `core.hooksPath = .githooks` — post-commit auto-reinstalls plugin on source changes
2. Register the local marketplace at `~/.claude/plugins/local-marketplace`
3. Prompt for approval if required tools are missing
4. Install the plugin via `claude plugin install <name>@local`

## Step 3: Smoke Test — Skills

In a new Claude session, trigger each skill to confirm it loads:

| Skill                    | Test phrase              |
| ------------------------ | ------------------------ |
| atelier:onboard-atelier  | `/onboard-atelier`       |
| atelier:handon           | "what's outstanding"     |
| atelier:cargo-gate       | "run gates"              |
| atelier:hook-diagnostics | "show hook status"       |
| atelier:git-guard        | "safe to commit"         |
| sanctum:op-resolver      | `/op-resolver`           |
| orca-strait              | `/orca-strait --dry-run` |

Expected: Claude responds using skill content, not a generic answer.

## Step 4: Smoke Test — SessionStart Hook

Start a fresh Claude session. Within the first response, Claude should output a sanctum summary:

```
1Password: 2 account(s) authed.
Direnv chain: N .envrc file(s) found, N op:// refs.
```

If absent:

```bash
ls -l ~/dev/sanctum/hooks/
claude plugin list | grep sanctum
```

## Step 5: Verify Handoff Setup

```bash
ls ~/dev/*/HANDOFF.*.yaml 2>/dev/null | head -10
sqlite3 ~/.local/share/atelier/handoff.db "SELECT project, id, status FROM items;" 2>/dev/null
```

If no HANDOFF files exist, run `/hand:off` or `/atelier:handoff` at session end to create one.

## Auto-Reinstall on Edit

Every plugin repo has `.githooks/post-commit` that auto-reinstalls the plugin when
`skills/`, `agents/`, `hooks/`, or `.claude-plugin/` files change. This requires
`core.hooksPath = .githooks` — set by `just init`.

To reinstall manually without a full init:

```bash
cd ~/dev/<plugin> && just reinstall
```

## Onboarding Complete

> At every new session:
>
> 1. sanctum validates 1Password auth and traces your `.envrc` chain
> 2. atelier:handon surfaces outstanding HANDOFF items across active repos
>
> Run `/onboard-atelier` again any time to re-verify the setup.
