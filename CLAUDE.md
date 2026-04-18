# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

**Atelier** is a Claude Code plugin — a collection of skills and agents for personal dev workflow automation.
It is not a compiled application. There is no build step; everything is markdown and YAML.

Plugin version: auto-managed (git-hash based) | Installed via the bazaar marketplace.

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
├── skills/                      # 12 skills — procedural markdown guides for Claude
├── agents/                      # 5 agents — thin wrappers that delegate to devkit
├── bin/                         # handoff-detect, handoff-init, handoff-db, handoff-reconcile, migrate-handoff
├── docs/design.md               # Authoritative design spec
└── justfile                     # Setup automation
```

`bin/` is added to PATH automatically by Claude Code when the plugin is installed. Scripts there
are callable directly: `handoff-detect`, `handoff-init`, `handoff-db`, `handoff-reconcile`, `migrate-handoff`.

### Skills

| Skill                | Trigger examples                                                     |
| -------------------- | -------------------------------------------------------------------- |
| `cap`                | "/cap", "commit and push", "ship it", "save progress"               |
| `cargo-gate`         | "run gates", "validate rust", "pre-commit check"                     |
| `ci-assist`          | "edit workflow", "fix CI", "check cross-compile"                     |
| `eod`                | "/eod", "end of day", "wrap up session"                              |
| `git-guard`          | "safe to commit", "check merge strategy"                             |
| `handoff`            | "write handoff", "end of session"                                    |
| `handon`             | "start session", "orient to work", "what's outstanding"              |
| `handdown`           | "write back analysis", "annotate handoffs", "persist handup context" |
| `handover`           | "visualize the handoff", "show handoff"                              |
| `handup`             | "survey all projects", "what's open across repos"                    |
| `hook-diagnostics`   | "show hook status", "what hooks ran"                                 |
| `minion`             | "dispatch subagent", "run in parallel", "fast subtask"               |
| `onboard-atelier`    | "onboard me", "how do I set up atelier"                              |
| `project-pulse`      | "end session", "capture state", "session summary"                    |
| `sentinel-autofixer` | "apply review fixes", "fix sentinel suggestions"                     |
| `valerie`            | "manage todos", "add task", "list todos"                             |

### Agents

All agents are thin wrappers — domain logic lives in `devkit`. Do not embed behavior here.

| Agent       | Purpose                                                      |
| ----------- | ------------------------------------------------------------ |
| `sentinel`  | Structured code review (hexagonal arch, Rust/Go conventions) |
| `forge`     | Primary dev companion: design, debug, refactor               |
| `herald`    | Cross-repo activity → Obsidian daily note                    |
| `conductor` | devloop → doob → devkit workflow pipeline                    |
| `oxidizer`  | Rust-specific review (clippy, unsafe, edition 2024)          |
| `minion`    | General-purpose parallel worker for independent subtasks     |
| `maxion`    | Structured task planner for complex or ambiguous items       |
| `midion`    | Parallel worker dispatched by handon for backlog items       |
| `workshop`  | Full-suite test agent — verifies skill loading and plugin surface |

**Agent Permissions:**

- `forge` and `conductor` have `permissionMode: acceptEdits` — they can write/edit files without
  prompting. All other agents operate read-only and prompt before file changes.

## Handoff System

Three-file model per project:

| File                                              | Committed | Purpose                                        |
| ------------------------------------------------- | --------- | ---------------------------------------------- |
| `.ctx/HANDOFF.<name>.<base>.yaml` (in `.ctx/`)   | YES       | Source of truth — tasks, log, metadata         |
| `.ctx/HANDOFF.<name>.<base>.state.yaml`           | NO        | Project snapshot (branch, build status, tests) |
| `.ctx/HANDOFF.md`                                 | NO        | Rendered human-readable reference              |

`<name>` is derived from the nearest `Cargo.toml`/`pyproject.toml`/`go.mod`; `<base>` is the
repo root directory name. `handoff-init` creates stubs and manages the `.gitignore` block on
first use — it runs lazily via `handoff-detect` and never needs to be called directly.

Items have immutable `id`/`title`/`description`/`priority` (P0/P1/P2) and mutable `status`
(open/done/parked/blocked). The log section prepends newest-first. Items also sync to
`~/.local/share/atelier/handoff.db` (SQLite) for cross-session queries, and `handoff-reconcile`
is the scripted bridge that captures open HANDOFF items into the authoritative `doob` backlog.

## Key Design Rules

- **Thin agents only** — agents delegate to `devkit`; no domain logic lives in `atelier/agents/`.
- `.ctx/HANDOFF.state.yaml` is intentionally gitignored — it tracks local session state and appearing
  untracked in `git status` is normal, not a dirty tree.
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

`atelier`, `sanctum`, and `orca-strait` install from the `bazaar` marketplace. Register it once
per machine before any `@bazaar` install: `claude plugin marketplace add https://github.com/89jobrien/bazaar`
`hand` and `vault-keeper` have no GitHub remote — `@local` only.

## Session Flow

1. Session starts → `sanctum` validates 1Password auth, traces `.envrc`
2. `sanctum` hands off to `atelier:handon` → triages `.ctx/HANDOFF.<name>.<base>.yaml` by priority
3. Work happens using skills (`cargo-gate`, `git-guard`, `ci-assist`, etc.)
4. Session ends → `project-pulse` captures state snapshot → `handoff` writes `.ctx/HANDOFF` files

## Valerie Setup

`setup.nu` uses `input` and requires an interactive terminal — it fails in Claude Code's
non-interactive context. Write the config directly instead:

```yaml
# ~/.claude/plugins/cache/local/atelier/<version>/.claude-plugin/valerie.local.yaml
backend: doob
shell: nu
configured: YYYY-MM-DD
```

## Adding or Editing Skills

Each skill lives at `skills/<name>/SKILL.md`. After editing:

1. Run `just reinstall` to reload into Claude Code.
2. Skills are auto-discovered from `skills/` — no `plugin.json` changes needed for new skills.
3. Keep skills as procedural guides — steps Claude follows, not implementations.

## Editing `plugin.json`

The manifest at `.claude-plugin/plugin.json` registers plugin metadata and agents. After any change:

```bash
just reinstall
```

The `version` field is auto-set by the post-commit hook to the current git hash — do not set it
manually.
