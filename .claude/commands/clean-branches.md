---
description: Find and delete local branches whose squash-merge already landed on the default branch. Safe — only deletes branches whose subject matches a merged commit.
---

The user wants to clean up local branches that have been squash-merged into the default branch. Squash-merge means `git branch --merged` won't recognize them (the merged commit has a different SHA than the branch tip), so the standard cleanup needs a content-aware match.

## What to do

1. **Sync state and detect the default branch.** `git fetch --prune origin` (trims any remote refs whose remote branch was deleted), then — repos differ (`main` vs `master`), so never hardcode it:
   ```bash
   DEFAULT=$(git remote show origin | sed -n 's/.*HEAD branch: //p')
   ```
   Every reference to `$DEFAULT` below means this detected branch.

2. **Move off the target branches.** If the current branch is anything other than `main` / `working` / `master`, switch to `working` first (or create it from the default branch if it doesn't exist):
   ```bash
   git checkout -B working "origin/$DEFAULT"
   ```
   Otherwise `git branch -D` against the current branch fails.

3. **List local branches** other than `main`, `master`, `working`:
   ```bash
   git for-each-ref --format='%(refname:short)' refs/heads/ \
     | grep -vE '^(main|master|working)$'
   ```

4. **For each candidate, decide if it's safely deletable.** A branch is safely deletable if EITHER:
   - **Its head commit's subject matches an already-landed commit on the default branch** (squash-merge case). Read the branch's head subject (`git log -1 --format='%s' <branch>`) and grep `git log "origin/$DEFAULT" --format='%s'` for that exact line. The match is exact — squash-merge preserves the title.
   - **`git branch --merged "$DEFAULT"` lists it** (regular merge case, rare in this repo).

   Branches that match NEITHER are surfaced as "ambiguous, leaving alone" — don't delete.

5. **Build the deletion plan** as a list:
   ```
   safe to delete (N):
     - feat/x: matches squash-merge "<subject>" on the default branch
     - fix/y: ...
   ambiguous (M, leaving alone):
     - feat/wip-z: head subject not found on the default branch; might be unmerged work
   ```

6. **Show the plan to the user.** No y/n prompt — the user has standing authorization to auto-clean any branch whose head subject matches a squash-merged commit on the default branch. Print the plan, then proceed straight to deletion. (Ambiguous branches are still skipped; only the "safe to delete" list is touched.)

7. **Delete each safe-to-delete branch with `git branch -D <branch>`** (capital D — these are squash-merged so `-d` would refuse them as "not fully merged"). Tail the output of each.

8. **Final state.** Run `git branch | head -10` and report. If `working` exists, leave it; if it didn't before, leave it (you created it in step 2 to enable cleanup).

## Edge cases

- **No candidates at all:** report "Nothing to clean — already tidy" and stop.
- **Branch checked out by another worktree:** `git branch -D` will fail with `used by worktree at '<path>'`. Surface that branch in the "ambiguous" list, don't delete.
- **You're in a worktree (not the main checkout):** the user does this often. `working` lives in the worktree fine; just make sure step 2 succeeds.

## Output

Compact summary at the end:
```
Cleaned N branches: <comma-separated list>
Left alone M ambiguous branches: <list>
```
