# xtask Patterns Reference

## What `cargo xtask pre-commit` Does

The `pre-commit` xtask is the canonical gate for Rust workspaces. It runs in order:

1. `cargo fmt --check` — format check (no modification)
2. `cargo clippy -- -D warnings` — promote all warnings to errors
3. `cargo build --release` — verify release build succeeds

It does NOT run `cargo test` by default. Tests must be added as a separate step or via a
`cargo xtask test` recipe if one exists.

## Detecting xtask Availability

```bash
# Check for xtask crate in workspace
ls xtask/src/main.rs 2>/dev/null && echo "xtask present" || echo "no xtask"

# Check for pre-commit recipe specifically
cargo xtask --help 2>/dev/null | grep pre-commit
```

If xtask is present but has no `pre-commit` recipe, fall back to manual stage sequence.

## Fallback Stage Sequence (no xtask)

Run stages in this order, stopping on first failure:

```bash
cargo fmt --check             # stage: fmt
cargo clippy -- -D warnings   # stage: clippy
cargo test                    # stage: test
cargo check --workspace       # stage: check
```

Report each stage pass/fail individually — do not aggregate.

## Workspace-Level vs Crate-Level Gates

Always run workspace-level gates (`--workspace` flag) when in a multi-crate workspace:

```bash
cargo clippy --workspace -- -D warnings
cargo check --workspace
cargo test --workspace
```

Run crate-level gates only when the user explicitly scopes to one crate:

```bash
cargo clippy -p <crate-name> -- -D warnings
```

## Clippy Fix Workflow

Determine if fixes are suggestion-level before applying:

```bash
# Dry-run: what would clippy --fix change?
cargo clippy --fix --allow-staged --dry-run 2>&1 | head -40
```

Apply only after user confirmation:

```bash
cargo clippy --fix --allow-staged
git diff   # show what changed
```

Never apply clippy fixes to files the user hasn't touched in this session without confirming.

## Common Failure Patterns

| Symptom | Stage | Fix |
|---------|-------|-----|
| `error[E0...]: expected...` | check/build | Fix the type/borrow error |
| `warning: ... [-D warnings]` | clippy | Fix or `#[allow(clippy::...)]` with justification |
| `left behind by rustfmt` | fmt | `cargo fmt` then re-run gate |
| `test ... FAILED` | test | Investigate failing test — do not skip |
| `xtask: No such subcommand` | xtask | Fall back to manual stage sequence |

## Minibox xtask Profile

In `~/dev/minibox`, `cargo xtask pre-commit` is defined to run:
- fmt-check
- clippy (`--workspace -D warnings`)
- release build (`--target x86_64-unknown-linux-musl` for VPS target)

It does NOT cross-compile by default — cross-compile is gated in CI only.

## Reporting Format

Always surface stage results in this structure after gate completion:

```
STAGE     RESULT   NOTES
fmt       PASS
clippy    FAIL     3 warnings promoted to errors (see below)
test      SKIP     (not run by xtask)
check     PASS

clippy errors:
  src/handler.rs:42  warning: unused variable `x` [-D unused_variables]
  src/handler.rs:57  warning: needless_borrow [-D clippy::needless_borrow]
```

Show the first 20 lines of error output for any failing stage.
