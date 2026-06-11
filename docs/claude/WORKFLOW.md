# Workflow — git, GitHub, commits, PRs

How work lands on `main`. Portable across machines.

---

## Cross-machine sync

Development may happen on multiple machines. Both must stay in sync
at every task boundary.

**Rule 1 — Before branching or editing:**

```bash
git fetch origin
git checkout main
git pull --ff-only
```

Non-negotiable. The other machine may have merged a PR since last session.

**Rule 2 — Before `git push`:**

```bash
git fetch origin
git rebase origin/main
```

Catches main-branch commits that landed while working.

---

## Branch-per-task workflow

Every distinct work item gets its own branch and PR. Main always
reflects merged tasks only — one squash-commit per task.

### Steps

1. **Pull main.** `git checkout main && git pull --ff-only`

2. **Branch.** `<type>/<slug>` naming, kebab-case, max 4 words.
   Types: `feat/`, `fix/`, `refactor/`, `docs/`, `chore/`, `test/`.

3. **Work + commit.** One coherent commit per branch. Imperative
   title, body explains why. Co-Authored-By trailer.

4. **Rebase before push.**
   ```bash
   git fetch origin main && git rebase origin/main
   git push -u origin <branch>
   ```

5. **PR.** Even for trivial work. `gh pr create`.

6. **Merge.** Squash only. `gh pr merge <num> --squash --delete-branch`.

7. **Cleanup.** `git checkout main && git pull --ff-only && git branch -d <branch>`

### Worktree handling

When Claude auto-spawns a worktree on `claude/<random>`, rename
before first commit:
```bash
git branch -m <type>/<slug>
```

### Don't

- Push directly to main. Always branch + PR.
- Use merge commits or rebase-merge. Squash only.
- Keep branches after merge.

---

## Close the loop

After every major step (bug fix, feature, refactor, phase), close
end-to-end before moving on:

1. **Cleanup** — delete temp files, verify `git status` is clean.
2. **Document** — update docs as the change requires. Add memory
   entries for durable conventions.
3. **Ship** — invoke `/ship-pr <title>` automatically.
4. **Clean** — invoke `/clean-branches` immediately after merge.

---

## Commit conventions

- Imperative mood, no trailing period in title.
- Body wraps ~72 cols, explains what changed and why.
- Trailer: `Co-Authored-By: Claude <model> <noreply@anthropic.com>`
- Match recent style: `git log --oneline -10`.
- Single coherent commit per branch/PR.

---

## Estimating work in tokens

Express effort as tokens Claude needs (file I/O + edits + verification),
not human-day estimates.

| Bucket | Description |
|---|---|
| ~2K tokens | Single-file targeted edit |
| ~5-10K | Multi-file scaffold |
| ~20-40K | Cross-cutting refactor with verification |
| ~80-150K | Major feature + docs + tests |
