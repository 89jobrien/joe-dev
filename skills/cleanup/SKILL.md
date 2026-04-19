---
name: cleanup
description: >
  Use when the user wants to clean up merged branches locally and on remote. Lists merged branches,
  confirms before deleting, and prunes stale remote refs.
allowed-tools: Read, Bash
---

# cleanup — Merge Branch Cleanup

Safe deletion of local and remote branches that have been merged into main. Always shows what
will be deleted and confirms before proceeding.

## Step 1 — List Merged Local Branches

```bash
git branch --merged main | grep -v '^\*\|main\|master'
```

Filter out:
- Current branch (marked with `*`)
- main and master (never delete)

## Step 2 — List Merged Remote Branches

```bash
git branch -r --merged origin/main | grep -v 'origin/main\|origin/master'
```

Filter out:
- origin/main and origin/master (never delete)

## Step 3 — Verify Branches Are Truly Merged

For each branch found, verify it is fully merged:

```bash
git log --oneline main..<branch>
```

If output is empty: branch is fully merged. Safe to delete.

If output is non-empty: branch has commits not in main. Do NOT delete. Warn the user.

## Step 4 — Check for Open Pull Requests

Before deleting a remote branch, check for open PRs:

```bash
gh pr list --head <branch> --state open
```

If any open PRs exist: skip deletion of that branch. Note it and ask the user if they want to
close the PR first.

## Step 5 — Show the Deletion Plan

Display a summary:

```
Local branches to delete:
  branch-1
  branch-2

Remote branches to delete:
  origin/branch-3
  origin/branch-4

Branches with open PRs (will be skipped):
  branch-5
```

Ask for explicit confirmation:

```
Proceed with deletion? (yes/no)
```

## Step 6 — Delete Local Branches

Use `-d` (safe delete only — fails if not fully merged):

```bash
git branch -d <branch>
```

**Never use `-D`** — it force-deletes without checking.

Report each deletion:

```
Deleted: branch-1
Deleted: branch-2
```

## Step 7 — Delete Remote Branches

```bash
git push origin --delete <branch>
```

Report each deletion:

```
Deleted remote: origin/branch-3
Deleted remote: origin/branch-4
```

## Step 8 — Prune Stale Remote References

```bash
git remote prune origin
```

## Step 9 — Final Report

Summary:

```
cleanup complete:
  Local branches deleted: N
  Remote branches deleted: M
  Stale refs pruned
```

## Safety Rules (Hard)

- **Never delete:** main, master, current branch
- **Always confirm:** show deletion plan before proceeding
- **Use `-d` not `-D`:** safe mode only
- **Check for open PRs:** before deleting remote branches
- **Verify merge status:** empty `git log main..<branch>` output required
- **Never prune stashes:** only prune remote refs

## When Deletion Fails

If `git branch -d <branch>` fails (branch not fully merged):

```
Cannot delete <branch>: not fully merged
```

Skip it and continue with others. Note it in the final report.

If `git push origin --delete <branch>` fails (remote branch doesn't exist), skip and continue.

## Additional Resources

Related: cap (commit and push), git-guard (merge strategy verification)
