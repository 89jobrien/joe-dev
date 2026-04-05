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
| cargo-gate | "gatecargo", "run gates", "validate rust" |
| sentinel-autofixer | "autofix", "apply review fixes", "fix sentinel suggestions" |
| hook-diagnostics | "failhook", "show hook status", "what hooks ran" |
| git-guard | "safe to commit", "check merge strategy", "commit safely" |
| ci-assist | "edit workflow", "fix CI", "check cross-compile", "verify binary" |
| project-pulse | "end session", "capture state", "session summary" |
| handoff | "write handoff", "end of session", "capture handoff" |
| handon | "handon", "start session", "what's outstanding" |

## Agents

> Currently delegates agent logic to devkit and likely always will

| Agent | Purpose |
|-------|---------|
| sentinel | Structured code review |
| forge | Dev companion — design, debug, refactor |
| herald | Cross-repo synthesis → Obsidian |
| conductor | devloop → doob → devkit pipeline |
| oxidizer | Rust-specific review: clippy, unsafe, edition 2024 |

## Notes

- `cargo-gate` runs `cargo xtask pre-commit` first — the xtask gate always
  takes priority.
- [joe-secrets](https://github.com/89jobrien/joe-secrets) must also be installed for the session-start op-resolver +
  handon chain.
- All agents are thin wrappers; devkit must be installed and accessible.
