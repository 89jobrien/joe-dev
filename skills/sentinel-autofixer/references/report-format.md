# Sentinel Report Format Reference

## Report Structure

A sentinel code review report contains three severity sections. All sections may not be
present in every report — only emit sections that have findings.

```
## Blocking

[B1] src/handler.rs:42 — Missing error propagation: `unwrap()` on fallible op
     Severity: blocking
     Fix: replace with `?` operator or explicit `match`

## Suggestions

[S1] src/handler.rs:88 — Needless clone: `x.clone()` passed to function taking &str
     Severity: suggestion
     Fix: pass `&x` instead of `x.clone()`

[S2] src/lib.rs:14 — Unused import: `use std::collections::BTreeMap`
     Severity: suggestion
     Fix: remove import

## Observations

[O1] src/handler.rs — High cyclomatic complexity in `process_request` (score: 12)
     No immediate action required. Consider refactoring if function grows.
```

## Severity Taxonomy

| Severity | Auto-apply? | Requires user ack? | Description |
|---|---|---|---|
| **Blocking** | Never | Yes, before proceeding | Correctness, safety, or security issue |
| **Suggestion** | Yes (with dry-run) | No (but show diff) | Style, lint, dead code, obvious cleanup |
| **Observation** | No | No | Informational — complexity, patterns, FYI |

## Parsing a Sentinel Report

When reading a report from the conversation:

1. Scan for the `## Blocking` section — if present, surface all blocking items first
2. Extract `## Suggestions` items by code location (file:line)
3. Ignore `## Observations` unless the user asks about them

Each item has a reference tag (`[B1]`, `[S1]`, etc.) used for selective application
(`yes/no/select` workflow).

## Dry-Run Diff Format

Present proposed suggestion-level changes in this format before applying:

```
SUGGESTION S1 — src/handler.rs:88
  - let result = process(x.clone());
  + let result = process(&x);

SUGGESTION S2 — src/lib.rs:14
  - use std::collections::BTreeMap;
  + (removed)
```

Show all suggestions as a batch before asking for approval. Do not apply one at a time.

## Selective Application

When the user responds "select" to the apply prompt:

1. List all suggestions with their `[S#]` tags and one-line descriptions
2. Ask: "Which suggestions to apply? (e.g. S1 S3 or 'all')"
3. Apply only the confirmed set
4. Run `cargo check --workspace` after applying
5. Commit the applied subset: `git commit -m "fix: apply sentinel suggestions (S1, S3)"`

## Report Sources

Sentinel reports may come from:

1. **Current conversation** — user pastes or the sentinel agent outputs directly
2. **File** — user references a saved report file (read with Read tool)
3. **Agent output** — sentinel agent was just invoked; use its output directly

When the source is unclear, ask: "Is there a sentinel report in this conversation, or
should I invoke the sentinel agent first?"

## Post-Apply Verification

After applying all suggestions and committing:

1. Run `cargo-gate` to confirm the workspace still builds cleanly
2. If any stage fails, check whether the applied fix introduced the regression
3. If yes: revert the specific suggestion and note it as incompatible
4. Report the final state:

```
Applied: S1, S2, S3
Committed: fix: apply sentinel suggestions (abc1234)
Gate: PASS

Skipped (blocking — needs manual review):
  B1 src/handler.rs:42 — Missing error propagation
```
