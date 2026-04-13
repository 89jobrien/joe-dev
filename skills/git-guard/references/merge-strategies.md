# Merge Strategy Reference

## Decision Matrix

| Condition | Strategy | Command |
|-----------|----------|---------|
| Branch has merge commits | Merge only | `git merge main` |
| Branch has no merge commits, linear history | Rebase safe | `git rebase main` |
| Branch is fully merged (no output from `git log main..HEAD`) | Nothing to do | — |
| Detached HEAD | Cannot commit | `git checkout <branch>` first |
| Dirty working tree | Cannot commit | `git stash` or commit changes |

**Hard rule:** never rebase a branch that contains merge commits. It rewrites history in
ways that corrupt the merge topology and are hard to recover from.

## Detecting Merge Commits

```bash
git log --oneline --merges main..HEAD
```

- Empty output → no merge commits on branch → rebase is safe
- Any output → merge commits present → use `git merge`, not `git rebase`

## Detecting Detached HEAD

```bash
git branch --show-current
```

- Empty output → detached HEAD state → cannot commit until on a named branch
- Fix: `git checkout -b <new-branch-name>` or `git checkout <existing-branch>`

## Checking Working Tree Cleanliness

```bash
git status --short
```

- Empty output → clean
- Any output → uncommitted changes — run `cargo-gate` first, then commit or stash

## 1Password SSH Signing — Failure Recovery

If `git commit` fails with `1Password: agent returned an error`:

1. Open the 1Password desktop app
2. Unlock it (authenticate with Touch ID or password)
3. Retry `git commit` — no config change needed

The SSH key is already wired to the 1Password agent. The agent just needs to be running and
authenticated.

To verify the agent is responding before committing:

```bash
ssh-add -l 2>/dev/null
```

- Lists loaded keys (should show a 1Password key)
- Empty or error → agent not running → unlock 1Password first

## Fork-Point Rebase

When a branch diverged from main before main received additional commits, a naive rebase
may use the wrong base. Use `--fork-point` to auto-detect the correct ancestor:

```bash
git rebase --fork-point main
```

Only relevant for long-running branches. Not needed for same-day feature branches.

## Squash Before Merge

When a branch has many noisy commits and no merge commits, squash before merging:

```bash
# Interactive squash (do NOT use -i in Claude — no TTY)
# Instead: soft-reset and re-commit
git reset --soft main
git commit -m "feat: <description of accumulated work>"
```

Only do this with explicit user instruction — it rewrites branch history.

## Push After Commit

After a successful commit:

```bash
git push
```

If the branch has no upstream yet:

```bash
git push -u origin <branch-name>
```

Never force-push to `main`. Force-push to feature branches only with explicit instruction.

## Branch State Summary Template

Present this after running all checks:

```
GUARD CHECK          RESULT
Merge commits        NO    → rebase is safe
Branch divergence    3 commits ahead of main
Working tree         clean
1Password agent      READY

Recommended: git merge main  (or: git rebase main)
```
