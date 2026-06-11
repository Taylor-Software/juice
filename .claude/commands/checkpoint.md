---
description: Full project checkpoint — verify, document, clean, commit, push, PR.
---

Execute these phases in strict order. Stop and report if any phase fails.

## Phase 1: Verify

1. `git status` — note modified/untracked files.
2. `git diff --stat` — scope of changes.
3. `flutter analyze` — fix issues before proceeding.
4. `flutter test` — fix failures before proceeding.
5. Count passing tests from output.

## Phase 2: Document findings

Summarize what changed since last commit. `git log --oneline -5` for recent history, compare against diff:
- What was added/changed/fixed
- Key decisions or trade-offs
- Bugs found and resolved

## Phase 3: Update memory

Read memory index at the project's memory directory. Update memory files to reflect:
- Phase/milestone completion status
- Test count
- Current branch
- New API discoveries, key decisions, architectural changes
- Remove stale entries

Keep MEMORY.md index under 200 lines. Each entry one line, under 150 chars.

## Phase 4: Cleanup

1. `dart fix --apply` to auto-fix remaining issues.
2. `flutter analyze` one final time — zero issues.
3. Resolve any new issues from dart fix manually.

## Phase 5: Commit

1. `git status` — final state.
2. `git diff --stat` — confirm scope.
3. Stage relevant files — prefer named files over `git add -A`. Never stage `.env`, credentials, or large binaries.
4. Write commit message:
   - Conventional commit format (fix:, feat:, chore:, etc.)
   - Summarize "why" in 1-2 sentences
   - End with `Co-Authored-By: Claude <model> <noreply@anthropic.com>`
5. Commit using HEREDOC.

## Phase 6: Push

1. `git branch --show-current`
2. `git status -sb` — check upstream tracking.
3. `git push origin <branch>` (add `-u` if no upstream).

## Phase 7: PR or Direct

- **On main:** push is sufficient.
- **On feature branch:** `gh pr create` with short title (<70 chars), body with `## Summary` + `## Test plan`, footer `Generated with [Claude Code](https://claude.com/claude-code)`. Report PR URL.

## Completion report

- Branch and commit hash
- Test count (passing/total)
- Files changed
- PR URL (if created)
