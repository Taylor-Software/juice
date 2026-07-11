# Scene Seed in the New-Scene Dialog — plan

Spec: `docs/superpowers/specs/2026-07-11-scene-seed-design.md`

1. `lib/features/loop_bar.dart` `_newScene`: await
   `oracleProvider.future`; dialog content becomes a min Column of the
   title field + a `loop-scene-seed` "Roll a seed" TextButton.icon that
   writes `oracle.newScene()`'s summary into the controller.
2. Test in `test/loop_bar_test.dart`: open the dialog, tap the seed, field
   non-empty, Create → journal has a scene with that title.
3. `flutter analyze` + full suite; ship via `/ship-pr`, squash-merge; note
   in CLAUDE.md's loop bullet.
