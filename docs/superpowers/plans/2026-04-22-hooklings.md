# hooklings CLI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a standalone `hooklings` Rust binary that runs layered YAML-defined preflight
checks via the crux pipeline engine and emits JSON + markdown table output.

**Architecture:** Single Rust workspace at `~/dev/hooklings`. Binary loads a `.crux` pipeline
via `cruxx-script`, builds a `HandlerRegistry` with hooklings-specific handlers (env, op, ssh,
handoff, doob), runs checks in parallel via `join_all`, and emits results as JSON to disk and a
markdown table to stdout. Config is layered TOML: global XDG + per-project override.

**Tech Stack:** Rust 2024, `clap` 4, `cruxx-script`/`cruxx-agentic` (path dep during dev),
`rusqlite` 0.32 (bundled), `toml` 0.8, `serde`/`serde_json`, `tempfile` 3, `proptest` 1.11,
`cargo-fuzz` / `libfuzzer-sys`.

**Prerequisite:** Plan `2026-04-22-sqlite-handlers.md` must be fully implemented and committed in
`~/dev/crux` before starting Task 5 (handoff/doob handlers).

---

## File Map

| Path | Action | Purpose |
|---|---|---|
| `hooklings/Cargo.toml` | Create | Workspace manifest |
| `hooklings/crates/hooklings/Cargo.toml` | Create | Crate manifest |
| `hooklings/crates/hooklings/src/main.rs` | Create | CLI entry — subcommands |
| `hooklings/crates/hooklings/src/config.rs` | Create | Layered TOML config |
| `hooklings/crates/hooklings/src/emit.rs` | Create | JSON + markdown table rendering |
| `hooklings/crates/hooklings/src/handlers/mod.rs` | Create | Handler registration |
| `hooklings/crates/hooklings/src/handlers/env.rs` | Create | `detect_shell`, `check_tools`, `check_pwd` |
| `hooklings/crates/hooklings/src/handlers/op.rs` | Create | `op::auth_check` |
| `hooklings/crates/hooklings/src/handlers/ssh.rs` | Create | `ssh::reachable` |
| `hooklings/crates/hooklings/src/handlers/handoff.rs` | Create | `handoff::pending` |
| `hooklings/crates/hooklings/src/handlers/doob.rs` | Create | `doob::pending` |
| `hooklings/crates/hooklings/tests/config.rs` | Create | Config merge unit tests + proptests |
| `hooklings/crates/hooklings/tests/emit.rs` | Create | Emit unit tests |
| `hooklings/crates/hooklings/tests/handlers_env.rs` | Create | env handler tests |
| `hooklings/crates/hooklings/tests/handlers_sqlite.rs` | Create | handoff/doob handler tests |
| `hooklings/crates/hooklings/tests/conformance.rs` | Create | All handlers registered conformance |
| `hooklings/fuzz/Cargo.toml` | Create | Fuzz workspace |
| `hooklings/fuzz/fuzz_targets/config_parse.rs` | Create | Fuzz TOML config parsing |
| `hooklings/fuzz/fuzz_targets/emit_table.rs` | Create | Fuzz markdown emit |
| `hooklings/pipelines/default.crux` | Create | Default preflight pipeline |
| `hooklings/README.md` | Create | Usage docs |

---

## Task 1: Bootstrap repo and workspace

**Files:**
- Create: `hooklings/Cargo.toml`
- Create: `hooklings/crates/hooklings/Cargo.toml`
- Create: `hooklings/crates/hooklings/src/main.rs`

- [ ] **Step 1: Create the repo**

```bash
gh repo create 89jobrien/hooklings --public --description "YAML-driven developer preflight checks via crux pipelines"
cd /Users/joe/dev
git clone https://github.com/89jobrien/hooklings hooklings
cd hooklings
```

- [ ] **Step 2: Create workspace `Cargo.toml`**

Create `/Users/joe/dev/hooklings/Cargo.toml`:

```toml
[workspace]
members = ["crates/*"]
resolver = "2"

[workspace.package]
version = "0.1.0"
edition = "2024"
rust-version = "1.85"
license = "MIT OR Apache-2.0"
authors = ["Joseph O'Brien"]
repository = "https://github.com/89jobrien/hooklings"
homepage = "https://github.com/89jobrien/hooklings"

[workspace.dependencies]
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"
clap = { version = "4", features = ["derive"] }
tokio = { version = "1", features = ["full"] }
thiserror = "2"
rusqlite = { version = "0.32", features = ["bundled"] }
tempfile = "3"
proptest = "1.11"
chrono = { version = "0.4", features = ["serde"] }
```

- [ ] **Step 3: Create crate `Cargo.toml`**

Create `/Users/joe/dev/hooklings/crates/hooklings/Cargo.toml`:

```toml
[package]
name = "hooklings"
version.workspace = true
edition.workspace = true
rust-version.workspace = true
license.workspace = true
authors.workspace = true
repository.workspace = true
homepage.workspace = true

[[bin]]
name = "hooklings"
path = "src/main.rs"

[dependencies]
serde = { workspace = true }
serde_json = { workspace = true }
toml = { workspace = true }
clap = { workspace = true }
tokio = { workspace = true }
thiserror = { workspace = true }
rusqlite = { workspace = true }
chrono = { workspace = true }
cruxx-script = { path = "/Users/joe/dev/crux/crates/cruxx-script" }
cruxx-agentic = { path = "/Users/joe/dev/crux/crates/cruxx-agentic" }
cruxx-core = { path = "/Users/joe/dev/crux/crates/cruxx-core" }

[dev-dependencies]
tempfile = { workspace = true }
proptest = { workspace = true }
tokio = { workspace = true }
```

- [ ] **Step 4: Write minimal `main.rs` stub**

Create `/Users/joe/dev/hooklings/crates/hooklings/src/main.rs`:

```rust
fn main() {
    println!("hooklings");
}
```

- [ ] **Step 5: Verify it compiles**

```bash
cd /Users/joe/dev/hooklings
cargo build
```

Expected: compiles, prints `hooklings` when run.

- [ ] **Step 6: Initial commit**

```bash
cd /Users/joe/dev/hooklings
git add .
git commit -m "chore: scaffold hooklings workspace"
git push -u origin main
```

---

## Task 2: Config module (layered TOML)

**Files:**
- Create: `crates/hooklings/src/config.rs`
- Create: `crates/hooklings/tests/config.rs`

- [ ] **Step 1: Write failing tests first**

Create `crates/hooklings/tests/config.rs`:

```rust
use hooklings::config::{ChecksConfig, Config, EmitConfig, PipelineConfig};
use std::io::Write;
use tempfile::NamedTempFile;

fn write_toml(content: &str) -> NamedTempFile {
    let mut f = NamedTempFile::new().unwrap();
    f.write_all(content.as_bytes()).unwrap();
    f
}

#[test]
fn default_config_has_expected_values() {
    let cfg = Config::default();
    assert!(!cfg.checks.op_auth.enabled);
    assert!(!cfg.checks.ssh_reachable.enabled);
    assert_eq!(cfg.checks.ssh_reachable.host, "minibox");
    assert!(cfg.emit.json_path.contains("hooklings"));
}

#[test]
fn load_from_toml_overrides_defaults() {
    let f = write_toml(
        r#"
[checks.op_auth]
enabled = true

[checks.ssh_reachable]
enabled = true
host = "my-vps"
"#,
    );
    let cfg = Config::load_from_file(f.path()).unwrap();
    assert!(cfg.checks.op_auth.enabled);
    assert!(cfg.checks.ssh_reachable.enabled);
    assert_eq!(cfg.checks.ssh_reachable.host, "my-vps");
}

#[test]
fn merge_project_over_global() {
    let global = write_toml(
        r#"
[checks.op_auth]
enabled = false

[checks.ssh_reachable]
host = "global-host"
"#,
    );
    let project = write_toml(
        r#"
[checks.op_auth]
enabled = true
"#,
    );
    let base = Config::load_from_file(global.path()).unwrap();
    let overlay = Config::load_from_file(project.path()).unwrap();
    let merged = base.merge(overlay);
    assert!(merged.checks.op_auth.enabled);
    // project didn't override ssh host — global value preserved
    assert_eq!(merged.checks.ssh_reachable.host, "global-host");
}

#[test]
fn invalid_toml_returns_error() {
    let f = write_toml("this is not toml ][[[");
    let result = Config::load_from_file(f.path());
    assert!(result.is_err());
}

#[test]
fn missing_file_returns_error() {
    let result = Config::load_from_file(std::path::Path::new("/nonexistent/path/hooklings.toml"));
    assert!(result.is_err());
}

#[test]
fn pipeline_path_override() {
    let f = write_toml(
        r#"
[pipeline]
default = "/tmp/my.crux"
"#,
    );
    let cfg = Config::load_from_file(f.path()).unwrap();
    assert_eq!(cfg.pipeline.default, "/tmp/my.crux");
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/joe/dev/hooklings
cargo nextest run -p hooklings --test config
```

Expected: compile error — `config` module not found.

- [ ] **Step 3: Implement `config.rs`**

Create `crates/hooklings/src/config.rs`:

```rust
//! Layered TOML configuration for hooklings.
//!
//! Discovery order:
//! 1. `~/.config/hooklings/hooklings.toml` — global base
//! 2. `<repo-root>/.hooklings.toml` — per-project override
//!
//! Call `Config::load()` to auto-discover and merge both layers.
//! Call `Config::load_from_file(path)` for explicit loading (used in tests).

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("IO error reading {path}: {source}")]
    Io {
        path: PathBuf,
        #[source]
        source: std::io::Error,
    },
    #[error("TOML parse error in {path}: {source}")]
    Toml {
        path: PathBuf,
        #[source]
        source: toml::de::Error,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct Config {
    #[serde(default)]
    pub pipeline: PipelineConfig,
    #[serde(default)]
    pub checks: ChecksConfig,
    #[serde(default)]
    pub emit: EmitConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PipelineConfig {
    pub default: String,
}

impl Default for PipelineConfig {
    fn default() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
        Self {
            default: format!("{home}/.config/hooklings/default.crux"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct ChecksConfig {
    #[serde(default)]
    pub op_auth: OpAuthConfig,
    #[serde(default)]
    pub ssh_reachable: SshConfig,
    #[serde(default)]
    pub handoff_pending: HandoffConfig,
    #[serde(default)]
    pub doob_pending: DoobConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpAuthConfig {
    pub enabled: bool,
}

impl Default for OpAuthConfig {
    fn default() -> Self {
        Self { enabled: false }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SshConfig {
    pub enabled: bool,
    pub host: String,
}

impl Default for SshConfig {
    fn default() -> Self {
        Self {
            enabled: false,
            host: "minibox".into(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HandoffConfig {
    pub db: String,
}

impl Default for HandoffConfig {
    fn default() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
        Self {
            db: format!("{home}/.local/share/atelier/handoff.db"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DoobConfig {
    pub db: String,
}

impl Default for DoobConfig {
    fn default() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
        Self {
            db: format!("{home}/.local/share/doob/doob.db"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EmitConfig {
    pub json_path: String,
}

impl Default for EmitConfig {
    fn default() -> Self {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
        Self {
            json_path: format!("{home}/.local/share/hooklings/last-preflight.json"),
        }
    }
}

impl Config {
    /// Load config from a single TOML file. Missing keys use type defaults.
    pub fn load_from_file(path: &Path) -> Result<Self, ConfigError> {
        let raw = std::fs::read_to_string(path).map_err(|source| ConfigError::Io {
            path: path.to_path_buf(),
            source,
        })?;
        toml::from_str(&raw).map_err(|source| ConfigError::Toml {
            path: path.to_path_buf(),
            source,
        })
    }

    /// Auto-discover and merge global + project-local configs.
    ///
    /// Returns the merged config. If neither file exists, returns `Config::default()`.
    pub fn load() -> Self {
        let global = Self::global_path();
        let project = Self::project_path();

        let base = if global.exists() {
            Self::load_from_file(&global).unwrap_or_default()
        } else {
            Self::default()
        };

        if let Some(proj_path) = project.filter(|p| p.exists()) {
            let overlay = Self::load_from_file(&proj_path).unwrap_or_default();
            base.merge(overlay)
        } else {
            base
        }
    }

    /// Merge `other` on top of `self`. Fields in `other` that are non-default override `self`.
    /// Simple field-level override — no deep array merging.
    pub fn merge(self, other: Self) -> Self {
        // Re-serialize both to TOML Values, overlay other onto self, deserialize back.
        // This lets unset fields in `other` (which deserialize to defaults) not clobber `self`.
        // We do a manual field merge to avoid re-serialization complexity.
        Self {
            pipeline: if other.pipeline.default != PipelineConfig::default().default {
                other.pipeline
            } else {
                self.pipeline
            },
            checks: ChecksConfig {
                op_auth: OpAuthConfig {
                    enabled: if other.checks.op_auth.enabled {
                        true
                    } else {
                        self.checks.op_auth.enabled
                    },
                },
                ssh_reachable: SshConfig {
                    enabled: other.checks.ssh_reachable.enabled || self.checks.ssh_reachable.enabled,
                    host: if other.checks.ssh_reachable.host != SshConfig::default().host {
                        other.checks.ssh_reachable.host
                    } else {
                        self.checks.ssh_reachable.host
                    },
                },
                handoff_pending: HandoffConfig {
                    db: if other.checks.handoff_pending.db != HandoffConfig::default().db {
                        other.checks.handoff_pending.db
                    } else {
                        self.checks.handoff_pending.db
                    },
                },
                doob_pending: DoobConfig {
                    db: if other.checks.doob_pending.db != DoobConfig::default().db {
                        other.checks.doob_pending.db
                    } else {
                        self.checks.doob_pending.db
                    },
                },
            },
            emit: if other.emit.json_path != EmitConfig::default().json_path {
                other.emit
            } else {
                self.emit
            },
        }
    }

    fn global_path() -> PathBuf {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
        PathBuf::from(home).join(".config/hooklings/hooklings.toml")
    }

    fn project_path() -> Option<PathBuf> {
        // Walk up from cwd looking for .hooklings.toml
        let mut dir = std::env::current_dir().ok()?;
        loop {
            let candidate = dir.join(".hooklings.toml");
            if candidate.exists() {
                return Some(candidate);
            }
            if !dir.pop() {
                return None;
            }
        }
    }
}
```

- [ ] **Step 4: Expose config module in `main.rs`**

Replace `main.rs` content:

```rust
pub mod config;
pub mod emit;
pub mod handlers;

fn main() {
    println!("hooklings stub");
}
```

(Other modules will be added as stubs in later tasks.)

- [ ] **Step 5: Run tests**

```bash
cd /Users/joe/dev/hooklings
cargo nextest run -p hooklings --test config
```

Expected: all 6 tests PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/joe/dev/hooklings
git add crates/hooklings/src/config.rs crates/hooklings/src/main.rs \
  crates/hooklings/tests/config.rs
git commit -m "feat(hooklings): layered TOML config with merge"
git push
```

---

## Task 3: Config property tests

**Files:**
- Modify: `crates/hooklings/tests/config.rs`

- [ ] **Step 1: Append property tests**

Append to `crates/hooklings/tests/config.rs`:

```rust
use proptest::prelude::*;
use std::io::Write;

proptest! {
    #![proptest_config(proptest::test_runner::Config::with_cases(128))]

    /// Property: loading a valid TOML file never panics, always returns Ok or a clean error.
    #[test]
    fn load_never_panics_on_any_toml(content in "[^\x00]{0,512}") {
        let mut f = NamedTempFile::new().unwrap();
        let _ = f.write_all(content.as_bytes());
        // Must not panic — Ok or Err both accepted
        let _ = Config::load_from_file(f.path());
    }

    /// Property: merging any two configs never panics.
    #[test]
    fn merge_never_panics(
        op_enabled_a in proptest::bool::ANY,
        op_enabled_b in proptest::bool::ANY,
        host_a in "[a-z]{1,20}",
        host_b in "[a-z]{1,20}",
    ) {
        let a = Config {
            checks: ChecksConfig {
                op_auth: OpAuthConfig { enabled: op_enabled_a },
                ssh_reachable: SshConfig { enabled: false, host: host_a },
                ..Default::default()
            },
            ..Default::default()
        };
        let b = Config {
            checks: ChecksConfig {
                op_auth: OpAuthConfig { enabled: op_enabled_b },
                ssh_reachable: SshConfig { enabled: false, host: host_b },
                ..Default::default()
            },
            ..Default::default()
        };
        // Must not panic
        let _ = a.merge(b);
    }

    /// Property: merge is idempotent when both sides are identical.
    #[test]
    fn merge_identical_is_identity(enabled in proptest::bool::ANY) {
        let a = Config {
            checks: ChecksConfig {
                op_auth: OpAuthConfig { enabled },
                ..Default::default()
            },
            ..Default::default()
        };
        let b = a.clone();
        let merged = a.clone().merge(b);
        prop_assert_eq!(merged.checks.op_auth.enabled, a.checks.op_auth.enabled);
    }
}
```

- [ ] **Step 2: Run property tests**

```bash
cd /Users/joe/dev/hooklings
cargo nextest run -p hooklings --test config
```

Expected: all tests PASS including property cases.

- [ ] **Step 3: Commit**

```bash
cd /Users/joe/dev/hooklings
git add crates/hooklings/tests/config.rs
git commit -m "test(hooklings): property tests for config merge invariants"
git push
```

---

## Task 4: Emit module (JSON + markdown table)

**Files:**
- Create: `crates/hooklings/src/emit.rs`
- Create: `crates/hooklings/tests/emit.rs`

- [ ] **Step 1: Write failing tests**

Create `crates/hooklings/tests/emit.rs`:

```rust
use hooklings::emit::{CheckResult, Emitter, Status};
use serde_json::json;

fn sample_results() -> Vec<CheckResult> {
    vec![
        CheckResult {
            name: "detect_shell".into(),
            status: Status::Pass,
            detail: "nu 0.102.0".into(),
            data: Some(json!({ "shell": "nu" })),
        },
        CheckResult {
            name: "check_tools".into(),
            status: Status::Warn,
            detail: "handoff-detect not found".into(),
            data: None,
        },
        CheckResult {
            name: "op::auth_check".into(),
            status: Status::Skip,
            detail: "disabled in config".into(),
            data: None,
        },
        CheckResult {
            name: "git::status".into(),
            status: Status::Fail,
            detail: "dirty tree".into(),
            data: None,
        },
    ]
}

#[test]
fn markdown_table_contains_all_check_names() {
    let table = Emitter::markdown_table(&sample_results());
    assert!(table.contains("detect_shell"));
    assert!(table.contains("check_tools"));
    assert!(table.contains("op::auth_check"));
    assert!(table.contains("git::status"));
}

#[test]
fn markdown_table_contains_status_labels() {
    let table = Emitter::markdown_table(&sample_results());
    assert!(table.contains("PASS"));
    assert!(table.contains("WARN"));
    assert!(table.contains("SKIP"));
    assert!(table.contains("FAIL"));
}

#[test]
fn markdown_table_has_header_row() {
    let table = Emitter::markdown_table(&sample_results());
    assert!(table.contains("| Check"));
    assert!(table.contains("| Status"));
    assert!(table.contains("| Detail"));
}

#[test]
fn json_output_contains_results_array() {
    let emitter = Emitter::new("preflight".into());
    let json = emitter.to_json(&sample_results());
    assert!(json["results"].is_array());
    assert_eq!(json["results"].as_array().unwrap().len(), 4);
    assert_eq!(json["pipeline"], "preflight");
    assert!(json["timestamp"].is_string());
}

#[test]
fn json_result_has_required_fields() {
    let emitter = Emitter::new("preflight".into());
    let json = emitter.to_json(&sample_results());
    let first = &json["results"][0];
    assert_eq!(first["name"], "detect_shell");
    assert_eq!(first["status"], "pass");
    assert!(first["detail"].is_string());
}

#[test]
fn write_json_creates_file() {
    let dir = tempfile::tempdir().unwrap();
    let path = dir.path().join("out.json");
    let emitter = Emitter::new("preflight".into());
    emitter.write_json(&sample_results(), &path).unwrap();
    assert!(path.exists());
    let content = std::fs::read_to_string(&path).unwrap();
    let parsed: serde_json::Value = serde_json::from_str(&content).unwrap();
    assert!(parsed["results"].is_array());
}

#[test]
fn status_display() {
    assert_eq!(Status::Pass.as_str(), "pass");
    assert_eq!(Status::Warn.as_str(), "warn");
    assert_eq!(Status::Fail.as_str(), "fail");
    assert_eq!(Status::Skip.as_str(), "skip");
    assert_eq!(Status::Error.as_str(), "error");
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/joe/dev/hooklings
cargo nextest run -p hooklings --test emit
```

Expected: compile error — `emit` module not found.

- [ ] **Step 3: Implement `emit.rs`**

Create `crates/hooklings/src/emit.rs`:

```rust
//! Emit preflight results as JSON to disk and a markdown table to stdout.

use chrono::Utc;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::path::Path;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Status {
    Pass,
    Warn,
    Fail,
    Skip,
    Error,
}

impl Status {
    pub fn as_str(&self) -> &'static str {
        match self {
            Status::Pass => "pass",
            Status::Warn => "warn",
            Status::Fail => "fail",
            Status::Skip => "skip",
            Status::Error => "error",
        }
    }

    pub fn label(&self) -> &'static str {
        match self {
            Status::Pass => "PASS",
            Status::Warn => "WARN",
            Status::Fail => "FAIL",
            Status::Skip => "SKIP",
            Status::Error => "ERROR",
        }
    }
}

#[derive(Debug, Clone)]
pub struct CheckResult {
    pub name: String,
    pub status: Status,
    pub detail: String,
    pub data: Option<Value>,
}

pub struct Emitter {
    pipeline: String,
}

impl Emitter {
    pub fn new(pipeline: String) -> Self {
        Self { pipeline }
    }

    /// Render results as a GitHub-flavored markdown table.
    pub fn markdown_table(results: &[CheckResult]) -> String {
        let mut out = String::new();
        out.push_str("| Check | Status | Detail |\n");
        out.push_str("|---|---|---|\n");
        for r in results {
            out.push_str(&format!(
                "| {} | {} | {} |\n",
                r.name,
                r.status.label(),
                r.detail
            ));
        }
        out
    }

    /// Serialize results to a JSON `Value`.
    pub fn to_json(&self, results: &[CheckResult]) -> Value {
        let items: Vec<Value> = results
            .iter()
            .map(|r| {
                let mut obj = json!({
                    "name": r.name,
                    "status": r.status.as_str(),
                    "detail": r.detail,
                });
                if let Some(data) = &r.data {
                    obj["data"] = data.clone();
                }
                obj
            })
            .collect();

        json!({
            "timestamp": Utc::now().to_rfc3339(),
            "pipeline": self.pipeline,
            "results": items,
        })
    }

    /// Write JSON to the given path, creating parent dirs if needed.
    pub fn write_json(&self, results: &[CheckResult], path: &Path) -> std::io::Result<()> {
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let json = self.to_json(results);
        let serialized = serde_json::to_string_pretty(&json)?;
        std::fs::write(path, serialized)
    }
}
```

- [ ] **Step 4: Add `chrono` to dependencies**

In `crates/hooklings/Cargo.toml`, verify `chrono` is listed under `[dependencies]`. It should be
from the workspace dep added in Task 1.

- [ ] **Step 5: Run tests**

```bash
cd /Users/joe/dev/hooklings
cargo nextest run -p hooklings --test emit
```

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/joe/dev/hooklings
git add crates/hooklings/src/emit.rs crates/hooklings/tests/emit.rs
git commit -m "feat(hooklings): emit module — JSON and markdown table output"
git push
```

---

## Task 5: env handlers (`detect_shell`, `check_tools`, `check_pwd`)

**Files:**
- Create: `crates/hooklings/src/handlers/mod.rs`
- Create: `crates/hooklings/src/handlers/env.rs`
- Create: `crates/hooklings/tests/handlers_env.rs`

- [ ] **Step 1: Write failing tests**

Create `crates/hooklings/tests/handlers_env.rs`:

```rust
use hooklings::handlers::env;
use cruxx_script::HandlerRegistry;
use serde_json::json;

fn registry() -> HandlerRegistry {
    let mut r = HandlerRegistry::new();
    env::register(&mut r);
    r
}

#[tokio::test]
async fn detect_shell_returns_shell_field() {
    let reg = registry();
    let h = reg.get_handler("detect_shell").unwrap();
    let result = h(json!({})).await.unwrap();
    assert!(result["shell"].is_string());
    assert!(result["path"].is_string());
}

#[tokio::test]
async fn check_tools_pass_for_known_tools() {
    let reg = registry();
    let h = reg.get_handler("check_tools").unwrap();
    // `cargo` must be on PATH in this environment
    let result = h(json!({"args": {"tools": ["cargo"]}})).await.unwrap();
    let tools = result["tools"].as_array().unwrap();
    assert!(!tools.is_empty());
    let cargo = tools.iter().find(|t| t["name"] == "cargo").unwrap();
    assert_eq!(cargo["status"], "pass");
}

#[tokio::test]
async fn check_tools_warn_for_missing_tools() {
    let reg = registry();
    let h = reg.get_handler("check_tools").unwrap();
    let result = h(json!({"args": {"tools": ["this-tool-definitely-does-not-exist-xyz"]}}))
        .await
        .unwrap();
    let tools = result["tools"].as_array().unwrap();
    let missing = tools
        .iter()
        .find(|t| t["name"] == "this-tool-definitely-does-not-exist-xyz")
        .unwrap();
    assert_eq!(missing["status"], "warn");
}

#[tokio::test]
async fn check_tools_empty_list_returns_empty_array() {
    let reg = registry();
    let h = reg.get_handler("check_tools").unwrap();
    let result = h(json!({"args": {"tools": []}})).await.unwrap();
    let tools = result["tools"].as_array().unwrap();
    assert_eq!(tools.len(), 0);
}

#[tokio::test]
async fn check_pwd_returns_cwd_project_workspace() {
    let reg = registry();
    let h = reg.get_handler("check_pwd").unwrap();
    let result = h(json!({})).await.unwrap();
    assert!(result["cwd"].is_string());
    // project and workspace may be null if not in a dev workspace
    assert!(result.get("project").is_some());
    assert!(result.get("workspace").is_some());
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/joe/dev/hooklings
cargo nextest run -p hooklings --test handlers_env
```

Expected: compile error — handlers module not found.

- [ ] **Step 3: Create `handlers/mod.rs`**

Create `crates/hooklings/src/handlers/mod.rs`:

```rust
pub mod doob;
pub mod env;
pub mod handoff;
pub mod op;
pub mod ssh;

use cruxx_script::HandlerRegistry;

/// Register all hooklings handlers into the given registry.
pub fn register_all(registry: &mut HandlerRegistry, config: &crate::config::Config) {
    env::register(registry);
    op::register(registry, config.checks.op_auth.enabled);
    ssh::register(registry, config.checks.ssh_reachable.enabled, &config.checks.ssh_reachable.host);
    handoff::register(registry, &config.checks.handoff_pending.db);
    doob::register(registry, &config.checks.doob_pending.db);
}
```

- [ ] **Step 4: Implement `handlers/env.rs`**

Create `crates/hooklings/src/handlers/env.rs`:

```rust
//! Environment check handlers: detect_shell, check_tools, check_pwd.

use cruxx_core::prelude::CruxErr;
use cruxx_script::HandlerRegistry;
use serde_json::{Value, json};
use tokio::process::Command;

pub fn register(registry: &mut HandlerRegistry) {
    registry.handler_value("detect_shell", |_input: Value| async move {
        let shell_env = std::env::var("SHELL").unwrap_or_default();
        // Try `which nu`, `which zsh`, `which bash` in order; return first found
        let candidates = ["nu", "zsh", "bash"];
        let mut detected = shell_env.clone();
        let mut path = String::new();

        for candidate in candidates {
            if let Ok(out) = Command::new("which").arg(candidate).output().await {
                if out.status.success() {
                    let p = String::from_utf8_lossy(&out.stdout).trim().to_string();
                    if !p.is_empty() {
                        detected = candidate.to_string();
                        path = p;
                        break;
                    }
                }
            }
        }

        if path.is_empty() {
            path = shell_env.clone();
        }

        Ok(json!({ "shell": detected, "path": path, "SHELL": shell_env }))
    });

    registry.handler_value("check_tools", |input: Value| async move {
        let tools: Vec<String> = input
            .get("args")
            .and_then(|a| a.get("tools"))
            .and_then(|t| t.as_array())
            .map(|arr| {
                arr.iter()
                    .filter_map(|v| v.as_str().map(str::to_string))
                    .collect()
            })
            .unwrap_or_default();

        let mut results = vec![];
        for tool in tools {
            let out = Command::new("which").arg(&tool).output().await;
            let (status, location) = match out {
                Ok(o) if o.status.success() => {
                    let loc = String::from_utf8_lossy(&o.stdout).trim().to_string();
                    ("pass", loc)
                }
                _ => ("warn", String::new()),
            };
            results.push(json!({
                "name": tool,
                "status": status,
                "path": location,
            }));
        }

        Ok(json!({ "tools": results }))
    });

    registry.handler_value("check_pwd", |_input: Value| async move {
        let cwd = std::env::current_dir()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default();

        // Detect project and workspace from path structure: ~/dev/<workspace>/<project>
        let home = std::env::var("HOME").unwrap_or_default();
        let dev_dir = format!("{home}/dev");

        let (workspace, project) = if cwd.starts_with(&dev_dir) {
            let remainder = &cwd[dev_dir.len()..].trim_start_matches('/');
            let parts: Vec<&str> = remainder.splitn(2, '/').collect();
            match parts.as_slice() {
                [ws] => (Some(ws.to_string()), None),
                [ws, proj] => (Some(ws.to_string()), Some(proj.to_string())),
                _ => (None, None),
            }
        } else {
            (None, None)
        };

        Ok(json!({
            "cwd": cwd,
            "workspace": workspace,
            "project": project,
        }))
    });
}
```

- [ ] **Step 5: Run tests**

```bash
cd /Users/joe/dev/hooklings
cargo nextest run -p hooklings --test handlers_env
```

Expected: all 5 tests PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/joe/dev/hooklings
git add crates/hooklings/src/handlers/ crates/hooklings/tests/handlers_env.rs
git commit -m "feat(hooklings): env handlers — detect_shell, check_tools, check_pwd"
git push
```

---

## Task 6: op, ssh, handoff, doob handlers (stubs for op/ssh, sqlite for handoff/doob)

**Files:**
- Create: `crates/hooklings/src/handlers/op.rs`
- Create: `crates/hooklings/src/handlers/ssh.rs`
- Create: `crates/hooklings/src/handlers/handoff.rs`
- Create: `crates/hooklings/src/handlers/doob.rs`
- Create: `crates/hooklings/tests/handlers_sqlite.rs`

- [ ] **Step 1: Write failing tests for handoff and doob handlers**

Create `crates/hooklings/tests/handlers_sqlite.rs`:

```rust
use hooklings::handlers::{handoff, doob};
use cruxx_script::HandlerRegistry;
use rusqlite::Connection;
use serde_json::json;
use tempfile::NamedTempFile;

fn setup_handoff_db() -> NamedTempFile {
    let f = NamedTempFile::new().unwrap();
    let conn = Connection::open(f.path()).unwrap();
    conn.execute_batch(
        "CREATE TABLE items (
            project TEXT NOT NULL,
            id TEXT NOT NULL,
            name TEXT,
            priority TEXT,
            status TEXT,
            completed TEXT,
            updated TEXT,
            PRIMARY KEY (project, id)
        );
        INSERT INTO items VALUES ('proj-a', 'a-1', 'open task', 'P1', 'open', NULL, NULL);
        INSERT INTO items VALUES ('proj-a', 'a-2', 'done task', 'P1', 'done', '2026-01-01', NULL);
        INSERT INTO items VALUES ('proj-b', 'b-1', 'another open', 'P0', 'open', NULL, NULL);",
    )
    .unwrap();
    f
}

fn setup_doob_db() -> NamedTempFile {
    let f = NamedTempFile::new().unwrap();
    let conn = Connection::open(f.path()).unwrap();
    // Minimal todos table — real schema unknown, use a simple approximation
    conn.execute_batch(
        "CREATE TABLE todos (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            status TEXT NOT NULL,
            project TEXT,
            due_date TEXT
        );
        INSERT INTO todos VALUES ('t1', 'pending task', 'pending', 'hooklings', NULL);
        INSERT INTO todos VALUES ('t2', 'done task', 'done', 'hooklings', NULL);",
    )
    .unwrap();
    f
}

#[tokio::test]
async fn handoff_pending_returns_open_items_only() {
    let db = setup_handoff_db();
    let mut reg = HandlerRegistry::new();
    handoff::register(&mut reg, db.path().to_str().unwrap());

    let h = reg.get_handler("handoff::pending").unwrap();
    let result = h(json!({})).await.unwrap();
    let items = result["items"].as_array().unwrap();
    // 2 open items, 1 done — only 2 should appear
    assert_eq!(items.len(), 2);
    for item in items {
        assert_ne!(item["status"], "done");
    }
}

#[tokio::test]
async fn handoff_pending_filter_by_project() {
    let db = setup_handoff_db();
    let mut reg = HandlerRegistry::new();
    handoff::register(&mut reg, db.path().to_str().unwrap());

    let h = reg.get_handler("handoff::pending").unwrap();
    let result = h(json!({"args": {"project": "proj-a"}})).await.unwrap();
    let items = result["items"].as_array().unwrap();
    assert_eq!(items.len(), 1);
    assert_eq!(items[0]["project"], "proj-a");
}

#[tokio::test]
async fn handoff_pending_empty_db_returns_empty_array() {
    let f = NamedTempFile::new().unwrap();
    let conn = Connection::open(f.path()).unwrap();
    conn.execute_batch(
        "CREATE TABLE items (
            project TEXT NOT NULL, id TEXT NOT NULL, name TEXT,
            priority TEXT, status TEXT, completed TEXT, updated TEXT,
            PRIMARY KEY (project, id)
        );",
    )
    .unwrap();
    drop(conn);

    let mut reg = HandlerRegistry::new();
    handoff::register(&mut reg, f.path().to_str().unwrap());
    let h = reg.get_handler("handoff::pending").unwrap();
    let result = h(json!({})).await.unwrap();
    assert_eq!(result["items"].as_array().unwrap().len(), 0);
}

#[tokio::test]
async fn doob_pending_returns_pending_todos_only() {
    let db = setup_doob_db();
    let mut reg = HandlerRegistry::new();
    doob::register(&mut reg, db.path().to_str().unwrap());

    let h = reg.get_handler("doob::pending").unwrap();
    let result = h(json!({})).await.unwrap();
    let todos = result["todos"].as_array().unwrap();
    assert_eq!(todos.len(), 1);
    assert_eq!(todos[0]["status"], "pending");
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd /Users/joe/dev/hooklings
cargo nextest run -p hooklings --test handlers_sqlite
```

Expected: compile error — handler modules not found.

- [ ] **Step 3: Implement `handlers/op.rs`**

Create `crates/hooklings/src/handlers/op.rs`:

```rust
//! `op::auth_check` — verify 1Password CLI is authenticated.

use cruxx_core::prelude::CruxErr;
use cruxx_script::HandlerRegistry;
use serde_json::{Value, json};
use tokio::process::Command;

pub fn register(registry: &mut HandlerRegistry, enabled: bool) {
    registry.handler_value("op::auth_check", move |_input: Value| async move {
        if !enabled {
            return Ok(json!({ "status": "skip", "detail": "disabled in config" }));
        }
        let out = Command::new("op")
            .args(["account", "list", "--format=json"])
            .output()
            .await
            .map_err(|e| CruxErr::step_failed("op::auth_check", format!("spawn failed: {e}")))?;

        if out.status.success() {
            let accounts: Vec<Value> = serde_json::from_slice(&out.stdout).unwrap_or_default();
            Ok(json!({
                "status": "pass",
                "authenticated": true,
                "accounts": accounts.len(),
            }))
        } else {
            Ok(json!({
                "status": "fail",
                "authenticated": false,
                "detail": String::from_utf8_lossy(&out.stderr).trim().to_string(),
            }))
        }
    });
}
```

- [ ] **Step 4: Implement `handlers/ssh.rs`**

Create `crates/hooklings/src/handlers/ssh.rs`:

```rust
//! `ssh::reachable` — check SSH reachability with a 3-second timeout.

use cruxx_core::prelude::CruxErr;
use cruxx_script::HandlerRegistry;
use serde_json::{Value, json};
use tokio::process::Command;

pub fn register(registry: &mut HandlerRegistry, enabled: bool, host: &str) {
    let host = host.to_string();
    registry.handler_value("ssh::reachable", move |_input: Value| {
        let h = host.clone();
        async move {
            if !enabled {
                return Ok(json!({ "status": "skip", "detail": "disabled in config" }));
            }
            let out = Command::new("ssh")
                .args([
                    "-o", "ConnectTimeout=3",
                    "-o", "BatchMode=yes",
                    "-o", "StrictHostKeyChecking=no",
                    &h,
                    "exit",
                ])
                .output()
                .await
                .map_err(|e| {
                    CruxErr::step_failed("ssh::reachable", format!("spawn failed: {e}"))
                })?;

            if out.status.success() {
                Ok(json!({ "status": "pass", "reachable": true, "host": h }))
            } else {
                Ok(json!({
                    "status": "warn",
                    "reachable": false,
                    "host": h,
                    "detail": String::from_utf8_lossy(&out.stderr).trim().to_string(),
                }))
            }
        }
    });
}
```

- [ ] **Step 5: Implement `handlers/handoff.rs`**

Create `crates/hooklings/src/handlers/handoff.rs`:

```rust
//! `handoff::pending` — query open handoff items from the atelier SQLite DB.

use cruxx_core::prelude::CruxErr;
use cruxx_script::HandlerRegistry;
use rusqlite::Connection;
use serde_json::{Value, json};

pub fn register(registry: &mut HandlerRegistry, db_path: &str) {
    let db = db_path.to_string();
    registry.handler_value("handoff::pending", move |input: Value| {
        let db = db.clone();
        async move {
            let project_filter = input
                .get("args")
                .and_then(|a| a.get("project"))
                .and_then(|v| v.as_str())
                .map(str::to_string);

            let conn = Connection::open(&db).map_err(|e| {
                CruxErr::step_failed("handoff::pending", format!("open {db}: {e}"))
            })?;

            let (sql, params): (String, Vec<String>) = if let Some(proj) = project_filter {
                (
                    "SELECT project, id, name, priority, status FROM items \
                     WHERE status <> 'done' AND project = ?1 ORDER BY priority, id"
                        .into(),
                    vec![proj],
                )
            } else {
                (
                    "SELECT project, id, name, priority, status FROM items \
                     WHERE status <> 'done' ORDER BY priority, project, id"
                        .into(),
                    vec![],
                )
            };

            let mut stmt = conn.prepare(&sql).map_err(|e| {
                CruxErr::step_failed("handoff::pending", format!("prepare: {e}"))
            })?;

            let items: Vec<Value> = stmt
                .query_map(
                    rusqlite::params_from_iter(params.iter()),
                    |row| {
                        Ok(json!({
                            "project": row.get::<_, String>(0).unwrap_or_default(),
                            "id": row.get::<_, String>(1).unwrap_or_default(),
                            "name": row.get::<_, Option<String>>(2).unwrap_or(None),
                            "priority": row.get::<_, Option<String>>(3).unwrap_or(None),
                            "status": row.get::<_, String>(4).unwrap_or_default(),
                        }))
                    },
                )
                .map_err(|e| CruxErr::step_failed("handoff::pending", format!("query: {e}")))?
                .filter_map(|r| r.ok())
                .collect();

            Ok(json!({ "items": items, "count": items.len() }))
        }
    });
}
```

- [ ] **Step 6: Implement `handlers/doob.rs`**

Create `crates/hooklings/src/handlers/doob.rs`:

```rust
//! `doob::pending` — query pending todos from the doob SQLite DB.

use cruxx_core::prelude::CruxErr;
use cruxx_script::HandlerRegistry;
use rusqlite::Connection;
use serde_json::{Value, json};

pub fn register(registry: &mut HandlerRegistry, db_path: &str) {
    let db = db_path.to_string();
    registry.handler_value("doob::pending", move |_input: Value| {
        let db = db.clone();
        async move {
            let conn = Connection::open(&db).map_err(|e| {
                CruxErr::step_failed("doob::pending", format!("open {db}: {e}"))
            })?;

            let mut stmt = conn
                .prepare(
                    "SELECT id, title, status, project, due_date FROM todos \
                     WHERE status = 'pending' ORDER BY due_date, id",
                )
                .map_err(|e| {
                    CruxErr::step_failed("doob::pending", format!("prepare: {e}"))
                })?;

            let todos: Vec<Value> = stmt
                .query_map([], |row| {
                    Ok(json!({
                        "id": row.get::<_, String>(0).unwrap_or_default(),
                        "title": row.get::<_, String>(1).unwrap_or_default(),
                        "status": row.get::<_, String>(2).unwrap_or_default(),
                        "project": row.get::<_, Option<String>>(3).unwrap_or(None),
                        "due_date": row.get::<_, Option<String>>(4).unwrap_or(None),
                    }))
                })
                .map_err(|e| CruxErr::step_failed("doob::pending", format!("query: {e}")))?
                .filter_map(|r| r.ok())
                .collect();

            Ok(json!({ "todos": todos, "count": todos.len() }))
        }
    });
}
```

- [ ] **Step 7: Run all handler tests**

```bash
cd /Users/joe/dev/hooklings
cargo nextest run -p hooklings --test handlers_sqlite --test handlers_env
```

Expected: all tests PASS.

- [ ] **Step 8: Commit**

```bash
cd /Users/joe/dev/hooklings
git add crates/hooklings/src/handlers/ crates/hooklings/tests/handlers_sqlite.rs
git commit -m "feat(hooklings): op, ssh, handoff, doob handlers"
git push
```

---

## Task 7: Conformance tests — all handlers registered

**Files:**
- Create: `crates/hooklings/tests/conformance.rs`

- [ ] **Step 1: Write conformance tests**

Create `crates/hooklings/tests/conformance.rs`:

```rust
use cruxx_script::HandlerRegistry;
use hooklings::{config::Config, handlers};

fn full_registry() -> HandlerRegistry {
    let cfg = Config::default();
    let mut reg = HandlerRegistry::new();
    handlers::register_all(&mut reg, &cfg);
    reg
}

#[test]
fn all_hooklings_handlers_registered() {
    let reg = full_registry();
    let expected = [
        "detect_shell",
        "check_tools",
        "check_pwd",
        "op::auth_check",
        "ssh::reachable",
        "handoff::pending",
        "doob::pending",
    ];
    for name in expected {
        assert!(
            reg.get_handler(name).is_some(),
            "handler not registered: {name}"
        );
    }
}

#[test]
fn cruxx_agentic_handlers_also_available() {
    // hooklings pipelines can also use git/shell/fs handlers from cruxx-agentic
    let mut reg = HandlerRegistry::new();
    cruxx_agentic::register_all(&mut reg);
    let cfg = Config::default();
    handlers::register_all(&mut reg, &cfg);

    for name in &["git::status", "git::log", "sqlite::exec"] {
        assert!(
            reg.get_handler(name).is_some(),
            "cruxx-agentic handler missing: {name}"
        );
    }
}
```

- [ ] **Step 2: Run conformance tests**

```bash
cd /Users/joe/dev/hooklings
cargo nextest run -p hooklings --test conformance
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/joe/dev/hooklings
git add crates/hooklings/tests/conformance.rs
git commit -m "test(hooklings): conformance tests for handler registry"
git push
```

---

## Task 8: Wire `main.rs` CLI subcommands

**Files:**
- Modify: `crates/hooklings/src/main.rs`

- [ ] **Step 1: Implement full CLI**

Replace `crates/hooklings/src/main.rs`:

```rust
pub mod config;
pub mod emit;
pub mod handlers;

use clap::{Parser, Subcommand, ValueEnum};
use cruxx_agentic::register_all as register_agentic;
use cruxx_script::{HandlerRegistry, PipelineRunner};
use emit::{CheckResult, Emitter, Status};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "hooklings", about = "YAML-driven developer preflight checks")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Run all enabled checks in the configured pipeline
    Preflight {
        #[arg(long, value_enum, default_value = "both")]
        emit: EmitMode,
        /// Override pipeline file
        #[arg(long)]
        pipeline: Option<PathBuf>,
    },
    /// Run a single named check
    Check {
        name: String,
    },
    /// Print the merged effective config
    Config {
        #[command(subcommand)]
        action: ConfigAction,
    },
}

#[derive(Subcommand)]
enum ConfigAction {
    Show,
}

#[derive(ValueEnum, Clone)]
enum EmitMode {
    Json,
    Table,
    Both,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    let cfg = config::Config::load();

    match cli.command {
        Command::Preflight { emit, pipeline } => {
            let mut registry = HandlerRegistry::new();
            register_agentic(&mut registry);
            handlers::register_all(&mut registry, &cfg);

            let pipeline_path = pipeline
                .unwrap_or_else(|| PathBuf::from(&cfg.pipeline.default));

            // Load and run pipeline
            let pipeline_yaml = std::fs::read_to_string(&pipeline_path)
                .map_err(|e| anyhow::anyhow!("cannot read pipeline {}: {e}", pipeline_path.display()))?;

            let runner = PipelineRunner::new(registry);
            let trace = runner.run_yaml(&pipeline_yaml).await
                .map_err(|e| anyhow::anyhow!("pipeline failed: {e}"))?;

            // Convert trace steps to CheckResults
            let results: Vec<CheckResult> = trace
                .steps()
                .iter()
                .map(|step| {
                    let output = step.output_json();
                    let status = if step.succeeded() {
                        match output.get("status").and_then(|s| s.as_str()) {
                            Some("warn") => Status::Warn,
                            Some("skip") => Status::Skip,
                            Some("fail") => Status::Fail,
                            _ => Status::Pass,
                        }
                    } else {
                        Status::Error
                    };
                    CheckResult {
                        name: step.name().to_string(),
                        status,
                        detail: output
                            .get("detail")
                            .and_then(|d| d.as_str())
                            .unwrap_or("")
                            .to_string(),
                        data: Some(output),
                    }
                })
                .collect();

            let emitter = Emitter::new("preflight".into());

            match emit {
                EmitMode::Json | EmitMode::Both => {
                    let json_path = PathBuf::from(&cfg.emit.json_path);
                    emitter.write_json(&results, &json_path)?;
                }
                _ => {}
            }
            match emit {
                EmitMode::Table | EmitMode::Both => {
                    print!("{}", Emitter::markdown_table(&results));
                }
                _ => {}
            }
        }

        Command::Check { name } => {
            let mut registry = HandlerRegistry::new();
            register_agentic(&mut registry);
            handlers::register_all(&mut registry, &cfg);

            let handler = registry
                .get_handler(&name)
                .ok_or_else(|| anyhow::anyhow!("unknown handler: {name}"))?;

            let result = handler(serde_json::json!({})).await
                .map_err(|e| anyhow::anyhow!("handler error: {e}"))?;
            println!("{}", serde_json::to_string_pretty(&result)?);
        }

        Command::Config { action: ConfigAction::Show } => {
            let toml = toml::to_string_pretty(&cfg)?;
            println!("{toml}");
        }
    }

    Ok(())
}
```

- [ ] **Step 2: Add `anyhow` to dependencies**

In `crates/hooklings/Cargo.toml` `[dependencies]`:

```toml
anyhow = "1"
```

- [ ] **Step 3: Verify it compiles**

```bash
cd /Users/joe/dev/hooklings
cargo build
```

Expected: compiles. (Pipeline runner API may need adjustment based on actual `cruxx-script` API
— see `crates/cruxx-script/src/runner.rs` for exact method names and adapt accordingly.)

- [ ] **Step 4: Commit**

```bash
cd /Users/joe/dev/hooklings
git add crates/hooklings/src/main.rs crates/hooklings/Cargo.toml
git commit -m "feat(hooklings): wire CLI subcommands — preflight, check, config show"
git push
```

---

## Task 9: Default pipeline + README

**Files:**
- Create: `hooklings/pipelines/default.crux`
- Create: `hooklings/README.md`

- [ ] **Step 1: Create default pipeline**

Create `pipelines/default.crux`:

```yaml
pipeline: preflight
steps:
  - join_all: environment
    arms:
      - detect_shell
      - step: check_tools
        args:
          tools:
            - nu
            - just
            - cargo
            - op
            - devkit
            - gkg
            - doob
            - handoff-db
            - handoff-detect
      - check_pwd

  - join_all: git
    arms:
      - git::status
      - step: git::log
        args: { n: 5 }

  - step: op::auth_check

  - step: ssh::reachable

  - step: handoff::pending

  - step: doob::pending
```

- [ ] **Step 2: Create README**

Create `README.md`:

```markdown
# hooklings

YAML-driven developer preflight checks via [crux](https://github.com/89jobrien/crux) pipelines.

## Install

```bash
cargo install --path crates/hooklings
```

## Usage

```bash
hooklings preflight            # run all checks, emit JSON + markdown table
hooklings preflight --emit table   # markdown table only
hooklings check detect_shell   # run a single check
hooklings config show          # print merged config
```

## Config

Global: `~/.config/hooklings/hooklings.toml`
Project: `.hooklings.toml` in repo root (merged over global)

```toml
[checks.op_auth]
enabled = true

[checks.ssh_reachable]
enabled = true
host = "minibox"

[checks.doob_pending]
db = "~/.local/share/doob/doob.db"
```

## Pipeline

Checks are defined as `.crux` YAML pipelines. The default pipeline runs at:
`~/.config/hooklings/default.crux`

Override per-project:

```toml
[pipeline]
default = ".hooklings/ci.crux"
```

## atelier Integration

atelier's SessionStart hook calls `hooklings preflight --emit both` when hooklings is on PATH.
```

- [ ] **Step 3: Commit**

```bash
cd /Users/joe/dev/hooklings
git add pipelines/ README.md
git commit -m "docs: default pipeline and README"
git push
```

---

## Task 10: Fuzz targets

**Files:**
- Create: `hooklings/fuzz/Cargo.toml`
- Create: `hooklings/fuzz/fuzz_targets/config_parse.rs`
- Create: `hooklings/fuzz/fuzz_targets/emit_table.rs`

- [ ] **Step 1: Bootstrap fuzz crate**

```bash
cd /Users/joe/dev/hooklings
cargo fuzz init
```

- [ ] **Step 2: Add fuzz targets to `fuzz/Cargo.toml`**

Ensure `fuzz/Cargo.toml` contains:

```toml
[dependencies]
hooklings = { path = "../crates/hooklings" }
libfuzzer-sys = "0.4"

[[bin]]
name = "config_parse"
path = "fuzz_targets/config_parse.rs"
test = false
doc = false

[[bin]]
name = "emit_table"
path = "fuzz_targets/emit_table.rs"
test = false
doc = false
```

- [ ] **Step 3: Write config fuzz target**

Create `fuzz/fuzz_targets/config_parse.rs`:

```rust
#![no_main]
use hooklings::config::Config;
use libfuzzer_sys::fuzz_target;
use std::io::Write;
use tempfile::NamedTempFile;

fuzz_target!(|data: &[u8]| {
    let Ok(s) = std::str::from_utf8(data) else { return };
    let mut f = match NamedTempFile::new() {
        Ok(f) => f,
        Err(_) => return,
    };
    let _ = f.write_all(s.as_bytes());
    // Must not panic regardless of TOML content
    let _ = Config::load_from_file(f.path());
});
```

- [ ] **Step 4: Write emit fuzz target**

Create `fuzz/fuzz_targets/emit_table.rs`:

```rust
#![no_main]
use hooklings::emit::{CheckResult, Emitter, Status};
use libfuzzer_sys::fuzz_target;

fuzz_target!(|data: &[u8]| {
    let Ok(s) = std::str::from_utf8(data) else { return };
    // Treat input as pipe-delimited name|detail pairs, one per line
    let results: Vec<CheckResult> = s
        .lines()
        .take(32)
        .map(|line| {
            let mut parts = line.splitn(2, '|');
            CheckResult {
                name: parts.next().unwrap_or("x").chars().take(64).collect(),
                status: Status::Pass,
                detail: parts.next().unwrap_or("").chars().take(128).collect(),
                data: None,
            }
        })
        .collect();
    // Must not panic
    let _ = Emitter::markdown_table(&results);
});
```

- [ ] **Step 5: Verify fuzz targets compile**

```bash
cd /Users/joe/dev/hooklings
cargo fuzz build config_parse
cargo fuzz build emit_table
```

Expected: both compile without errors.

- [ ] **Step 6: Smoke run each fuzz target**

```bash
cargo fuzz run config_parse -- -max_total_time=10
cargo fuzz run emit_table -- -max_total_time=10
```

Expected: no panics or crashes.

- [ ] **Step 7: Commit**

```bash
cd /Users/joe/dev/hooklings
git add fuzz/
git commit -m "test(hooklings): fuzz targets for config parsing and emit table"
git push
```

---

## Task 11: Clippy + final gate

- [ ] **Step 1: Run clippy**

```bash
cd /Users/joe/dev/hooklings
cargo clippy --all-targets -- -D warnings
```

Fix any warnings.

- [ ] **Step 2: Run full test suite**

```bash
cargo nextest run
```

Expected: all tests PASS.

- [ ] **Step 3: Commit any clippy fixes**

```bash
git add -A
git commit -m "fix(hooklings): clippy clean"
git push
```

---

## Task 12: Update atelier SessionStart hook

**Files:**
- Modify: `~/.claude/hooks/nu/session/session-start.nu`

- [ ] **Step 1: Update the hook**

Replace the content of `/Users/joe/.claude/hooks/nu/session/session-start.nu`:

```nu
#!/usr/bin/env nu
# session-start.nu — SessionStart hook
# Runs hooklings preflight when available; falls back to navigator hint.

def main [] {
    let cwd = $env.PWD
    let dev_dir = $env.HOME | path join "dev"

    if (which hooklings | is-empty) {
        # Fallback: emit navigator hint only
        if ($cwd | str starts-with $"($dev_dir)/") {
            let remainder = $cwd | str substring (($dev_dir | str length) + 1)..
            let project = $remainder | split row "/" | first
            if $project != "" {
                print $"Navigator available: run /navigate ($project) for an architecture briefing."
            }
        }
    } else {
        hooklings preflight --emit both
    }

    # Run rtk learn in the background
    if not (which rtk | is-empty) {
        job spawn { ^rtk learn --quiet }
    }
}
```

- [ ] **Step 2: Test the hook manually**

```bash
nu /Users/joe/.claude/hooks/nu/session/session-start.nu
```

Expected: either hooklings output (if installed) or the navigator hint.

- [ ] **Step 3: Commit to atelier**

```bash
git -C /Users/joe/dev/atelier add .
git -C /Users/joe/dev/atelier commit -m "feat(hooks): update session-start to call hooklings preflight with fallback"
```

---

## Self-Review Checklist (Spec Coverage)

- [x] Standalone repo `89jobrien/hooklings` — Task 1
- [x] Subcommands: `preflight`, `check`, `config show` — Task 8
- [x] Layered TOML config (global + project) — Task 2
- [x] Config merge logic — Task 2 + Task 3 property tests
- [x] `detect_shell` handler — Task 5
- [x] `check_tools` handler — Task 5
- [x] `check_pwd` handler — Task 5
- [x] `op::auth_check` handler (enabled flag) — Task 6
- [x] `ssh::reachable` handler (enabled flag, configurable host) — Task 6
- [x] `handoff::pending` handler (SQLite, filter by project) — Task 6
- [x] `doob::pending` handler (SQLite, configurable db path) — Task 6
- [x] JSON emit to disk — Task 4
- [x] Markdown table to stdout — Task 4
- [x] Default `.crux` pipeline — Task 9
- [x] `--emit json|table|both` flag — Task 8
- [x] atelier SessionStart hook update — Task 12
- [x] Conformance tests (all handlers registered) — Task 7
- [x] Property tests (config) — Task 3
- [x] Fuzz targets (config parse, emit table) — Task 10
- [x] Clippy clean — Task 11
- [x] README — Task 9

**Note on main.rs Task 8:** The `PipelineRunner` API (`run_yaml`, `steps()`, `output_json()`,
`succeeded()`, `name()`) must be verified against the actual `cruxx-script` runner.rs before
implementing. Read `crates/cruxx-script/src/runner.rs` and adapt method names to match.
