---
description: Find and delete local branches whose squash-merge already landed on main.
---

Clean up local branches that have been squash-merged into main. Squash-merge means `git branch --merged main` won't recognize them — uses content-aware subject matching.

## Steps

1. **Sync.** `git fetch --prune origin`.

2. **Move off target branches.** If current branch isn't `main`/`working`/`master`:
   ```bash
   git checkout -B working origin/main
   ```

3. **List candidates:**
   ```bash
   git for-each-ref --format='%(refname:short)' refs/heads/ \
     | grep -vE '^(main|master|working)$'
   ```

4. **For each candidate, check if safely deletable:**
   - Head commit subject matches a landed commit on main (squash-merge case): read `git log -1 --format='%s' <branch>` and grep `git log origin/main --format='%s'`.
   - OR `git branch --merged main` lists it (regular merge).
   - Neither match → "ambiguous, leaving alone."

5. **Show the plan:**
   ```
   safe to delete (N):
     - feat/x: matches squash-merge "<subject>" on main
   ambiguous (M, leaving alone):
     - feat/wip-z: head subject not found on main
   ```

6. **Delete safe branches** with `git branch -D <branch>` (capital D — squash-merged branches need force).

7. **Report:**
   ```
   Cleaned N branches: <list>
   Left alone M ambiguous: <list>
   ```

## Edge cases

- No candidates: "Nothing to clean — already tidy."
- Branch used by worktree: surface in ambiguous list, don't delete.
