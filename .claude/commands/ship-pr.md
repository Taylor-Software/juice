---
description: Ship the staged work as one squash-merged PR — commit + push + PR + merge + cleanup.
---

Ship current work as a complete pull request — the full mechanical dance from "I have changes" to "merged on main and local cleaned up."

## Preconditions

1. **Not on `main`** — `git branch --show-current` must be a feature/fix/docs/chore branch. If on main: "Won't ship from main; create a branch first."
2. **Branch tracks `origin/<same-branch>` OR is brand-new** — either is fine; brand-new means push with `-u`.
3. **Something to ship** — if `git status --short` is empty AND `git log origin/main..HEAD` is empty: "Nothing to ship."

## What `$ARGUMENTS` contains

PR title (and commit subject). Required. If empty: "Pass a title: `/ship-pr fix(ui): …`"

## Steps

1. **Stage everything**: `git add -A`.
2. **Verify analyze + tests pass.** Run `flutter analyze` and `flutter test`. If either fails, abort — surface the failure, ask how to proceed.
3. **Compose commit body.** Use `git diff --cached --stat` + diff hunks + `git log --oneline -5` as input. Body: 1-3 short paragraphs explaining what changed and why. Match existing commit style. End with `Co-Authored-By: Claude <co-authored-by-model> <noreply@anthropic.com>` trailer (detect the current model name from the conversation).
4. **Commit** via HEREDOC:
   ```bash
   git commit -m "$(cat <<'EOF'
   <title from $ARGUMENTS>

   <body>

   Co-Authored-By: Claude <model> <noreply@anthropic.com>
   EOF
   )"
   ```
5. **Rebase before push.** `git fetch origin main && git rebase origin/main`. If conflicts: abort and surface them.
6. **Push.** `git push -u origin <branch>` if no upstream, otherwise `git push`.
7. **Open PR.** `gh pr create` with `--title` from `$ARGUMENTS` and `--body` HEREDOC:
   ```markdown
   ## Summary
   <2-4 bullet recap>

   ## Test plan
   - [x] flutter analyze clean
   - [x] flutter test passes
   - [ ] <manual smoke checks if UI-visible>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   ```
   Capture PR URL.
8. **Squash-merge.** `gh pr merge <num> --squash --delete-branch --admin`.
9. **Verify merge** with `gh pr view <num> --json state` — must show `MERGED`.
10. **Force-delete remote branch** if still exists: `git push origin --delete <branch>`.
11. **Reset locally:**
    ```bash
    git checkout -B working origin/main
    git fetch --prune origin
    git branch -D <feature-branch>
    ```
12. **Report.** One line: `Merged via #<num>: <title>`.

## Edge cases

- **Pre-commit hook fails:** investigate and fix, re-stage, new commit. NEVER `--no-verify`. NEVER `--amend` after hook failure.
- **PR creation 504:** retry once.
- **Merge conflicts on PR:** abort, surface to user.
- **PR already merged:** skip merge step, proceed with cleanup.

## Don't

- Don't duplicate analyze + test work — inline `flutter analyze` and `flutter test`.
- Don't push to `main` directly. Don't bypass `--squash`.
- Don't sleep/poll. `gh pr view` is synchronous.
- Don't use `--no-verify`.
