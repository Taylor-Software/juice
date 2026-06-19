# Encounter Map Pin — Design

## Problem

`EncounterState.locationRef` (a `LocationRef` of `roomId` OR `hexCol`/`hexRow`)
was added by the context-spine work (`2026-06-18-context-spine-verb-nav`) but is
**dead weight**: nothing writes it and nothing renders it. The "encounter happens
at this location" link and its map-side pin were both deferred (that spec's "Rich
encounter-pin-on-map UI" out-of-scope line). This closes the minimal version: a
single active encounter can be pinned to a map cell, and the map draws a marker
there.

## Scope

In:
- A writer that sets/clears `EncounterState.locationRef` from the map.
- A renderer that draws one pin on the matching dungeon room or world hex.

Out (unchanged, still deferred):
- `PlayContext.activeLocation` wiring (tap-sets-pointer, "Map opens to it"). The
  pin reads `EncounterState.locationRef` directly, not `activeLocation`.
- Multiple simultaneous encounters / multiple pins. There is one
  `EncounterState`, so one pin.
- Tap-the-pin-to-jump-to-encounter, encounter-location name on the encounter
  screen, interior/flower-view pins.

## Key decision — writer lives on the map, not the encounter screen

The encounter screen (Track → Encounter) cannot disambiguate *which* cell the
user means: `MapState` tracks the dungeon `currentRoomId` and the hex
`currentHexCol`/`currentHexRow` independently, and the encounter is a single
global object. The room/hex **detail cards** already encode exactly which cell
was tapped (`DungeonMapPaneState._detailCard(room)`,
`HexMapPaneState._hexDetailCard(hex)`), so the link toggle goes there —
unambiguous, no precedence rule needed.

## Components

### `EncounterNotifier.setLocation` — `lib/state/providers.dart`

```dart
Future<void> setLocation(LocationRef? ref) async {
  final s = await _ready;
  await save(ref == null
      ? s.copyWith(clearLocationRef: true)
      : s.copyWith(locationRef: ref));
}
```

`reset()` already drops the link (it saves a fresh `const EncounterState()`), so
no extra clear path is needed there.

### Writer toggle — `lib/features/map_screen.dart`

- `DungeonMapPaneState._detailCard(room)`: add a button row. Read
  `ref.watch(encounterProvider).valueOrNull?.locationRef`. If it already points
  at `room.id` → label "Encounter here ✓", tap calls `setLocation(null)`
  (unlink). Else → "Set encounter here", tap calls
  `setLocation(LocationRef(roomId: room.id))`.
- `HexMapPaneState._hexDetailCard(hex)`: same toggle keyed on
  `hexCol == h.col && hexRow == h.row`, setting
  `LocationRef(hexCol: h.col, hexRow: h.row)`. NOTE: the hex detail card is
  itself gated behind the `hexcrawl` opt-in (`_hexcrawlOn()`), so hex *linking*
  is only available in hexcrawl campaigns. Pin *rendering* on the hex painter is
  ungated — a link set elsewhere still draws. The dungeon room card (and its
  toggle) is ungated.
- Button keys: `dungeon-encounter-toggle`, `hex-encounter-toggle` (for tests).
- Guard: `encounterProvider.valueOrNull == null` (loading) → button disabled.

### Renderer — painters

The active encounter's `locationRef` is split into painter inputs:
- `_DungeonPainter` gains `String? encounterRoomId`. The `DungeonMapPane`
  `_canvas` passes `encounter.locationRef?.roomId`. In `paint`, after drawing a
  room, if `r.id == encounterRoomId`, stamp a pin marker in the room rect's
  top-right.
- `_HexPainter` gains `int? encounterCol, int? encounterRow`. `HexMapPane`
  `_canvas` passes `locationRef?.hexCol` / `?.hexRow`. In `paint`, the cell whose
  `(col, row)` matches gets the same marker at its hex center.
- Both panes already `ref.watch(encounterProvider)` (they are `ConsumerState`);
  add the watch and thread the value into the painter.
- `shouldRepaint` for each painter compares the new field(s).

**Pin marker** — a shared `paintEncounterPin(Canvas, Offset center, Color)`
helper (top of `map_screen.dart`). Reuse the existing `TextPainter` approach (the
dungeon painter already lays out room-label text) to draw a material icon
codepoint:

```dart
void paintEncounterPin(Canvas canvas, Offset center, Color color) {
  const icon = Icons.local_fire_department;
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 18,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}
```

Colour: `Theme.of(context).colorScheme.error` (or the existing `scheme` the
hex painter already receives), passed into the painter so it reads correctly in
light/dark.

## Data flow

Map detail card toggle → `EncounterNotifier.setLocation(ref)` → persisted
`EncounterState.locationRef`. Map pane `_canvas` watches `encounterProvider`,
threads `locationRef` into the painter → marker drawn on the matching cell.

## Error / edge handling

- Toggle while encounter still loading → button disabled (no null deref).
- `locationRef` points at a room/hex not on the current map (e.g. dungeon
  regenerated) → no cell matches → nothing drawn. No crash; the stale link is
  harmless and can be re-set or cleared by `reset()`.
- A `roomId`-typed link viewed on the hex pane (or vice-versa) → no match on that
  pane → no pin. Each pane only renders its own ref kind.

## Testing

- **Notifier** (`encounter` test): `setLocation(LocationRef(roomId: 'r1'))` sets
  it; `setLocation(null)` clears; survives `toJson`/`fromJson` round-trip
  (round-trip itself already covered by the context-spine tests).
- **Painter**: `_DungeonPainter.shouldRepaint` returns true when
  `encounterRoomId` changes; `_HexPainter.shouldRepaint` reacts to
  `encounterCol`/`encounterRow`.
- **Widget** (`map_screen` test): select a room → tap `dungeon-encounter-toggle`
  → `encounterProvider` `locationRef.roomId` equals the room; tapping again
  clears it. (Pump `DungeonMapPane` with `mapProvider` seeded with rooms +
  `oracleProvider` overridden, per the rootBundle-hang fixture rule.)

## Rollout

Pre-release; no migration. `locationRef` JSON is already tolerant
(absent → null).
