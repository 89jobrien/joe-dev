# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

**Atelier** is a Claude Code plugin — a collection of skills and agents for personal dev workflow automation.
It is not a compiled application. There is no build step; everything is markdown and YAML.

Plugin version: `0.3.0` | Installed via the local marketplace at `~/.claude/plugins/local-marketplace/`.

## Setup & Reinstall

```bash
just init        # One-time setup: wire git hooks, verify tools, install plugin
just reinstall   # Reinstall plugin without re-running full init
```

The post-commit hook auto-reinstalls the plugin when `.claude-plugin/`, `skills/`, `agents/`, or `hooks/`
change — no manual step needed after edits.

## Architecture

```
atelier/
├── .claude-plugin/plugin.json   # Plugin manifest (name, version, skills, agents)
├── skills/                      # 10 skills — procedural markdown guides for Claude
├── agents/                      # 5 agents — thin wrappers that delegate to devkit
├── docs/design.md               # Authoritative design spec
└── justfile                     # Setup automation
```

### Skills (11)

| Skill                | Trigger examples                                                     |
| -------------------- | -------------------------------------------------------------------- |
| `cargo-gate`         | "run gates", "validate rust", "pre-commit check"                     |
| `sentinel-autofixer` | "apply review fixes", "fix sentinel suggestions"                     |
| `hook-diagnostics`   | "show hook status", "what hooks ran"                                 |
| `git-guard`          | "safe to commit", "check merge strategy"                             |
| `ci-assist`          | "edit workflow", "fix CI", "check cross-compile"                     |
| `project-pulse`      | "end session", "capture state", "session summary"                    |
| `handoff`            | "write handoff", "end of session"                                    |
| `handon`             | "start session", "orient to work", "what's outstanding"              |
| `handup`             | "survey all projects", "what's open across repos"                    |
| `handdown`           | "write back analysis", "annotate handoffs", "persist handup context" |
| `handover`           | "visualize the handoff", "show handoff"                              |
| `onboard`            | "onboard me", "how do I set up atelier"                              |

### Agents (5)

All agents are thin wrappers — domain logic lives in `devkit`. Do not embed behavior here.

| Agent       | Purpose                                                      |
| ----------- | ------------------------------------------------------------ |
| `sentinel`  | Structured code review (hexagonal arch, Rust/Go conventions) |
| `forge`     | Primary dev companion: design, debug, refactor               |
| `herald`    | Cross-repo activity → Obsidian daily note                    |
| `conductor` | devloop → doob → devkit workflow pipeline                    |
| `oxidizer`  | Rust-specific review (clippy, unsafe, edition 2024)          |

## Handoff System

Three-file model per project:

| File                                            | Committed | Purpose                                        |
| ----------------------------------------------- | --------- | ---------------------------------------------- |
| `.ctx/HANDOFF.<project>.<base>.yaml` (in `.ctx/`) | YES     | Source of truth — tasks, log, metadata         |
| `.ctx/HANDOFF.state.yaml`                       | NO        | Project snapshot (branch, build status, tests) |
| `.ctx/HANDOFF.md`                               | NO        | Rendered human-readable reference              |

Items have immutable `id`/`title`/`description`/`priority` (P0/P1/P2) and mutable `status`
(open/done/parked/blocked). The log section prepends newest-first. Items also sync to
`~/.local/share/atelier/handoff.db` (SQLite) for cross-session queries.

## Key Design Rules

- **Thin agents only** — agents delegate to `devkit`; no domain logic lives in `atelier/agents/`.
- **No duplicate hooks** — global hooks (`rtk-rewrite.sh`, `cargo-fmt.nu`, etc.) live in
  `~/.claude/hooks/`; never copy them here.
- **`cargo-gate` runs xtask first** — always calls `cargo xtask pre-commit`; the skill adds
  reporting on top, not a replacement.
- **Secrets split** — 1Password / `.envrc` logic belongs in the companion `sanctum` plugin, not here.

## Companion Plugins

| Plugin        | Role                                                                                   |
| ------------- | -------------------------------------------------------------------------------------- |
| `sanctum`     | 1Password auth + `.envrc` chain tracing (required for `git-guard` SSH signing)         |
| `hand`        | Standalone session handoff (optional; atelier's handoff skills are the preferred path) |
| `orca-strait` | Parallel TDD orchestrator for Rust workspaces (optional)                               |

## Session Flow

1. Session starts → `sanctum` validates 1Password auth, traces `.envrc`
2. `sanctum` hands off to `atelier:handon` → triages `HANDOFF.yaml` by priority
3. Work happens using skills (`cargo-gate`, `git-guard`, `ci-assist`, etc.)
4. Session ends → `project-pulse` captures state snapshot → `handoff` writes `HANDOFF.yaml` + `.ctx/`

## Adding or Editing Skills

Each skill lives at `skills/<name>/SKILL.md`. After editing:

1. Run `just reinstall` to reload into Claude Code.
2. Verify trigger phrases in `plugin.json` match the skill's `when_to_use` section.
3. Keep skills as procedural guides — steps Claude follows, not implementations.

## Editing `plugin.json`

The manifest at `.claude-plugin/plugin.json` registers all skills and agents. After any change:

```bash
just reinstall
```

If the skill cache appears stale, bump the `version` field to force invalidation.
