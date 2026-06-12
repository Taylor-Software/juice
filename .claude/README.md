# `.claude/` — the integrated development system

This directory is the Claude Code harness for this repo: slash commands, subagents,
permissions, and hooks. It's tuned to **supercharge the workflow while staying
token-frugal**, and it shares a canonical workflow layer with the sibling `deep_iq_v2`
repo so the muscle memory is identical across both projects.

## Design principles

1. **Shared workflow, per-project depth.** The generic lifecycle commands/agents are
   byte-identical across `juice` and `deep_iq_v2` (the canonical layer). Domain-specific
   helpers live only where they apply.
2. **Token routing is the main cost lever.** Mechanical work runs on cheap models in
   isolated subagent context; only judgment and synthesis run on the session model.
3. **Deterministic gates, not advisory hopes.** Formatting and the stop-check are hooks,
   so they happen regardless of what the model remembers to do.

## Commands (`commands/`)

All six are shared-canonical (identical in `deep_iq_v2`):

| Command | What it does |
|---|---|
| `/prime` | Read-only: loads `CLAUDE.md` + canonical docs (`README.md`, `ROADMAP.md`, `docs/`), reports project state. Start here. |
| `/audit` | `flutter analyze` + `flutter test`, compressed to counts + failures. ~1-2K token cost regardless of suite size. |
| `/checkpoint` | Verify → document → cleanup → commit → push → PR, in strict phases. |
| `/ship-pr <title>` | Full branch→commit→rebase→push→PR→squash-merge→cleanup. Works local (`gh`) or remote (GitHub MCP). |
| `/clean-branches` | Delete local branches whose squash-merge already landed on `main`. Content-aware + safe. |
| `/code-analysis` | Fans out 4 **Haiku** scan agents (packages/patterns/perf/dead-code), synthesizes on the session model. |

## Subagents (`agents/`) and model routing

| Agent | Model | Why |
|---|---|---|
| `doc-syncer` | sonnet | Judgment about which docs a change touches. |
| `screenshot-bug-tracer` | sonnet | Vision + code tracing. |
| `github-steward` | sonnet | Multi-step GitHub orchestration (repo-agnostic). |

**Convention for ad-hoc subagents:** when *you* spawn an `Explore`/`general-purpose`
agent for retrieval or fan-out search, pass `model: haiku`. Reserve the session model
for synthesizing their results — that's where most of the token savings live.

## Hooks & permissions (`settings.json`)

- **PreToolUse (graphify nudge)** — when `graphify-out/graph.json` exists, grep/find/read
  calls get a reminder to query the knowledge graph instead of grepping raw files.
- **PostToolUse (format-on-edit)** — after any `Edit`/`Write` to a `.dart` file, runs
  `dart format` on just that file. Guarded by `command -v dart`, silent on success.
- **Stop (gate)** — if uncommitted `.dart` changes remain when a turn ends, surfaces a
  non-blocking reminder to run `/audit` then `/checkpoint` or `/ship-pr`.
- **permissions.allow** — a shared superset of safe routine commands so the common loop
  runs without permission prompts.

## graphify (token-saver)

This repo leads the graphify workflow. Build the graph with the `graphify` CLI in the
repo root (writes `graphify-out/`); once present, the hooks nudge toward
`graphify query "<question>"` / `explain "<concept>"` / `path "<A>" "<B>"` — a scoped
subgraph is far cheaper than reading source files. Absent the graph, the hooks no-op.

## Keeping the canonical layer in sync

The six commands above and `agents/github-steward.md` are intended to be **identical** in
`juice/.claude/` and `deep_iq_v2/.claude/`. When you change one, mirror it to the other
in the same change.
