---
name: ai-review
description:
  This skill should be used when the user asks to "review this diff", "ai review",
  "security review my changes", "review before push", "check my code for issues", or
  wants an LLM-based security and correctness review of uncommitted or unpushed changes.
model: sonnet
effort: high
allowed-tools:
  - Bash
  - Read
  - Glob
  - Write
---

# ai-review

Run an LLM-based security and correctness review of the current diff vs a base branch.
Surfaces findings grouped by severity. Writes a markdown report to `.ai-logs/`.

## Workflow

### 1. Get the diff

Default base branch is `main`. Accept an explicit base if provided.

```bash
git diff main...HEAD
```

If `HEAD` is already on `main` or there is no diff, fall back to staged changes:

```bash
git diff --staged
```

If both are empty: inform the user there is nothing to review and stop.

### 2. Get the current short SHA

```bash
git rev-parse --short HEAD
```

Use this as `<sha>` in the report filename.

### 3. Send to LLM for review

Compose a prompt with the following structure:

```
You are a senior engineer performing a security and correctness review of a code diff.

Review the diff below and produce a structured report with findings grouped by severity:
- CRITICAL: security vulnerabilities, data loss, auth bypasses, path traversal, injection
- HIGH: correctness bugs, panics in production paths, missing error handling, race conditions
- MEDIUM: performance issues, missing cleanup, unclear invariants, incomplete implementations
- LOW: style issues, dead code, missing docs, minor inefficiencies

For each finding:
- Severity: CRITICAL | HIGH | MEDIUM | LOW
- File + line reference (if determinable from diff)
- Finding: one-sentence description
- Detail: 2-3 sentences of explanation
- Recommendation: concrete fix

If no findings at a severity level, omit that section.
End with a one-paragraph summary verdict.

DIFF:
<diff content>
```

### 4. Write report

Ensure `.ai-logs/` directory exists, then write the report:

```
.ai-logs/ai-review-<sha>.md
```

Report format:

```markdown
# AI Review — <sha>

**Base:** main  **Date:** <date>

## CRITICAL

### <Finding title>
**File:** `path/to/file.rs:42`
**Finding:** ...
**Detail:** ...
**Recommendation:** ...

## HIGH
...

## Summary

<verdict paragraph>
```

If the directory does not exist, create it before writing.

### 5. Surface results

Print the findings summary to the terminal grouped by severity with counts:

```
SEVERITY   COUNT
CRITICAL   0
HIGH       2
MEDIUM     3
LOW        1

Report: .ai-logs/ai-review-<sha>.md
```

If CRITICAL or HIGH findings exist, highlight them inline before the summary table.

## Base Branch Override

If the user specifies a different base (e.g. "review against `next`"), use that ref
instead of `main` for the diff command.

## Pairing with cargo-gate

Run `cargo-gate` before `ai-review` on Rust projects to ensure the diff is clean first.
The review is most useful on a diff that already compiles and passes clippy.
