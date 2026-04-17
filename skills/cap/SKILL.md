---
name: cap
description: >
  Use when the user runs "/cap" or asks to "commit and push", "cap it", "ship it", "save progress".
  Scans for secrets, generates a commit message, stages appropriate files, commits, and pushes.
argument-hint: "[optional commit message hint]"
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
---

# cap — Scan, Commit, Push

Fast commit workflow: devsec scan → message generation → selective staging → commit → push.

## Step 1 — Status Snapshot

```bash
git status --short
git diff --stat HEAD
```

Identify: new files, modified files, deleted files, untracked files.

## Step 2 — Devsec Scan

Run gitleaks on staged + unstaged changes:

```bash
gitleaks detect --source . --no-git 2>/dev/null \
  || gitleaks detect --source . 2>/dev/null \
  || echo "gitleaks not found — skipping"
```

If gitleaks is unavailable, fall back to a quick pattern grep on changed files:

```bash
git diff HEAD -- . | grep -iE \
  '(api[_-]?key|secret|password|token|bearer|private[_-]?key)\s*[:=]\s*["\x27]?[A-Za-z0-9+/]{16,}'
```

**If any real secrets are found: STOP. Report findings. Do not commit.**

False positives (test fixtures, variable names, localhost IPs) — note them and continue.

## Step 3 — Decide What to Stage

**Stage:**
- Source files, config, docs, skills, markdown
- Files explicitly relevant to the work done

**Do NOT stage:**
- `.env`, `.env.*`, `*.key`, `*.pem`, `*.p12`, `*.pfx`
- `*secret*`, `*credential*`, `*token*` (unless clearly non-sensitive, e.g. a test fixture file)
- Lock files if they are the only change (unless asked)
- Generated/compiled artifacts (`target/`, `dist/`, `*.wasm`) unless explicitly requested
- State files: `.ctx/HANDOFF.*.state.yaml`

Stage appropriate files:

```bash
git add <files>    # specific files only — never `git add -A` blindly
```

## Step 4 — Generate Commit Message

Read the diff and produce a conventional commit message:

```
<type>(<scope>): <what changed and why>
```

Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `ci`

Rules:
- One line, ≤72 chars
- Past tense ("add", "fix", "remove") — not "adding", "fixed"
- Scope = affected component/skill/crate (omit if unclear)
- If user passed an argument hint, use it to inform the message

## Step 5 — Commit

```bash
git commit -m "<message>"
```

Never use `--no-verify`. Let hooks run. If a hook fails, report it — do not retry blindly.

## Step 6 — Push

```bash
git push
```

If the branch has no upstream, set it:

```bash
git push -u origin $(git branch --show-current)
```

## Step 7 — Report

One-line summary:

```
capped: <N> files | <commit hash> | <branch> -> origin
```

If anything was skipped (secrets found, files excluded), note it on the next line.
