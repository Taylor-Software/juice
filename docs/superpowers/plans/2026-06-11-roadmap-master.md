# Roadmap Implementation Master Plan

> **For agentic workers:** This is a sequencing index, not an executable plan.
> Execute the linked plans in order; author the missing plans only when their
> predecessors ship (roadmap rule: don't reshuffle mid-item, nothing
> speculative).

**Goal:** Implement ROADMAP.md phase by phase, one working release per plan.

| # | Roadmap item | Plan | Status |
|---|---|---|---|
| 1 | Web deploy + CI | [2026-06-11-web-deploy-ci.md](2026-06-11-web-deploy-ci.md) | shipped (PR #1) |
| 2 | Re-verify BEST-EFFORT tables (monster grid, dialog grid) | [2026-06-11-table-verification.md](2026-06-11-table-verification.md) | shipped (PR #2) |
| 3 | Stateful crawl modes | author after #2 — reuse the DialogState pattern #2 introduces | — |
| 4 | Sessions (multi-campaign) | author after #3 | — |
| 5 | Campaign file save/open (BYO cloud) | author after #4 (shared JSON schema) | — |
| 6 | Mythic GME core spike | author after #4 (chaos is per-session state) | — |
| 7+ | Later items (journal depth, Mythic full, Ironsworn family per `docs/specs/ironsworn-family.md`, icons, PWA) | author when promoted into Next | — |

Constraints that bind every plan:
- `flutter analyze` + `flutter test` green before every commit (CONVENTIONS.md).
- `build_oracle.py` and `lib/engine/oracle.dart` change together, re-verified
  (CLAUDE.md).
- Doc updates land in the same commit as the code they describe.
- Stack stays `flutter_riverpod` + `shared_preferences` until a plan
  explicitly justifies an addition.

Source material note: plans #2 and #3 read the Juice PDF + instructions from
the juice-roll reference clone. If `/tmp/juice-roll` is gone, re-clone first:

```bash
git clone --depth 1 https://github.com/johnkord/juice-roll /tmp/juice-roll
```
