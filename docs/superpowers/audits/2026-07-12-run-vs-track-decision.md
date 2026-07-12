# Run-vs-Track overlap — decision record

**Date:** 2026-07-12
**Context:** the 2026-07-12 QoL/UI assessment flagged that post-solo-refocus
(#253–#258) the Run dashboard and the Track panes show overlapping content
(encounter, threads/rumors glance, scene, dice), and asked whether six verbs
is too many for a solo journaling app.

## Decision: keep the Run verb (for now)

- Run is a **glance surface** (read-and-act dashboard: initiative, party HP,
  scene + chaos, dice with inline interpret, capture); Track is the **edit
  surface** (full CRUD panes). The overlap is by design — the same state at
  two altitudes — and removing Run would push mid-encounter play back into
  tab-hopping, which the GM-live-table work (#195/#232) existed to fix.
- The subtraction that WAS clearly right shipped instead: the Track bar
  dropped two tabs (#292 — Tasks→Threads, People+Places→World), which was
  the concrete navigational pain.
- Revisit trigger: the wedge Phase-4 stranger test with real humans. If no
  solo player reaches for Run (it originated as a GM surface), fold its
  unique panels (initiative glance, pacing dice row) into Track→Encounter and
  retire the verb. That check belongs to the "items no stranger reached for"
  kill-list already queued in the stranger-test audit.
