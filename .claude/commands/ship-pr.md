---
description: Ship the staged work as one squash-merged PR — commit + push + PR + merge + cleanup. The 10-step branch-PR-merge dance run automatically.
---

The user wants to ship the current work as a complete pull request — the full mechanical dance from "I have changes" to "merged on the default branch and local cleaned up."

> **Environment note:** the `gh` steps below assume a local session where `gh` is authed. In a remote / web session `gh` is unavailable — use the GitHub MCP tools (`mcp__github__create_pull_request`, `mcp__github__merge_pull_request`, `mcp__github__pull_request_read`) for the PR open / merge / verify steps instead. The git steps (stage, commit, rebase, push) are the same in both.

## Preconditions you check before doing anything

1. **Detect the default branch** — repos differ (`main` vs `master`), so never hardcode it:
   ```bash
   DEFAULT=$(git remote show origin | sed -n 's/.*HEAD branch: //p')
   ```
   Every reference to `$DEFAULT` below means this detected branch.
2. **You're not on `$DEFAULT`** — `git branch --show-current` must be a feature / fix / docs / chore branch. If on the default branch, error out: "Won't ship from the default branch; create a branch first."
3. **The branch tracks `origin/<same-branch>` OR is brand-new** — either is fine; brand-new means you'll push with `-u`.
4. **There's something to ship** — if `git status --short` is empty AND `git log origin/$DEFAULT..HEAD` is empty, error out: "Nothing to ship."

## What `$ARGUMENTS` contains

The argument string is the PR title (and the commit subject). Required. If empty, error: "Pass a title: `/ship-pr fix(ui): …`"

## What to do

1. **Stage everything**: `git add -A`. (The user has already done their own staging if they cared; staging the rest is the right default at ship time.)
2. **Verify analyze + tests pass.** Run `flutter analyze` and `flutter test` (full suite). If either fails, abort: don't commit, surface the failure, ask the user how to proceed. The user's policy is "tests + analyze clean before ship."
3. **Compose the commit body.** Use the diff (`git diff --cached --stat` + the actual diff hunks for any non-trivial changes) and recent commit history (`git log --oneline -5`) as input. Body should be 1-3 short paragraphs explaining what changed and why, NOT what the diff already shows. Match the user's existing commit style — see recent commits with `git log --format='%B' -5` for tone. Always end with the `Co-Authored-By: Claude <noreply@anthropic.com>` line.
4. **Commit** via HEREDOC so newlines are preserved:
   ```bash
   git commit -m "$(cat <<'EOF'
   <title from $ARGUMENTS>

   <body you composed>

   Co-Authored-By: Claude <noreply@anthropic.com>
   EOF
   )"
   ```
5. **Pull + rebase before push.** `git fetch origin "$DEFAULT"` and `git rebase "origin/$DEFAULT"`. If conflicts, abort and surface them: "rebase conflict on `<file>`, resolve and re-run /ship-pr."
6. **Push the branch.** `git push -u origin <branch>` if it doesn't track yet, otherwise plain `git push`. Tail the last 3 lines of output.
7. **Open the PR.** Use `gh pr create` with `--title` matching `$ARGUMENTS` and `--body` from a HEREDOC. Body template:
   ```markdown
   ## Summary
   <2-4 bullet recap, derived from the commit body>

   ## Test plan
   - [x] flutter analyze clean
   - [x] flutter test passes
   - [ ] <one or two manual smoke checks if the change is UI-visible>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   ```
   Capture the PR URL from the output.
8. **Squash-merge with admin.** `gh pr merge <num> --squash --delete-branch --admin`. The command may print one warning that the default branch `is already used by worktree` — that's expected (the merge happens on the remote anyway, and the local default-branch worktree is held by another session). Ignore that line; the next command compensates.
9. **Verify merge** with `gh pr view <num> --json state` — must show `MERGED`.
10. **Force-delete the remote branch** if it still exists: `git push origin --delete <branch>`. The squash-merge with `--delete-branch` usually handles this but the worktree-lock warning sometimes leaves it behind.
11. **Reset locally** to a fresh `working` branch off the default branch:
    ```bash
    git checkout -B working "origin/$DEFAULT"
    git fetch --prune origin
    git branch -D <feature-branch>
    ```
12. **Report.** One short line: `Merged via #<num>: <title>`. No essay.

## Edge cases

- **Pre-commit hook fails on commit (step 4):** investigate the underlying issue and fix, then re-stage and re-run `git commit`. NEVER use `--no-verify`. NEVER use `--amend` after a hook failure (the commit didn't happen — amend would modify the previous commit).
- **PR creation fails with `HTTP 504` (step 7):** retry once with the same body. If retry fails, surface the error to the user.
- **gh pr merge fails because PR has merge conflicts:** abort, surface "PR #<num> has merge conflicts, resolve on the branch and re-run."
- **The PR was already merged manually before you got to step 8:** check `gh pr view <num> --json state` first. If MERGED, skip the merge step and proceed with cleanup.

## What you don't do

- Don't run `/audit` or duplicate the analyze + test work it already does — just inline `flutter analyze` and `flutter test`.
- Don't open the user's editor to write the commit message — compose it yourself from the diff.
- Don't push to the default branch directly. Don't bypass `--squash`. Don't skip `--admin` (the user has authorized it for solo work).
- Don't sleep / poll for merge state. `gh pr view` is synchronous.
- Don't use `git push --no-verify` or `git commit --no-verify`. If hooks fail, fix the cause.
