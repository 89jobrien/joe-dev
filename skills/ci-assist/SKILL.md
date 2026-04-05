---
name: ci-assist
description: This skill should be used when the user asks to "edit workflow", "fix CI",
  "check cross-compile", "verify binary", "update github actions", "debug CI failure",
  "verify target triple", or needs help with CI/CD workflow files or cross-compilation.
---

# ci-assist

Edit GitHub Actions workflow files, verify cross-compiled binary architecture, and
diagnose CI failures.

See `references/target-triples.md` for target triple reference, common CI failure patterns,
and the heredoc approach for editing workflow files.

## CI Diagnostics

```bash
gh run list --limit 5
gh run view <run-id> --log-failed
gh run watch <run-id>
```

## Diagnosing a Failed CI Run

1. `gh run list --limit 5` — find the failing run ID
2. `gh run view <id> --log-failed` — see only failing steps
3. Read the failing step's log for the root cause
4. Check: missing env vars, wrong target triple, denied `op://` refs in CI context

## Reference Repo

Canonical CI patterns live in `~/dev/minibox/.github/workflows/`.
