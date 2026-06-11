---
description: Read project docs and get ready to work — load scope, status, conventions into context.
---

Starting a working session — prime on current project state before the user hands a task.

## What to read

Read these in order (skip any that don't exist):

1. **`CLAUDE.md`** — project guide (auto-loaded, but re-read for completeness)
2. **`docs/`** — scan for design specs, requirements, architecture docs, TODO files
3. **`docs/claude/`** — portable conventions (WORKFLOW.md, CONVENTIONS.md, etc.)
4. **`PLAN.md`** or equivalent roadmap files
5. **Recent git history** — `git log --oneline -15` to see what landed recently

## Then report back

Tight readback, under 200 words:

- **Current state** — what phase/milestone the project is in, open priorities
- **Recent landings** — what landed in the last few commits (don't propose to redo it)
- **Test status** — quick `flutter analyze` + `flutter test` counts (don't fix, just report)
- **Any drift** — places where docs disagree with code state

End with: **"Ready. What are we working on?"**

## Don't

- Don't run fixes — read-only context loading.
- Don't open code files yet — docs are the source of truth for project state.
- Don't propose changes — just summarize what's there.
