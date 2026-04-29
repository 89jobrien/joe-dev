---
name: commit-msg
description:
  This skill should be used when the user asks to "generate commit message",
  "write a commit msg", "ai commit", "generate a conventional commit", "write my commit",
  or wants an LLM to draft a commit message from the staged diff.
model: haiku
effort: low
allowed-tools:
  - Bash
  - Read
---

# commit-msg

Generate a conventional commit message from the staged diff using an LLM. Present for
confirmation before committing. Never commits without explicit user approval.

## Workflow

### 1. Get the staged diff

```bash
git diff --staged
```

If the staged diff is empty: inform the user nothing is staged and stop. Suggest
`git add <files>` first.

### 2. Get recent commit history for style context

```bash
git log --oneline -5
```

Use this to match the project's existing commit message conventions (prefix style,
scope usage, verbosity).

### 3. Send to LLM

Compose a prompt:

```
You are an expert at writing conventional commit messages.

Based on the staged diff and recent commit history below, generate a commit message
following the Conventional Commits specification:

  <type>[optional scope]: <description>

  [optional body]

Rules:
- type: feat | fix | refactor | chore | docs | test | perf | ci | build
- description: lowercase, imperative mood, no period, ≤72 chars
- scope: optional, lowercase, matches the subsystem changed (e.g. handler, protocol, cli)
- body: optional, wrap at 100 chars, explain WHY not WHAT, use bullet points for multiple changes
- Do NOT add a footer unless there is a breaking change or issue reference
- Output ONLY the commit message — no preamble, no explanation

RECENT COMMITS (for style context):
<git log output>

STAGED DIFF:
<git diff --staged output>
```

### 4. Present for confirmation

Display the generated message clearly:

```
Generated commit message:

  feat(handler): add streaming output for ephemeral containers

  Wires ContainerOutput protocol messages through the channel-based dispatch
  path so ephemeral run output streams to the CLI in real time.

Commit with this message? [y/N/edit]
```

Options:
- `y` — commit immediately with the message
- `N` (default) — abort, user will commit manually
- `edit` — open the message in `$EDITOR` for modification, then confirm again

### 5. Commit

If the user confirms, run:

```bash
git commit -m "$(cat <<'EOF'
<message>
EOF
)"
```

Never use `--no-verify`. Always let pre-commit hooks run.

If commit fails with `1Password: agent returned an error`: instruct user to unlock
1Password and retry. No config change needed.

## Pairing

Run `cargo-gate` before `commit-msg` on Rust projects to ensure the commit is clean.
Optionally run `ai-review` first if the diff involves security-sensitive paths.
