---
name: cargo-gate
description:
  This skill should be used when the user asks to "run gates", "validate rust",
  "pre-commit check", "run cargo validation", "check before committing", or wants to run
  the full Rust validation suite before a commit.
model: sonnet
effort: high
allowed-tools:
  - Bash
  - Read
  - Glob
---

# cargo-gate

Run the full Rust validation suite before committing. The `cargo xtask pre-commit` gate
always takes priority — this skill wraps it and adds structured pass/fail reporting.

## Validation Order

Always run stages in this order:

1. `cargo xtask pre-commit` — runs fmt-check + clippy + release build (canonical gate, always first)
2. Report results per stage: fmt / clippy / test / check
3. If xtask fails, surface the failing stage explicitly before stopping

## Running the Gate

```bash
cargo xtask pre-commit
```

If `cargo xtask pre-commit` is not available (no xtask in workspace), fall back to:

```bash
cargo fmt --check && cargo clippy -- -D warnings && cargo test && cargo check --workspace
```

Never skip `cargo xtask pre-commit` when it exists. It is the canonical gate.

## Reporting

After running, present a structured summary:

```
STAGE      RESULT
fmt        PASS
clippy     PASS  (or: FAIL — 3 warnings promoted to errors)
test       PASS  (or: FAIL — 2 tests failed)
check      PASS
```

If any stage fails, show the first 20 lines of error output for that stage.

## Clippy Auto-Fix

When clippy produces suggestion-level warnings (not errors), offer:

> "clippy has N suggestions. Apply auto-fixes? (yes/no/show-diff)"

If yes: run `cargo clippy --fix --allow-staged`. Always show the diff before applying.
Never auto-apply without confirmation.

## Integration with xtask

`cargo xtask pre-commit` on minibox runs: fmt-check → clippy → release build.
It does NOT run `cargo test` by default. Add test stage separately if needed.

## When to Use

Invoke before every commit on Rust projects. Pairs with `git-guard` — run cargo-gate
first, then git-guard to confirm merge strategy before committing.

## Additional Resources

- **`references/xtask-patterns.md`** — xtask detection, workspace vs crate gates, fallback
  stage sequence, clippy fix workflow, common failure patterns, minibox xtask profile
