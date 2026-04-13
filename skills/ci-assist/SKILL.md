---
name: ci-assist
description:
  This skill should be used when the user asks to "edit workflow", "fix CI",
  "check cross-compile", "verify binary", "update github actions", "debug CI failure",
  "verify target triple", or needs help with CI/CD workflow files or cross-compilation.
model: sonnet
effort: medium
allowed-tools:
  - Read
  - Bash
  - Glob
---

# ci-assist

Edit GitHub Actions workflow files, verify cross-compiled binary architecture, and
diagnose CI failures.

See `references/target-triples.md` for target triple reference, common CI failure patterns,
and the heredoc approach for editing workflow files.

## Diagnosing a Failed CI Run

1. `gh run list --limit 5` — find the failing run ID
2. `gh run view <id> --log-failed` — see only failing steps
3. Read the failing step's log for the root cause
4. Check in order: missing env vars → wrong target triple → denied `op://` refs → clippy -D warnings

```bash
gh run list --limit 5
gh run view <run-id> --log-failed
gh run watch <run-id>
gh workflow list
gh workflow run <name>
```

## Editing Workflow Files

The `Edit` and `Write` tools are blocked for `.github/workflows/*.yml` by a security hook.
Always use a Bash heredoc:

```bash
cat > .github/workflows/ci.yml << 'EOF'
name: CI
on: [push, pull_request]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: cargo test --workspace
EOF
```

Reference canonical patterns from `~/dev/minibox/.github/workflows/` before writing any
new workflow. Do not guess — read the reference repo first.

## Cross-Compilation Verification

Always run `file <binary>` after a cross-compiled build to verify architecture before deploying:

```bash
cargo build --release --target x86_64-unknown-linux-musl
file target/x86_64-unknown-linux-musl/release/<binary>
# Expected: ELF 64-bit LSB executable, x86-64, statically linked
```

Never rsync a binary to the VPS before confirming it is `x86_64` + statically linked.

## CI Secret Injection

`op://` URIs are not resolved in GitHub Actions by default. Secrets must be injected via
the 1Password GitHub Actions integration or passed explicitly as `${{ secrets.NAME }}`.

If `op://` literals appear in CI logs: the secret was not injected — the raw URI leaked.
Fix by wrapping with `op run --` or using the 1Password GitHub Actions provider.

## Common Root Causes (check in this order)

1. Missing env var / unresolved `op://` ref
2. Wrong target triple (macOS binary deployed to Linux VPS)
3. Clippy warnings promoted to errors locally that weren't caught
4. Workflow YAML syntax error (validate with `actionlint` if available)
5. Pinned action version no longer exists or was force-pushed

## Reference Repo

Canonical CI patterns live in `~/dev/minibox/.github/workflows/`. Read it before writing
or editing any workflow file.

## Additional Resources

- **`references/target-triples.md`** — target triple table, `file` output verification,
  common CI failure patterns, workflow editing heredoc approach, diagnostics commands
