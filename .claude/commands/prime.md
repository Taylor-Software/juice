---
description: Read the project's canonical docs and get primed to work — load scope, status, conventions, TODOs into context. Read-only.
---

The user is starting a working session and wants you primed on the current state of the project before they hand you a task — so you don't burn context re-reading mid-task.

## First, check the checkout is current

A stale checkout gives stale numbers. Before you read anything:

1. Run `git fetch origin` (skip silently if there is no remote or no network).
2. Find the default branch (`git symbolic-ref --short refs/remotes/origin/HEAD`) and count the commits `HEAD` is behind it (`git rev-list --count HEAD..origin/<default>`).
3. If `HEAD` is behind, say so first in the readback: how many commits, and the version or build the checkout holds (from `pubspec.yaml` or the repo's equivalent). Do not pull or switch branches; the user decides.

## What to read

This command is project-agnostic. Read what exists, in this order; skip silently what doesn't.

1. **`CLAUDE.md`** (repo root) — the constitution: conventions, critical rules, layout.
2. **The canonical planning docs.** Read whichever are present (don't fail on absence):
   - `docs/REQUIREMENTS.md` — product scope, what's in / out
   - `docs/REQUIREMENTS_ASSESSMENT.md` — per-requirement status (✅ / 🟡 / ❌)
   - `docs/CODE_QUALITY.md` — code-health findings + staged plan; note the current phase
   - `docs/TODO.md` — open engineering items
   - `docs/PROJECT_NOTES.md` — cross-cutting design patterns, lineage, glossary
   - `docs/testing.md` — in-app / harness test surfaces
   - `ROADMAP.md`, `README.md` — if the repo leads with these instead of a `docs/` tree
3. **Index files, not leaves.** If `docs/` has per-topic subtrees (e.g. `docs/rulesets/`, `docs/action_types/`), read only their `README.md` index. Open individual leaf files later, when a task makes one relevant — never the whole tree up front.

**Don't** front-load the per-area detail files `CLAUDE.md`'s pointer table names (here, `docs/claude/`) — open the matching one when a task lands in that area.

To discover the doc surface cheaply, prefer one Glob (`docs/**/*.md`) over reading blindly.

## Then report back

Tight readback so the user can confirm you loaded the right context. Under 200 words:

- **Current phase / focus** — which plan phase is active and the next item on it
- **Open priorities** — top 2-3 items that look like the next logical work
- **Recent landings** — anything that landed recently, so you don't propose to redo it
- **Checkout** — current, or N commits behind the default branch (name the build it holds)
- **Any drift you spotted** — places where the status docs disagree, or reference code that may have moved

End with: **"Ready. What are we working on?"**

## Don't

- Don't run tests or analyze — that's `/audit`. This is read-only context loading.
- Don't open code files yet — the docs are the source of truth for project *state*. Open code when the user gives a task.
- Don't propose changes — just summarize what's there.
