---
name: git-guard
description: This skill should be used when the user asks to "safe to commit",
  "check merge strategy", "commit safely", "is it safe to merge", "should I rebase
  or merge", or wants to verify the git strategy is safe before committing or merging.
model: haiku
effort: low
allowed-tools:
  - Bash
  - Read
---

# git-guard

Verify git merge/rebase strategy is safe before committing. Detect unsafe rebase
candidates, confirm 1Password SSH signing agent is available, and recommend the
correct strategy.

## Safety Check Workflow

Run these checks in order:

### 1. Check for merge commits on current branch

```bash
git log --oneline --merges main..HEAD
```

If output is non-empty: the branch contains merge commits. **Do NOT rebase.** Use merge.

If output is empty: branch has no merge commits. Rebase is safe if desired.

### 2. Check branch divergence

```bash
git log --oneline main..HEAD
```

If empty: branch is fully merged into main. Nothing to do.

If non-empty: list the commits that will be included and confirm with the user.

### 3. Confirm 1Password SSH signing agent

```bash
ssh-add -l 2>/dev/null | grep -i "1password\|agent" || echo "WARNING: 1Password agent may not be running"
```

If agent not detected: warn user to unlock 1Password before committing.

```bash
op account list
```

If this fails: 1Password is not authed. Commits will fail with signing error.

### 4. Recommend strategy

Present recommendation:

```
STRATEGY RECOMMENDATION
Branch has merge commits:  NO  →  rebase is safe (but merge also fine)
Branch has merge commits:  YES →  USE MERGE, do not rebase

Recommended: git merge main  (or: git rebase main)
1Password:   READY
```

## Unsafe Rebase — Hard Rule

**Never rebase a branch that contains merge commits.** Per project convention:

> Never rebase branches that contain merge commits. Use `git merge` for conflict
> resolution unless explicitly told to rebase.

When merge commits are detected, always recommend `git merge` and refuse to suggest rebase.

## After Confirmation

Once the user confirms strategy, proceed with the commit:

```bash
git add -A && git commit -m "<message>"
```

If commit fails with `1Password: agent returned an error`: instruct user to open and
unlock 1Password, then retry the commit. No config change is needed.

## Pairing with cargo-gate

Always run `cargo-gate` before `git-guard` on Rust projects:

1. `cargo-gate` — validates the build is clean
2. `git-guard` — confirms strategy and signs the commit

## Additional Resources

- **`references/merge-strategies.md`** — decision matrix, detached HEAD detection, dirty
  working tree handling, 1Password failure recovery, fork-point rebase, squash workflow,
  push patterns, branch state summary template
