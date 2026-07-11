# Loop Steps Visibility — plan

Spec: `docs/superpowers/specs/2026-07-11-loop-steps-visibility-design.md`

1. `lib/features/loop_bar.dart`
   - Steps `ExpansionTile`: `expandedCrossAxisAlignment:
     CrossAxisAlignment.stretch`, `childrenPadding:
     EdgeInsets.fromLTRB(12, 0, 12, 8)`.
   - `PlayScreen` → `ConsumerStatefulWidget` owning a `ScrollController`;
     wrap the capped `SingleChildScrollView` in
     `Scrollbar(thumbVisibility: true)` sharing that controller.
2. Tests: extend `test/loop_bar_test.dart` (step-card width ≈ viewport
   width after expanding) and `test/play_screen_layout_test.dart`
   (Scrollbar present when expanded; steps reachable by drag).
3. `flutter analyze` + full suite; live web spot-check.
4. CLAUDE.md loop bullet note; ship via `/ship-pr`, squash-merge.
