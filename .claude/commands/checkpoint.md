---
description: Full project checkpoint — verify, document, clean, commit, push, PR.
---

Run these phases in order. Stop and report if one fails.

1. **Clean.** `dart fix --apply`, then review its diff: some fixes produce code that does not compile, so revert any hunk that is wrong. This runs before Verify so the gate covers it.
2. **Verify.** `git status`, `git diff --stat`, then the gate (the analyze and test commands `CLAUDE.md` names as the gate, else `flutter analyze` and `flutter test`). Fix failures before going on. Note the passing-test count.
3. **Document.** From the diff and `git log --oneline -5`: what was added, changed or fixed; key decisions and trade-offs; bugs found and resolved.
4. **Update memory.** In the project's memory directory, update milestone status, test count, current branch and key decisions; remove stale entries. Keep `MEMORY.md` under 200 lines, one line per entry, each under 150 characters.
5. **Commit.** Stage named files, never `git add -A`, and never `.env`, credentials or large binaries. Conventional-commit subject (`fix:`, `feat:`, `chore:`…); body says why in 1–2 sentences; end with `Co-Authored-By: Claude <noreply@anthropic.com>`. Use a HEREDOC.
6. **Push.** `git push origin <branch>`, with `-u` if it has no upstream.
7. **PR.** On the default branch, the push is enough. On a feature branch, `gh pr create` with a title under 70 characters, `## Summary` and `## Test plan`, and the footer `Generated with [Claude Code](https://claude.com/claude-code)`.

Report: branch and commit hash, tests passing/total, files changed, PR URL if any.
