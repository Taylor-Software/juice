# Encounter Map Pin — Plan

Spec: `docs/superpowers/specs/2026-06-19-encounter-map-pin-design.md`.

## Steps

1. **Notifier** — `lib/state/providers.dart`
   - Add `EncounterNotifier.setLocation(LocationRef?)` (save `copyWith`;
     null → `clearLocationRef: true`).
   - Test first (`test/encounter_*` or wherever EncounterState is tested): link
     sets `locationRef`, `setLocation(null)` clears.

2. **Pin helper + dungeon renderer** — `lib/features/map_screen.dart`
   - Add top-level `paintEncounterPin(Canvas, Offset, Color)` (material-icon
     `TextPainter`, per spec).
   - `_DungeonPainter`: add `String? encounterRoomId`, `Color encounterColor`;
     in `paint`, stamp pin at the matching room rect's top-right;
     `shouldRepaint` compares `encounterRoomId`.
   - `DungeonMapPane._canvas`: `ref.watch(encounterProvider)`, pass
     `locationRef?.roomId` + `colorScheme.error`.
   - Painter test: `shouldRepaint` reacts to `encounterRoomId`.

3. **Hex renderer** — `lib/features/map_screen.dart`
   - `_HexPainter`: add `int? encounterCol, encounterRow`; draw pin at matching
     hex center (reuse `hexCenter`); `shouldRepaint` compares both.
   - `HexMapPane._canvas`: pass `locationRef?.hexCol` / `?.hexRow`.

4. **Writer toggles** — `lib/features/map_screen.dart`
   - `_detailCard(room)`: toggle button `dungeon-encounter-toggle` —
     set/unlink `LocationRef(roomId: r.id)` based on current `locationRef`.
   - `_hexDetailCard(hex)`: toggle `hex-encounter-toggle` —
     `LocationRef(hexCol: h.col, hexRow: h.row)`.
   - Disable while `encounterProvider.valueOrNull == null`.
   - Widget test: select room → toggle stamps `locationRef.roomId`; toggle again
     clears.

5. **Verify** — `flutter analyze` clean; `flutter test` green; web run to
   eyeball the pin (preview).

6. **Ship** — commit, PR, squash-merge.

## Risk notes

- Widget tests pumping map panes must override `oracleProvider`/`mapProvider`
  with fixtures + mock prefs (rootBundle-hang rule).
- `_DungeonPainter` is reused by the site-interior view with `currentRoomId:
  null`; pass `encounterRoomId: null` there so interiors get no stray pin.
