# hooklings — Design Spec

**Date:** 2026-04-22
**Status:** Draft

---

## Overview

`hooklings` is a standalone Rust CLI that automates developer preflight checks. It loads a layered
YAML pipeline (`.crux` format, evaluated by `cruxx-script`) and emits results as both structured
JSON and a human-readable markdown summary table. It is independent of atelier but is typically
orchestrated by atelier's SessionStart hook.

---

## Repositories

| Repo                  | Purpose                                          |
| --------------------- | ------------------------------------------------ |
| `89jobrien/hooklings` | Standalone Rust binary — the `hooklings` CLI     |
| `89jobrien/crux`      | Gains `sqlite` handler module in `cruxx-agentic` |

---

## Architecture

### Binary: `hooklings`

Single Rust binary with subcommands:

```
hooklings preflight [--emit json|table|both]   # run all enabled checks
hooklings check <name>                          # run a single named check
hooklings config show                           # print merged effective config
```

The binary:

1. Loads and merges config (global → project-local)
2. Resolves which `.crux` pipeline file to use
3. Builds a `HandlerRegistry` with all hooklings handlers registered
4. Runs the pipeline via `cruxx-script`
5. Collects `CheckResult` values from the trace
6. Emits JSON to `~/.local/share/hooklings/last-preflight.json`
7. Emits a markdown table to stdout

### Pipeline Files

Pipelines are standard `.crux` YAML files (cruxx-script format). A default pipeline ships with
hooklings at `~/.config/hooklings/default.crux`. Users can override globally or per-project.

Default pipeline:

```yaml
pipeline: preflight
steps:
  - join_all: environment
    arms:
      - detect_shell
      - step: check_tools
        args:
          {
            tools:
              [
                nu,
                just,
                cargo,
                op,
                devkit,
                gkg,
                doob,
                handoff-db,
                handoff-detect,
              ],
          }
      - check_pwd

  - join_all: git
    arms:
      - git::status
      - step: git::log
        args: { n: 5 }

  - step: op::auth_check
    args: { enabled: false }

  - step: ssh::reachable
    args: { enabled: false, host: minibox }

  - step: handoff::pending

  - step: doob::pending
```

Optional checks (`op::auth_check`, `ssh::reachable`) are disabled by default and enabled via
config.

---

## Config System

### Discovery Order (layered, merged)

1. `~/.config/hooklings/hooklings.toml` — global base
2. `<repo-root>/.hooklings.toml` — per-project overrides

Later layers merge into earlier. Arrays replace (not append). Unknown keys are ignored.

### Schema

```toml
# ~/.config/hooklings/hooklings.toml

[pipeline]
default = "~/.config/hooklings/default.crux"

[checks.op_auth]
enabled = false

[checks.ssh_reachable]
enabled = false
host = "minibox"

[checks.doob_pending]
db = "~/.local/share/doob/doob.db"   # path to doob's SQLite DB

[checks.handoff_pending]
db = "~/.local/share/atelier/handoff.db"

[emit]
json_path = "~/.local/share/hooklings/last-preflight.json"
```

Per-project `.hooklings.toml` can override any key, e.g.:

```toml
[pipeline]
default = ".hooklings/ci-preflight.crux"

[checks.op_auth]
enabled = true

[checks.ssh_reachable]
enabled = true
host = "minibox"
```

---

## Handlers

### New handlers in `hooklings` (registered locally, not in crux)

| Handler            | Description                                                              |
| ------------------ | ------------------------------------------------------------------------ |
| `detect_shell`     | Reads `$SHELL`/`$0`, runs `which nu zsh bash`, returns `{shell, path}`   |
| `check_tools`      | Takes `tools: [...]`, runs `which` for each, returns pass/warn per tool  |
| `check_pwd`        | Returns `{cwd, project, workspace}` parsed from `$PWD`                   |
| `op::auth_check`   | Runs `op account list`, parses output, returns auth status               |
| `ssh::reachable`   | SSH connect with 3s timeout, returns reachable bool                      |
| `handoff::pending` | SQLite query against `handoff.db`, returns open items by project         |
| `doob::pending`    | SQLite query against doob's DB (path from config), returns pending todos |

All hooklings handlers respect an `enabled: bool` arg — if false, they return `Status::Skip`
without executing.

### New handlers in `cruxx-agentic` (reusable across any crux pipeline)

Module: `sqlite` — registered as `sqlite::*`.

All handlers share the base arg shape:

```json
{ "db": "<path>", "sql": "<query>", "params": { ":name": "value" } }
```

`params` is optional. Named bindings use SQLite `:name` style.

| Handler              | Returns                      | Notes                           |
| -------------------- | ---------------------------- | ------------------------------- |
| `sqlite::exec`       | `{ rows_affected: u64 }`     | DDL / fire-and-forget DML       |
| `sqlite::query_one`  | `{ row: {...} }`             | Error if 0 or >1 rows           |
| `sqlite::query_many` | `{ rows: [{...}] }`          | Empty array if no rows          |
| `sqlite::insert`     | `{ last_insert_rowid: i64 }` | INSERT with named params        |
| `sqlite::update`     | `{ rows_affected: u64 }`     | UPDATE with named params        |
| `sqlite::delete`     | `{ rows_affected: u64 }`     | DELETE with named params        |
| `sqlite::upsert`     | `{ rows_affected: u64 }`     | INSERT OR REPLACE / ON CONFLICT |

Dependency: `rusqlite` (pure-Rust, no libsqlite3-sys dynamic linking — use bundled feature).

---

## Output

### JSON (`~/.local/share/hooklings/last-preflight.json`)

```json
{
  "timestamp": "2026-04-22T09:14:00Z",
  "pipeline": "preflight",
  "results": [
    { "name": "detect_shell",  "status": "pass", "detail": "nu 0.102.0", "data": { "shell": "nu" } },
    { "name": "check_tools",   "status": "warn", "detail": "handoff-detect not found", "data": { ... } },
    { "name": "git::status",   "status": "pass", "detail": "clean", "data": { ... } },
    { "name": "op::auth_check","status": "skip", "detail": "disabled in config" }
  ]
}
```

### Markdown table (stdout)

```
| Check            | Status | Detail                     |
|------------------|--------|----------------------------|
| detect_shell     | PASS   | nu 0.102.0                 |
| check_tools      | WARN   | handoff-detect not found   |
| git::status      | PASS   | clean, branch: main        |
| git::log         | PASS   | 5 commits loaded           |
| op::auth_check   | SKIP   | disabled in config         |
| handoff::pending | PASS   | 3 open items               |
| doob::pending    | PASS   | 12 pending todos           |
```

---

## atelier Integration

atelier's SessionStart hook calls `hooklings preflight --emit both`. The markdown table is
printed into the conversation. The JSON file is available for any subsequent hook or skill to
read via `fs::read`.

The existing `session-start.nu` in `~/.claude/hooks/nu/session/` is updated to call hooklings
when it is on PATH, falling back to the current navigator hint if not installed.

---

## crux Changes Required

### `cruxx-agentic`

1. New file: `crates/cruxx-agentic/src/sqlite.rs` — implements all `sqlite::*` handlers
2. `crates/cruxx-agentic/src/handlers.rs` — add `sqlite::*` constants
3. `crates/cruxx-agentic/src/lib.rs` — register sqlite handlers in the default registry
4. `Cargo.toml` — add `rusqlite = { version = "...", features = ["bundled"] }`

### No changes to `cruxx-script`, `cruxx-core`, or other crates.

---

## hooklings Workspace Structure

```
hooklings/
├── Cargo.toml                  # workspace
├── crates/
│   └── hooklings/
│       ├── Cargo.toml
│       └── src/
│           ├── main.rs         # CLI entry — subcommands, config loading, emit
│           ├── config.rs       # hooklings.toml schema + layered merge
│           ├── emit.rs         # JSON + markdown table rendering
│           └── handlers/
│               ├── mod.rs
│               ├── env.rs      # detect_shell, check_tools, check_pwd
│               ├── op.rs       # op::auth_check
│               ├── ssh.rs      # ssh::reachable
│               ├── handoff.rs  # handoff::pending (sqlite query)
│               └── doob.rs     # doob::pending (sqlite query)
├── pipelines/
│   └── default.crux            # default preflight pipeline
├── .claude-plugin/             # (future) if published to bazaar
└── README.md
```

---

## Status Enum

```
Pass  — check succeeded
Warn  — check ran but found a non-fatal issue (missing optional tool, stale todo)
Fail  — check ran and found a blocking issue
Skip  — check disabled in config or not applicable
Error — check failed to run (process error, DB unavailable, etc.)
```

---

## Out of Scope

- No LLM steps in the preflight pipeline
- No modification of doob or atelier source code (atelier only updates its SessionStart hook)
- No Windows support
- Item 7 (1Password UUID lookup) and item 9 (`handon` skill) remain AI-instruction-only —
  they require judgment and are not automatable as deterministic checks
