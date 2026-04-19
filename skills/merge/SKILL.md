---
name: merge
description: >
  Use when the user wants to merge a branch, resolve conflicts, or integrate remote changes.
  Covers fetch, merge, conflict resolution, and verification.
allowed-tools: Read, Bash, Glob, Grep
---

# merge — Safe Branch Integration

Automated merge workflow: pre-merge verification → fetch → merge strategy selection → conflict
resolution → verification.

## Step 1 — Pre-Merge Check

Check current branch and what will merge:

```bash
git status
git log --oneline main..HEAD
```

Output shows:
- Current branch and tracking status
- Commits that will be merged into `main`

If output is empty and status shows "up to date": branch is already merged. Nothing to do.

## Step 2 — Fetch Remote

Ensure remote state is current:

```bash
git fetch origin
```

## Step 3 — Check Upstream Divergence

See if `main` has new commits since branch was created:

```bash
git log --oneline HEAD..origin/main
```

If non-empty: `main` has advanced. Recommend reviewing those commits before merge.

## Step 4 — Decide Merge Strategy

**Check for merge commits on the branch:**

```bash
git log --oneline --merges main..HEAD
```

**If output is non-empty (branch contains merge commits):**
- Use `git merge` — do not rebase
- Per project convention: never rebase branches with merge commits

**If output is empty (no merge commits):**
- Merge is safe and recommended
- Rebase is also safe if user explicitly requests it, but merge is the default

**Recommended command:**

```bash
git merge origin/main
```

Or if not tracking `origin/main`:

```bash
git merge main
```

## Step 5 — Resolve Conflicts (if any)

If merge results in conflicts, `git status` will list conflicted files.

**For each conflicted file:**

1. **Identify the conflict type:**
   - Content conflict: both sides modified
   - Modify/delete conflict: deleted in one branch, modified in the other
   - Add/add conflict: both sides added the file

2. **Resolve by intent:**
   - Accept ours (keep our changes): `git checkout --ours <file>`
   - Accept theirs (take incoming changes): `git checkout --theirs <file>`
   - Manual merge: edit the file, resolve `<<<<<<<...=======...>>>>>>>` markers
   - For modify/delete: decide based on intent (deleted = we intentionally removed it)

3. **After resolving each file:**

   ```bash
   git add <file>
   ```

4. **Complete the merge:**

   ```bash
   git merge --continue
   ```

   You will be prompted for a merge commit message. Accept the default or customize it.

**If merge becomes too complex:**

Do NOT run `git merge --abort` without showing the user what would be lost. Always show:

```bash
git diff HEAD
```

before aborting. Then, if user confirms:

```bash
git merge --abort
```

## Step 6 — Verification

Confirm the merge succeeded:

```bash
git log --oneline main..branch
```

If output is **empty**: the branch is fully merged into `main`. Success.

If output is **non-empty**: merge did not integrate fully. Investigate.

Also verify the commit was created:

```bash
git log --oneline -1
```

Should show the merge commit.

## Step 7 — Push

Push the merged branch:

```bash
git push
```

If the branch has no upstream, set it:

```bash
git push -u origin $(git branch --show-current)
```

Never use `--no-verify`. Let hooks run. If a hook fails, report it — do not retry blindly.

## Step 8 — Report

One-line summary:

```
merged: <branch> -> main | <merge commit hash>
```

If conflicts were resolved, note the files and resolution strategy used.
If the merge was already complete, note that no action was needed.

## Key Rules

- **Never rebase branches with merge commits** — use merge instead
- **Always verify with `git log --oneline main..branch`** — if empty, merge is complete
- **Never abort merge without showing the diff** — preserve local changes
- **Always let hooks run** — never use `--no-verify`
- **Decide conflict resolution by intent, not blindly accepting ours/theirs**

## Additional Resources

- **`references/merge-strategies.md`** — decision matrix, detached HEAD detection, dirty working
  tree handling, 1Password failure recovery, fork-point merge, squash workflow, push patterns,
  branch state summary template
