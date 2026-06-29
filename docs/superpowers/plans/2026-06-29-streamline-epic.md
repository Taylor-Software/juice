# Streamline & Connective-Tissue Epic — Roadmap

> **Status:** active. One PR per phase, merged to `main` between phases.
> **Origin:** product critique 2026-06-29 ("what are we missing / how to streamline"),
> re-scoped against a code recon that found two proposed features already shipped.

## Recon correction (why this differs from the raw critique)

The original critique reasoned from `CLAUDE.md`, not the full tree. Recon (3 agents,
2026-06-29) found:

- **Session continuity — ALREADY BUILT.** `JournalKind.session` +
  `JournalNotifier.addSessionBreak` (`lib/state/providers.dart:143`) + a full
  `SessionResumeScreen` ("where did I leave off", `lib/features/session_resume_screen.dart`)
  shown on re-entry (`lib/features/enter_campaign.dart:58`), with recap. **Dropped.**
- **Narrative export — ALREADY BUILT.** Journal Markdown/HTML export
  (`journal_screen.dart:1921`, `export-markdown`/`export-html`) + Lonelog `.md`
  (`exportActiveAsLonelog`, `providers.dart:1519`). **Dropped** (a polished prose
  "campaign story" compile is a possible later nicety, not a gap).
- **Journal search — PARTIALLY BUILT.** `journal-search` toggle + pure
  `searchEntries` (`lib/engine/journal_search.dart`), but **journal-only,
  single-campaign**. Threads/rumors/tracks/characters not searchable. Re-scoped
  to "cross-entity search."

## Genuinely-missing backlog (confirmed against code)

| # | Phase | Why | Size | Risk |
|---|-------|-----|------|------|
| 1 | Custom oracle/random tables ✅ **shipped** | Zero runtime table authoring; #1 solo-player hack | M | Low |
| 2 | Cross-entity search ✅ **shipped** | Search is journal-only; can't find an NPC/thread/rumor | M | Low |
| 3 | Entity linking / backlinks ✅ **shipped** | Entities are islands; no connective tissue | L | Med |
| 4 | First-run onboarding ✅ **shipped** | No onboarding for a 16-system app; sprawl undiscoverable | M | Low |
| 5 | Backup safety ✅ **shipped** | Export exists but no "last backed up" nudge / one-tap | S | Low |
| 6 | Play-loop "Now" consolidation | Run/Track/Sheet overlap; the actual sprawl disease | L | High |

## Chosen order (rationale)

Self-contained + low-risk first to build momentum and land value fast; the big UX
refactor (#6) last, after the connective-tissue features teach us what the unified
surface needs. Each phase ships independently behind its own PR.

1. **Custom oracle tables** — clean new model, reuses the existing
   `roll → journalProvider.addResult` pipeline. Pure-engine-first, TDD-friendly.
2. **Cross-entity search** — extends the proven `searchEntries` pattern to a
   campaign-wide "find anything" over journal + threads + rumors + tracks +
   characters. Pure search core, thin UI.
3. **Entity linking / backlinks** — generic mention/link + a backlink panel.
   Bigger; benefits from #2's search to pick link targets.
4. **First-run onboarding** — intro cards + seeded demo campaign + progressive
   system disclosure. Addresses discovery/sprawl. Self-contained.
5. **Backup safety** — "last exported" timestamp + a reminder nudge + one-tap
   export. Small.
6. **Play-loop "Now" consolidation** — audit Run/Track/Sheet overlap; a single
   next-action surface leaning on the existing ranked-suggestion chips. **Needs
   its own brainstorm/spec before building** — do not auto-execute blind.

## Working rules (per repo CLAUDE.md)

- Minimum code that solves the problem. Nothing speculative. Touch only what you must.
- Pure engine logic in `lib/engine/`, no Flutter imports; UI in `lib/features/`.
- Facts-only/licensing posture unchanged: custom tables ship zero vendored content
  (the user authors all rows).
- Each phase: spec/plan → TDD → `flutter analyze` + `flutter test` green → PR → merge.

## Per-phase plans

- Phase 1 — `docs/superpowers/plans/2026-06-29-custom-oracle-tables.md` (written just-in-time)
- Phases 2-6 — planned just-in-time as each predecessor merges, re-verifying against
  the then-current code (this doc's findings can themselves go stale).
