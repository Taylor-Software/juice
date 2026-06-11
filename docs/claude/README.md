# Claude context — portable across machines

This directory mirrors project conventions, workflow rules, and build
instructions so any Claude session on any host picks up the full
context on first clone — not just the host that originally accumulated
the `~/.claude/.../memory/` directory.

## Files

| File | Purpose |
|---|---|
| [CONVENTIONS.md](CONVENTIONS.md) | Coding rules, doc maintenance — "how we work" |
| [WORKFLOW.md](WORKFLOW.md) | Branch-per-task git workflow, commit conventions, PR ops |

## When to read

A session bootstraps in this order:

1. **`CLAUDE.md`** at repo root — project guide (auto-loaded)
2. **`docs/`** — design specs, requirements, architecture docs
3. **This directory** — workflow / conventions
4. **`.claude/agents/*.md`** and **`.claude/commands/*.md`** — specialists and slash commands

## Why this exists

Claude Code's auto-memory persists per-user, per-machine. The
`~/.claude/projects/<hash>/memory/` directory doesn't travel with
`git clone`. To give a session on any machine the same context, rules
live in the repo.

Session-ephemeral notes stay per-user. This directory is for
**durable project conventions** any Claude session should know.

## Keeping in sync

**Rule:** when a session adds a durable convention to memory, mirror
it into `docs/claude/` in the same change. Otherwise a session on a
fresh host operates with stale rules.

| Memory pattern | Mirror into |
|---|---|
| `feedback_*` about coding rules | [CONVENTIONS.md](CONVENTIONS.md) |
| `feedback_*` about workflow / git / commits | [WORKFLOW.md](WORKFLOW.md) |
| `project_*` about architecture | CONVENTIONS.md or a new PROJECT_CONTEXT.md |

### What does NOT get mirrored

- Session-ephemeral memory ("skip tests on this branch")
- Personal info (emails, absolute home paths, passwords)
