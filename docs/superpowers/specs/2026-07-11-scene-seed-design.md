# Scene Seed in the New-Scene Dialog — design

**Date:** 2026-07-11
**Source:** tool-evaluation audit F6 / enhancement 5
(`docs/superpowers/audits/2026-07-11-tool-evaluation-audit.md`).

## Problem

The loop's New-scene dialog (Next beat → "Name the scene", `_newScene` in
`lib/features/loop_bar.dart`) is a bare title field. The scene generator
(`Oracle.newScene()`), the word oracle, and kit starter scenes all exist —
but none is offered at the one moment a stranger stares at "Scene title…"
with nothing to say. The Scenes pane's separate "Generate" button is three
taps away in another verb.

## Design

Add a **"Roll a seed"** chip (`loop-scene-seed`, `TextButton.icon` with the
auto_awesome icon) inside the dialog, under the title field. Tapping fills
the field with `oracle.newScene()`'s summary (same generator the Scenes
pane uses); tapping again rerolls. The user can edit before Create. Oracle
is awaited via `oracleProvider.future` before the dialog opens (the cold
`.valueOrNull` first-tap gotcha).

No new generator, no journal side effects from rolling the seed (only
Create logs the scene divider, unchanged).

## Success criteria

- Next beat → Name the scene → Roll a seed fills the title; reroll changes
  it; Create logs a scene with the seeded title.
- Widget test covers seed-fill + create; full suite green.
