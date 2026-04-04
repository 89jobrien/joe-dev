# joe-dev

Personal dev workflow plugin — Rust gates, code review, CI, git safety,
multi-repo pulse.

## Installation

Install both plugins for full session-start experience:

```bash
claude --plugin-dir ~/.claude/plugins/joe-dev
claude --plugin-dir ~/.claude/plugins/joe-secrets
```

## Skills

| Skill | Trigger Phrases |
|-------|----------------|
| cargo-gate | "run gates", "validate rust", "pre-commit check" |
| sentinel-autofixer | "apply review fixes", "fix sentinel suggestions", "auto-fix review" |
| hook-diagnostics | "show hook status", "hook failures", "what hooks ran" |
| git-guard | "safe to commit", "check merge strategy", "commit safely" |
| ci-assist | "edit workflow", "fix CI", "check cross-compile", "verify binary" |
| project-pulse | "end session", "capture state", "session summary" |
| handoff | "write handoff", "end of session", "capture handoff" |
| handon | "start session", "orient to work", "what's outstanding" |

## Agents

| Agent | Purpose |
|-------|---------|
| sentinel | Structured code review (delegates to devkit) |
| forge | Dev companion — design, debug, refactor (delegates to devkit) |
| herald | Cross-repo synthesis → Obsidian (delegates to devkit) |
| conductor | devloop → doob → devkit pipeline (delegates to devkit) |
| oxidizer | Rust-specific review: clippy, unsafe, edition 2024 (delegates to devkit) |

## Notes

- `cargo-gate` runs `cargo xtask pre-commit` first — the xtask gate always
  takes priority.
- `joe-secrets` must also be installed for the session-start op-resolver +
  handon chain.
- All agents are thin wrappers; devkit must be installed and accessible.
