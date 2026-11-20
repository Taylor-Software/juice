---
description: Ship the staged work as one squash-merged PR — commit + push + PR + merge + cleanup, run automatically.
---

Ship the current work as one PR, from "I have changes" to "squash-merged on the default branch, local cleaned up". `$ARGUMENTS` is the PR title and commit subject; if empty, stop: "Pass a title: `/ship-pr fix(ui): …`".

Locally use `gh`. In a remote/web session `gh` is unavailable: use the GitHub MCP tools (`create_pull_request`, `merge_pull_request`, `pull_request_read`) for the PR steps. The git steps are the same.

## Preconditions — stop if any fails

- `DEFAULT=$(git remote show origin | sed -n 's/.*HEAD branch: //p')`. Never hardcode `main`/`master`.
- Not on `$DEFAULT` ("Won't ship from the default branch; create a branch first.").
- Something to ship: `git status --short` or `git log origin/$DEFAULT..HEAD` is non-empty ("Nothing to ship.").

## Steps

1. **Bump the build number.** `pubspec.yaml` `version: X.Y.Z+N` → `N+1` (the build the app shows in its settings/about version row).
2. **Stage by explicit path**, never `git add -A`: a local `flutter build ios` mutates tracked `ios/` files. Leave out build output, `.env`, credentials and unrelated `ios/` churn.
3. **Gate** (the analyze and test commands `CLAUDE.md` names as the gate, else `flutter analyze` and `flutter test`) must pass. On failure: don't commit; show it and ask how to proceed.
4. **Review gate.** Spawn a subagent: "Follow `.claude/commands/flutter-review.md` in ship-pr mode (staged diff). Return its full output." Read its last non-blank line:
   - `✅ PASS` → print any ADVISORY lines under "ℹ️ Advisory (non-blocking):", continue.
   - `🚫 BLOCK` → abort without committing; print the BLOCK findings and "flutter-review blocked ship — fix the above findings and re-run /ship-pr."
   - Anything else → abort: "flutter-review returned no clear verdict; re-run /ship-pr."
5. **Commit** (HEREDOC). Subject = `$ARGUMENTS`. Body: 1–3 short paragraphs on *why*, matching the tone of `git log --format='%B' -5`. End with `Co-Authored-By: Claude <noreply@anthropic.com>`.
6. **Rebase.** `git fetch origin "$DEFAULT" && git rebase "origin/$DEFAULT"`. On conflict, stop: "rebase conflict on `<file>`, resolve and re-run /ship-pr."
7. **Push.** `git push -u origin <branch>` (plain `git push` if it already tracks).
8. **Open the PR.** Title = `$ARGUMENTS`. Body:
   ```markdown
   ## Summary
   <2-4 bullets from the commit body>

   ## Test plan
   - [x] analyze clean
   - [x] tests pass
   - [ ] <manual smoke check, if UI-visible>

   🤖 Generated with [Claude Code](https://claude.com/claude-code)
   ```
   On HTTP 504, retry once.
9. **Merge.** `gh pr merge <num> --squash --delete-branch --admin` (`--admin` is authorized for solo work). If it is already merged, skip to 10. A warning that the default branch "is already used by worktree" is expected; ignore it. On merge conflicts, stop: "PR #<num> has merge conflicts, resolve on the branch and re-run."
10. **Verify** `gh pr view <num> --json state` reads `MERGED`. Delete the remote branch if it survived: `git push origin --delete <branch>`.
11. **Reset locally.** `git checkout -B working "origin/$DEFAULT" && git fetch --prune origin && git branch -D <branch>`.
12. **Report** one line: `Merged via #<num>: <title>`.

## Never

- `--no-verify` on commit or push. If a hook fails, fix the cause and re-commit; never `--amend` after a failed commit (it didn't happen).
- Push to `$DEFAULT` directly, or merge without `--squash`.
- Run `/audit` as well: step 3 is the gate.
- Sleep or poll for merge state.
