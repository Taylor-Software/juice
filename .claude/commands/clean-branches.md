---
description: Find and delete local branches already landed on the default branch. Safe — asks GitHub which branch each merged PR came from, falls back to a subject match, and reports anything it cannot prove.
---

The user wants to clean up local branches whose work has already landed on the default branch. Squash-merge means `git branch --merged` won't recognize them (the merged commit has a different SHA than the branch tip), so the cleanup needs a stronger match.

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

4. **For each candidate, try three checks in order.** The first hit wins; stop there.

   **A — ask GitHub which branch the PR came from (authoritative, use first):**
   ```bash
   gh pr list --state merged --head "<branch>" --json number,title --jq '.[0]'
   ```
   A merged PR whose head ref IS this branch proves the branch landed, **whatever the PR was titled**. This is the check that matters: a branch's head *commit subject* and its *PR title* are different strings, and they only coincide when the branch had exactly one commit. Any multi-commit branch whose PR was retitled on the way in fails check B and passes this one.

   **B — head subject matches a landed commit (offline fallback):**
   ```bash
   git log -1 --format='%s' <branch>                  # the subject
   git log "origin/$DEFAULT" --format='%s' | grep -Fxq "<subject>"
   ```
   Use when `gh` is unavailable/unauthenticated, or the PR record is gone. Exact match — a squash-merge preserves the PR title, so this fires when the branch's last commit *was* what the PR was called.

   **C — `git branch --merged "$DEFAULT"` lists it** (regular merge case, rare).

   Anything matching none of the three is **ambiguous — never delete it.**

5. **For each ambiguous branch, gather evidence so the human can judge in one read.** This is the important half: the checks above are *incomplete by construction* (see below), so the report has to carry enough to settle the question, not just say "dunno".
   ```bash
   git branch -r --contains <branch>        # empty  => never pushed
   git rev-list --count <branch>..origin/$DEFAULT   # how far behind
   git log -1 --format='%ad' --date=short <branch>  # how stale
   git cherry origin/$DEFAULT <branch> | grep -c '^-'  # commits already on the default, by patch-id
   ```
   Report each as: never-pushed?, N commits behind, head date, and how many of its commits are already on the default branch by patch-id.

6. **Show the plan.** No y/n prompt — the user has standing authorization to auto-clean any branch a check above proved landed. Print the plan, then delete straight away. Ambiguous branches are always skipped.
   ```
   safe to delete (N):
     - feat/x: merged PR #123 "<PR title>" (head-ref match)
     - fix/y: matches squash-merge "<subject>" on the default branch
   ambiguous (M, leaving alone):
     - feat/wip-z: never pushed · 107 behind · head 2026-06-30 · 0/11 commits on the default branch
   ```

7. **Delete each safe-to-delete branch with `git branch -D <branch>`** (capital D — squash-merged branches aren't "fully merged" so `-d` refuses them). Tail the output of each.

8. **Final state.** `git branch | head -10` and report. Leave `working` alone either way.

## Why the checks cannot be complete (read before "improving" this)

A local branch can be genuinely, fully merged and still fail **every** mechanical check. Real case that motivated this file (coreciv `trade-caravans-b4`, 2026-07-15):

- Its work shipped as `Trade caravans (B4): spatial, contestable trade routes (#42)` — every symbol and doc it introduced is on the default branch.
- **Check A missed it**: the PR's head ref was `trade-caravans-b4-v2`. The local branch was an earlier attempt; the work was redone on a `-v2` branch and shipped from there.
- **Check B missed it**: its head subject was its 11th commit (`feat(engine): AI trades via caravans instead of instant routes`), not the PR title.
- **Patch-id missed it**: `git cherry` marked all 11 commits `+` (not present), because the rework changed the patches.
- **A SHA search missed it**: the commits were **never pushed**, so GitHub had never seen them.

Proving it merged took *content* judgment — are the symbols on the default branch, are the docs there (they were, under **renamed** paths). No heuristic gets there.

So: **do not chase completeness.** When a branch is ambiguous, the job is to hand the user the evidence in step 5 and let them decide. A false "safe to delete" destroys work; a false "ambiguous" costs one look.

## Edge cases

- **No candidates at all:** report "Nothing to clean — already tidy" and stop.
- **`gh` unavailable / not authenticated / no remote:** skip check A silently, fall through to B and C. Say so in the summary so a thin result isn't mistaken for a clean one.
- **Branch checked out by another worktree:** `git branch -D` fails with `used by worktree at '<path>'`. Surface in "ambiguous", don't delete.
- **You're in a worktree (not the main checkout):** the user does this often. `working` lives in the worktree fine; just make sure step 2 succeeds.

## Output

Compact summary at the end:
```
Cleaned N branches: <comma-separated list>
Left alone M ambiguous branches: <list>
```
