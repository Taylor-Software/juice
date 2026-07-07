# Classic Dungeon Generator (Roll 4 Ruin, P1) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in `classic-dungeon` campaign system that turns the Map → Dungeon pane into a Roll 4 Ruin room-by-room crawler: shape-accurate multi-cell rooms placed by directed door-to-door exploration, depth-scaled monster/treasure, and tracked monster factions.

**Architecture:** A data rail (`build_dungeon.py` → `assets/dungeon_data.json`) is the source of truth for all table text (CC-BY-NC-SA-4.0, attributed). A pure `lib/engine/dungeon/` package holds footprint geometry, placement, faction state, and the 4D6 generator. `DungeonRoom` grows an optional footprint/doors/roomType (single-cell default = today's base pane, unchanged). A footprint-aware painter + door-tap exploration extends `map_screen.dart`, gated on the system flag.

**Tech Stack:** Dart/Flutter, `flutter_riverpod`, `shared_preferences`, `package:test`/`flutter_test`; Python 3 for the build rail. No new dependencies.

**Source spec:** `docs/superpowers/specs/2026-07-06-classic-dungeon-generator-design.md`. Source PDF: `Roll4Ruin_2.1_NocturnalPeacock.pdf` (dungeon branch = pages 2–4 tables A–C; monsters = page 8 tables G; build elements = page 9 tables H).

**Conventions to follow (verify by reading the cited file before you start a phase):**
- Dice: `lib/engine/dice.dart` — `Dice.dN(n)` returns 1..n. Seed determinism in tests with `Dice(Random(seed))`.
- Result text: `GenResult{title, List<Roll> rolls, summary}` in `lib/engine/models.dart:72`; `Roll{label, display}`; `.asText` joins `label: display` lines.
- Data providers: `FutureProvider` + `rootBundle.loadString('assets/…')`, e.g. `lib/state/providers.dart:44` (`oracleProvider`) and `:2141` (`rulesetProvider.family`).
- Session-scoped persistence: `sessionScopedKeys` list at `lib/state/providers.dart:1696`; a session AsyncNotifier persisting to `<base>.<sessionId>` — pattern in `DecksNotifier` (base `juice.decks.v1`).
- Build-rail precedent: `build_hexcrawl.py` (authored literals + structural self-check, `python3 build_hexcrawl.py`, copy JSON to `assets/`).
- Widget-test hang recipe: override oracle/verdant/emulator/ruleset AND the new dungeon-data provider with file fixtures + `SharedPreferences.setMockInitialValues`; never call `*.load()` in tests. See `test/` existing map tests.
- Format only files you edit (`dart format <file>`); never repo-wide (see the dart-format-collateral note).

---

## Phase 1a — Data rail: `build_dungeon.py` + `dungeon_data.json` + loader

### Task 1: JSON schema + build script skeleton with self-check

**Files:**
- Create: `build_dungeon.py`
- Create (generated): `assets/dungeon_data.json`

- [ ] **Step 1: Write `build_dungeon.py` skeleton** with the schema, a few worked table rows, and the self-check. Transcribe the remaining rows from the PDF pages cited in each table's comment during this step — the self-check is the correctness gate.

```python
#!/usr/bin/env python3
"""Roll 4 Ruin (Nocturnal Peacock, CC-BY-NC-SA-4.0) dungeon-branch tables ->
assets/dungeon_data.json. This script is the SOURCE OF TRUTH; never hand-edit
the emitted JSON. Rerun: python3 build_dungeon.py && cp dungeon_data.json assets/

Cross-references to other tables are encoded as the token "{ref:XX}" inside a
row string (e.g. "Chest {ref:H5}"). Tables in the P2 cave/natural set (prefixes
I, E and the D-F rooms) are NOT shipped in P1; a row referencing them keeps a
plain label and drops the token via LABEL_FALLBACKS so the P1 resolver renders
text, not an expansion.
"""
import json, re, sys

# --- P2-only ref prefixes: rendered as their plain label in P1 ---------------
P2_REF_PREFIXES = ("I", "E", "D", "F")
LABEL_FALLBACKS = {  # ref id -> P1 display label (extend as rows demand)
    "I6": "flora", "I7": "liquid", "I8": "gas", "I3": "vein", "E4": "obstacle",
    "E5": "cavestone", "G7": "fauna",
}

# --- A1 Dungeon Entrance (D12), page 2 ---------------------------------------
A1 = [  # index 0 == roll 1
    "In a magical archway portal", "Under weird alienlike ruins",
    "In overgrown formations", "Under temple ruins", "Under tower ruins",
    "Between ruined archways", "Between rocks", "At the bottom of a crater",
    "Stairs under a big statue", "In fortress ruins", "In the side of a hill",
    "Roll again",  # 12 -> reroll (resolver treats as reroll)
]

# --- A2 Dungeon Type (2D6), page 2. effect = structured modifier or note -----
# keys: name, and one of {note} | {tier_bump,int} | {treasure_bonus,int}
#       | {stock_double,bool} | {leads_to_caves,bool}
A2 = {  # 2..12
    "2":  {"name": "Vault", "stock_double": True,
           "note": "Monsters & treasure doubled."},
    "3":  {"name": "Arcane lair", "note": "Halls transformed by arcane effects."},
    "4":  {"name": "Forgotten ruins", "note": "Roll D12 for monster stocking."},
    "5":  {"name": "Overgrown ruins", "note": "6 on stocking -> D4 flora & fauna."},
    "6":  {"name": "Catacombs", "note": "6 on stocking -> D4 burial alcoves."},
    "7":  {"name": "Ruins", "note": "A former community, now in ruins."},
    "8":  {"name": "Stronghold", "note": "6 on stocking -> a barricade."},
    "9":  {"name": "Temple", "note": "6 on stocking -> 1/6 chance of a shrine."},
    "10": {"name": "Cursed ruins", "tier_bump": 1, "treasure_bonus": 3,
           "note": "Monster stocking begins at central levels; treasure +3."},
    "11": {"name": "Transformed ruins", "note": "Roll an obstacle for the room."},
    "12": {"name": "Ancient ruin", "leads_to_caves": True,
           "note": "6 on stocking -> openings lead to caves (P2)."},
}

# --- B2 Corridor Stocking (D6), page 3 ---------------------------------------
B2 = [  # roll 1..6
    "Monster + (2/6) Feature {ref:B3}", "Feature {ref:B3}", "Trap {ref:B4}",
    "Change of door type {ref:B5}", "Nothing", "Nothing (or Type effect)",
]
# --- B5 Door Types (D10), page 3 ---------------------------------------------
B5 = ["Wooden", "Rusty metal", "Smooth stone", "Metal plates", "Portcullis",
      "Grating", "Rotting wood", "Engraved metal", "Engraved stone",
      "Ironbound wooden"]
# --- C2 Chamber Stocking (D6), page 4 ----------------------------------------
C2 = [
    "Feature {ref:C3} + Monster", "Feature {ref:C3} + Monster + Treasure {ref:H8}",
    "Feature {ref:C3} + Treasure {ref:H8}", "Feature {ref:C3}",
    "Feature {ref:C3} + Special {ref:C4}", "Nothing (or Type effect)",
]
# --- G1 Reaction (2D6), page 8 -----------------------------------------------
G1 = {  # 2..12
    "2": "Immediate ambush", "3": "Hostile/Engage", "4": "Hostile/Alert",
    "5": "Hostile/Threaten", "6": "Uncertain/Threaten", "7": "Uncertain/Suspicious",
    "8": "Uncertain/Confused", "9": "Neutral/Curious", "10": "Neutral/Unaware",
    "11": "Interested/Unaware", "12": "Friendly/Inactive",
}
# --- G2 Upper-level monsters (D20), page 8. "organized" flags faction rows ----
# each row: {text, count, organized}
G2 = [
    {"text": "Insect Swarm", "count": "D4", "organized": False},
    {"text": "Giant Rat", "count": "2D6", "organized": False},
    # ... transcribe rows 3..20 from page 8 (Goblins/Bandits/Kobolds/etc are
    #     organized=True; vermin/molds/oozes organized=False) ...
]
# TODO-DURING-STEP-1: transcribe the full literals for the tables below from the
# cited PDF pages, following the shapes above:
#   B3 (D20, p3), B4 trigger (D8) + effect (D12) (p3),
#   C3 (D20, p4), C4 (D20, p4), C5 (D6, p4),
#   G3 (D20 p8), G4 (D20 p8), G5 (D12/D20 p8), G6 (D12/D20 p8), G7 (D20 p8),
#   H1 coffins, H2 statues, H3 secret room, H4 containers, H5 chests,
#   H6 shrine, H7 frescos, H8 treasure (all p9).
# Keep {ref:XX} tokens verbatim; do not expand here.

# --- Authored (ours): faction name pool + shape-family range maps ------------
FACTION_NAMES = [  # original, facts-only; no vendored content
    "Rotfangs", "Ashclaw Pack", "The Gloomwardens", "Bonepickers",
    "Iron Maw", "The Hollow Court", "Grislefolk", "The Ninth Tally",
    "Murkeye Clan", "The Sundered Hand", "Cinder Kin", "The Pale Circle",
]
# D66 roll -> shape family. Keys are family ids the Dart catalog also declares.
CORRIDOR_FAMILIES = {  # inclusive d66 ranges; must cover 11..66
    "straight": [[11, 22]], "l-bend": [[23, 34]], "t-junction": [[35, 44]],
    "cross": [[45, 52]], "offset": [[53, 62]], "long": [[63, 66]],
}
CHAMBER_FAMILIES = {
    "small": [[11, 22]], "medium": [[23, 36]], "large": [[41, 52]],
    "round": [[53, 56]], "cross": [[61, 64]], "l-room": [[65, 66]],
}

def d66_covered(fam):
    seen = set()
    for ranges in fam.values():
        for lo, hi in ranges:
            for tens in range(lo // 10, hi // 10 + 1):
                for ones in range(1, 7):
                    v = tens * 10 + ones
                    if lo <= v <= hi and 1 <= ones <= 6:
                        seen.add(v)
    want = {t * 10 + o for t in range(1, 7) for o in range(1, 7)}
    return seen == want

REF_RE = re.compile(r"\{ref:([A-Z]\d+)\}")

def all_ref_ids(*tables):
    ids = set()
    def scan(x):
        if isinstance(x, str):
            ids.update(REF_RE.findall(x))
        elif isinstance(x, dict):
            for v in x.values(): scan(v)
        elif isinstance(x, list):
            for v in x: scan(v)
    for t in tables: scan(t)
    return ids

def build():
    data = {
        "_license": "Roll 4 Ruin: Classic Dungeon Generator (c) Nocturnal "
                    "Peacock, CC-BY-NC-SA-4.0.",
        "A1": A1, "A2": A2, "B2": B2, "B5": B5, "C2": C2, "G1": G1, "G2": G2,
        # ... add B3,B4,C3,C4,C5,G3,G4,G5,G6,G7,H1..H8 once transcribed ...
        "faction_names": FACTION_NAMES,
        "corridor_families": CORRIDOR_FAMILIES,
        "chamber_families": CHAMBER_FAMILIES,
        "label_fallbacks": LABEL_FALLBACKS,
    }
    verify(data)
    return data

def verify(data):
    errs = []
    # row-count checks
    if len(data["A1"]) != 12: errs.append("A1 must have 12 rows")
    if set(data["A2"]) != {str(i) for i in range(2, 13)}: errs.append("A2 2..12")
    if set(data["G1"]) != {str(i) for i in range(2, 13)}: errs.append("G1 2..12")
    for k, n in [("B2", 6), ("B5", 10), ("C2", 6)]:
        if len(data[k]) != n: errs.append(f"{k} must have {n} rows")
    # d66 family coverage
    if not d66_covered(data["corridor_families"]): errs.append("corridor d66 gap")
    if not d66_covered(data["chamber_families"]): errs.append("chamber d66 gap")
    # every ref token targets a known table OR a P2 fallback label
    known = {"B3", "B4", "B5", "C3", "C4", "C5",
             "H1", "H2", "H3", "H4", "H5", "H6", "H7", "H8"}
    for rid in all_ref_ids(data["B2"], data["C2"]):
        if rid not in known and rid not in data["label_fallbacks"]:
            errs.append(f"unknown ref {rid}")
    if errs:
        print("SELF-CHECK FAILED:", *errs, sep="\n  "); sys.exit(1)
    print("self-check OK")

if __name__ == "__main__":
    d = build()
    with open("dungeon_data.json", "w") as f:
        json.dump(d, f, indent=2, ensure_ascii=False)
    print("wrote dungeon_data.json")
```

- [ ] **Step 2: Transcribe the remaining tables** (B3, B4, C3, C4, C5, G3–G7, H1–H8) from the cited PDF pages into the script, keeping `{ref:XX}` tokens verbatim, then add them to the `data` dict and extend `verify()` with their row-count checks (B3=20, B4 trigger=8/effect=12, C3=20, C4=20, C5=6, G3/G4/G5/G6/G7=20, H5/H4=20, H8 GP-form=4). Mark each transcribed table's source page in a comment.

- [ ] **Step 3: Run the build and self-check**

Run: `python3 build_dungeon.py`
Expected: `self-check OK` then `wrote dungeon_data.json`, exit 0.

- [ ] **Step 4: Copy into assets**

Run: `cp dungeon_data.json assets/`
Expected: `assets/dungeon_data.json` exists.

- [ ] **Step 5: Register the asset** in `pubspec.yaml` under `flutter: assets:` (add `assets/dungeon_data.json` next to the other `assets/*.json`; read the existing block first — many are covered by an `assets/` dir entry, in which case no edit is needed). Run `flutter pub get`.

- [ ] **Step 6: Commit**

```bash
git add build_dungeon.py assets/dungeon_data.json pubspec.yaml pubspec.lock
git commit -m "feat(dungeon): Roll 4 Ruin table data rail (build_dungeon.py)"
```

### Task 2: Typed loader `dungeon_tables.dart` + provider

**Files:**
- Create: `lib/engine/dungeon/tables.dart`
- Modify: `lib/state/providers.dart` (add `dungeonDataProvider`)
- Test: `test/dungeon/tables_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/tables.dart';

void main() {
  test('parses shipped dungeon_data.json', () {
    final raw = File('assets/dungeon_data.json').readAsStringSync();
    final t = DungeonTables.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    expect(t.a1.length, 12);
    expect(t.a2['7']!.name, 'Ruins');
    expect(t.reaction['2'], 'Immediate ambush');
    expect(t.corridorFamilies.keys, contains('straight'));
    expect(t.factionNames, isNotEmpty);
  });
}
```

- [ ] **Step 2: Run it, expect FAIL** (`tables.dart` missing).

Run: `flutter test test/dungeon/tables_test.dart`
Expected: FAIL (uri doesn't exist).

- [ ] **Step 3: Implement `tables.dart`**

```dart
/// Typed view over assets/dungeon_data.json (Roll 4 Ruin, CC-BY-NC-SA-4.0).
/// Pure: no Flutter, no I/O. Tolerant of missing optional tables (P1 ships a
/// subset; unknown keys are simply absent).
library;

class A2Type {
  const A2Type({required this.name, this.note = '', this.tierBump = 0,
      this.treasureBonus = 0, this.stockDouble = false, this.leadsToCaves = false});
  final String name;
  final String note;
  final int tierBump;
  final int treasureBonus;
  final bool stockDouble;
  final bool leadsToCaves;

  factory A2Type.fromJson(Map<String, dynamic> j) => A2Type(
        name: j['name'] as String? ?? '',
        note: j['note'] as String? ?? '',
        tierBump: (j['tier_bump'] as num?)?.toInt() ?? 0,
        treasureBonus: (j['treasure_bonus'] as num?)?.toInt() ?? 0,
        stockDouble: j['stock_double'] as bool? ?? false,
        leadsToCaves: j['leads_to_caves'] as bool? ?? false,
      );
}

class MonsterRow {
  const MonsterRow({required this.text, required this.count, required this.organized});
  final String text;
  final String count; // dice notation e.g. "2D6"
  final bool organized;
  factory MonsterRow.fromJson(Map<String, dynamic> j) => MonsterRow(
      text: j['text'] as String, count: j['count'] as String? ?? '1',
      organized: j['organized'] as bool? ?? false);
}

class DungeonTables {
  const DungeonTables({
    required this.a1, required this.a2, required this.b2, required this.b5,
    required this.c2, required this.reaction, required this.upperMonsters,
    required this.factionNames, required this.corridorFamilies,
    required this.chamberFamilies, required this.labelFallbacks, required this.raw,
  });

  final List<String> a1;
  final Map<String, A2Type> a2;
  final List<String> b2;
  final List<String> b5;
  final List<String> c2;
  final Map<String, String> reaction;          // G1
  final List<MonsterRow> upperMonsters;         // G2
  final List<String> factionNames;
  final Map<String, List<List<int>>> corridorFamilies;
  final Map<String, List<List<int>>> chamberFamilies;
  final Map<String, String> labelFallbacks;
  final Map<String, dynamic> raw;               // for tables added later (B3/C3/H*)

  static List<String> _strs(dynamic v) =>
      (v as List? ?? const []).map((e) => e.toString()).toList();
  static Map<String, List<List<int>>> _fam(dynamic v) => {
        for (final e in (v as Map? ?? const {}).entries)
          e.key as String: [
            for (final r in e.value as List)
              [(r as List)[0] as int, r[1] as int]
          ]
      };

  factory DungeonTables.fromJson(Map<String, dynamic> j) => DungeonTables(
        a1: _strs(j['A1']),
        a2: {
          for (final e in (j['A2'] as Map).entries)
            e.key as String: A2Type.fromJson((e.value as Map).cast())
        },
        b2: _strs(j['B2']),
        b5: _strs(j['B5']),
        c2: _strs(j['C2']),
        reaction: (j['G1'] as Map).map((k, v) => MapEntry(k as String, v.toString())),
        upperMonsters: [
          for (final r in (j['G2'] as List? ?? const []))
            MonsterRow.fromJson((r as Map).cast())
        ],
        factionNames: _strs(j['faction_names']),
        corridorFamilies: _fam(j['corridor_families']),
        chamberFamilies: _fam(j['chamber_families']),
        labelFallbacks:
            (j['label_fallbacks'] as Map? ?? const {}).map((k, v) => MapEntry(k as String, v.toString())),
        raw: j,
      );
}
```

- [ ] **Step 4: Run it, expect PASS.**

Run: `flutter test test/dungeon/tables_test.dart`
Expected: PASS.

- [ ] **Step 5: Add the provider** in `lib/state/providers.dart` (near `oracleProvider`):

```dart
final dungeonDataProvider = FutureProvider<DungeonTables>((ref) async {
  final raw = await rootBundle.loadString('assets/dungeon_data.json');
  return DungeonTables.fromJson(jsonDecode(raw) as Map<String, dynamic>);
});
```
Add `import '../engine/dungeon/tables.dart';` (top of file, alphabetical among engine imports).

- [ ] **Step 6: Commit**

```bash
git add lib/engine/dungeon/tables.dart lib/state/providers.dart test/dungeon/tables_test.dart
git commit -m "feat(dungeon): typed dungeon_data loader + provider"
```

---

## Phase 1b — Geometry: footprints + placement

### Task 3: `footprint.dart` — model, rotation, authored catalog

**Files:**
- Create: `lib/engine/dungeon/footprint.dart`
- Test: `test/dungeon/footprint_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';

void main() {
  test('rotate 4 quarter-turns is identity', () {
    final f = const RoomFootprint(
      family: 'l-bend', cells: [(0, 0), (0, 1), (1, 1)],
      openings: [Opening((0, 0), Side.n), Opening((1, 1), Side.e)]);
    var r = f;
    for (var i = 0; i < 4; i++) r = r.rotate(1);
    expect(r.normalizedCells.toSet(), f.normalizedCells.toSet());
    expect(r.openings.map((o) => o.side).toSet(),
        f.openings.map((o) => o.side).toSet());
  });

  test('rotate 1 turns North opening to East', () {
    final f = const RoomFootprint(
      family: 'straight', cells: [(0, 0)], openings: [Opening((0, 0), Side.n)]);
    expect(f.rotate(1).openings.single.side, Side.e);
  });

  test('every catalog family in the JSON range maps has >=1 footprint', () {
    for (final fam in kCorridorShapes.keys) {
      expect(kCorridorShapes[fam], isNotEmpty, reason: fam);
    }
    for (final fam in kChamberShapes.keys) {
      expect(kChamberShapes[fam], isNotEmpty, reason: fam);
    }
  });
}
```

- [ ] **Step 2: Run it, expect FAIL.**

Run: `flutter test test/dungeon/footprint_test.dart`
Expected: FAIL (uri missing).

- [ ] **Step 3: Implement `footprint.dart`**

```dart
/// Pure grid geometry for classic-dungeon rooms. A footprint is a set of cell
/// offsets plus authored OPENINGS (which sides can connect). Door KIND is not
/// stored here — the generator assigns it from the type die (see spec).
library;

enum Side { n, e, s, w }

Side _rotSide(Side s) => switch (s) { // one clockwise quarter-turn
      Side.n => Side.e, Side.e => Side.s, Side.s => Side.w, Side.w => Side.n,
    };

Side oppositeSide(Side s) => switch (s) {
      Side.n => Side.s, Side.s => Side.n, Side.e => Side.w, Side.w => Side.e,
    };

class Opening {
  const Opening(this.cell, this.side);
  final (int, int) cell;
  final Side side;
}

enum DoorKind { locked, door, open }

class DoorEdge {
  const DoorEdge(this.cell, this.side, this.kind);
  final (int, int) cell;
  final Side side;
  final DoorKind kind;
  Map<String, dynamic> toJson() =>
      {'x': cell.$1, 'y': cell.$2, 's': side.index, 'k': kind.index};
  factory DoorEdge.fromJson(Map<String, dynamic> j) => DoorEdge(
      (j['x'] as int, j['y'] as int), Side.values[j['s'] as int],
      DoorKind.values[j['k'] as int]);
}

class RoomFootprint {
  const RoomFootprint(
      {required this.family, required this.cells, required this.openings});
  final String family;
  final List<(int, int)> cells;
  final List<Opening> openings;

  /// Clockwise quarter-turn: (x,y) -> (-y, x); sides rotate with it.
  RoomFootprint rotate(int quarterTurns) {
    var f = this;
    for (var i = 0; i < (quarterTurns % 4); i++) {
      f = RoomFootprint(
        family: f.family,
        cells: [for (final c in f.cells) (-c.$2, c.$1)],
        openings: [for (final o in f.openings) Opening((-o.cell.$2, o.cell.$1), _rotSide(o.side))],
      );
    }
    return f;
  }

  /// Cells shifted so min x/y == 0 (rotation can push them negative).
  List<(int, int)> get normalizedCells {
    final minX = cells.map((c) => c.$1).reduce((a, b) => a < b ? a : b);
    final minY = cells.map((c) => c.$2).reduce((a, b) => a < b ? a : b);
    return [for (final c in cells) (c.$1 - minX, c.$2 - minY)];
  }
}

/// Authored corridor catalog. Family ids MUST match corridor_families in the
/// JSON range map. Openings are on the sides the zine shape shows arrows.
const kCorridorShapes = <String, List<RoomFootprint>>{
  'straight': [
    RoomFootprint(family: 'straight', cells: [(0, 0), (0, 1)],
        openings: [Opening((0, 0), Side.n), Opening((0, 1), Side.s)]),
  ],
  'l-bend': [
    RoomFootprint(family: 'l-bend', cells: [(0, 0), (0, 1), (1, 1)],
        openings: [Opening((0, 0), Side.n), Opening((1, 1), Side.e)]),
  ],
  't-junction': [
    RoomFootprint(family: 't-junction', cells: [(0, 0), (1, 0), (2, 0), (1, 1)],
        openings: [Opening((0, 0), Side.w), Opening((2, 0), Side.e), Opening((1, 1), Side.s)]),
  ],
  'cross': [
    RoomFootprint(family: 'cross', cells: [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)],
        openings: [Opening((1, 0), Side.n), Opening((0, 1), Side.w), Opening((2, 1), Side.e), Opening((1, 2), Side.s)]),
  ],
  'offset': [
    RoomFootprint(family: 'offset', cells: [(0, 0), (0, 1), (1, 1), (1, 2)],
        openings: [Opening((0, 0), Side.n), Opening((1, 2), Side.s)]),
  ],
  'long': [
    RoomFootprint(family: 'long', cells: [(0, 0), (0, 1), (0, 2), (0, 3)],
        openings: [Opening((0, 0), Side.n), Opening((0, 3), Side.s)]),
  ],
};

/// Authored chamber catalog. Family ids MUST match chamber_families in the JSON.
const kChamberShapes = <String, List<RoomFootprint>>{
  'small': [
    RoomFootprint(family: 'small', cells: [(0, 0), (1, 0), (0, 1), (1, 1)],
        openings: [Opening((0, 0), Side.w), Opening((1, 0), Side.n), Opening((1, 1), Side.e)]),
  ],
  'medium': [
    RoomFootprint(family: 'medium', cells: [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1)],
        openings: [Opening((0, 0), Side.w), Opening((2, 0), Side.e), Opening((1, 1), Side.s)]),
  ],
  'large': [
    RoomFootprint(family: 'large', cells: [
      (0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2)],
        openings: [Opening((1, 0), Side.n), Opening((0, 1), Side.w), Opening((2, 1), Side.e), Opening((1, 2), Side.s)]),
  ],
  'round': [
    RoomFootprint(family: 'round', cells: [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)],
        openings: [Opening((1, 0), Side.n), Opening((1, 2), Side.s), Opening((0, 1), Side.w)]),
  ],
  'cross': [
    RoomFootprint(family: 'cross', cells: [
      (1, 0), (0, 1), (1, 1), (2, 1), (1, 2)],
        openings: [Opening((1, 0), Side.n), Opening((0, 1), Side.w), Opening((2, 1), Side.e), Opening((1, 2), Side.s)]),
  ],
  'l-room': [
    RoomFootprint(family: 'l-room', cells: [(0, 0), (1, 0), (0, 1), (0, 2), (1, 2)],
        openings: [Opening((1, 0), Side.e), Opening((1, 2), Side.e)]),
  ],
};

/// Maps a D66 roll (11..66) to a family id via the JSON range map, then returns
/// the candidate footprints for that family. [rangeMap] is corridorFamilies or
/// chamberFamilies from DungeonTables; [catalog] the matching kCorridor/Chamber.
List<RoomFootprint> shapesForRoll(
    int d66, Map<String, List<List<int>>> rangeMap,
    Map<String, List<RoomFootprint>> catalog) {
  for (final e in rangeMap.entries) {
    for (final r in e.value) {
      if (d66 >= r[0] && d66 <= r[1]) return catalog[e.key] ?? const [];
    }
  }
  return catalog.values.first; // defensive: covered map never reaches here
}
```

- [ ] **Step 4: Run it, expect PASS.**

Run: `flutter test test/dungeon/footprint_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/dungeon/footprint.dart test/dungeon/footprint_test.dart
git commit -m "feat(dungeon): footprint model, rotation, authored shape catalog"
```

### Task 4: `placement.dart` — rotate+fit a footprint against occupied cells

**Files:**
- Create: `lib/engine/dungeon/placement.dart`
- Test: `test/dungeon/placement_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';
import 'package:juice_oracle/engine/dungeon/placement.dart';

void main() {
  test('places a straight corridor south of an existing cell, no overlap', () {
    final occupied = {(0, 0)};
    // We explored the SOUTH opening of the room at (0,0): edge cell (0,0) side s.
    final p = placeRoom(occupied, (cell: (0, 0), side: Side.s),
        kCorridorShapes['straight']!, Dice(Random(1)));
    expect(p, isNotNull);
    // no placed cell collides with occupied
    expect(p!.cells.toSet().intersection(occupied), isEmpty);
    // the entry door mates the explored edge: its opposite side faces north
    expect(p.entryDoor.side, Side.n);
    // entry cell is directly south of (0,0)
    expect(p.entryDoor.cell, (0, 1));
  });

  test('returns null when fully boxed in', () {
    final occupied = {(0, 0), (0, 1), (0, 2), (1, 1), (-1, 1)};
    final p = placeRoom(occupied, (cell: (0, 1), side: Side.s),
        kCorridorShapes['long']!, Dice(Random(1)));
    // a long 1x4 corridor south of (0,1) collides at (0,2); no rotation fits.
    expect(p, isNull);
  });
}
```

- [ ] **Step 2: Run it, expect FAIL.**

Run: `flutter test test/dungeon/placement_test.dart`
Expected: FAIL (uri missing).

- [ ] **Step 3: Implement `placement.dart`**

```dart
/// Pure placement: rotate + translate a footprint so one of its openings mates
/// the explored door edge, without overlapping occupied cells. Deterministic
/// under a seeded [Dice].
library;

import '../dice.dart';
import 'footprint.dart';

class Placement {
  const Placement({required this.cells, required this.entryDoor, required this.openDoors});
  final List<(int, int)> cells;      // absolute grid cells
  final DoorEdge entryDoor;          // the edge back to the room we came from
  final List<DoorEdge> openDoors;    // remaining openings, kind == open
}

/// The neighbor cell across [side] from [cell].
(int, int) _across((int, int) cell, Side side) => switch (side) {
      Side.n => (cell.$1, cell.$2 - 1),
      Side.s => (cell.$1, cell.$2 + 1),
      Side.e => (cell.$1 + 1, cell.$2),
      Side.w => (cell.$1 - 1, cell.$2),
    };

/// [fromDoor] is the explored opening on the SOURCE room (its world cell+side).
/// The new room must present an opening on the OPPOSITE side, and the cell
/// carrying that opening must sit in `_across(fromDoor.cell, fromDoor.side)`.
Placement? placeRoom(
  Set<(int, int)> occupied,
  ({(int, int) cell, Side side}) fromDoor,
  List<RoomFootprint> candidates,
  Dice dice,
) {
  final target = _across(fromDoor.cell, fromDoor.side); // where the mating cell goes
  final wantSide = oppositeSide(fromDoor.side);
  // Shuffle candidate order by dice for variety (Fisher-Yates).
  final cand = [...candidates];
  for (var i = cand.length - 1; i > 0; i--) {
    final j = dice.dN(i + 1) - 1;
    final t = cand[i]; cand[i] = cand[j]; cand[j] = t;
  }
  for (final base in cand) {
    for (var q = 0; q < 4; q++) {
      final f = base.rotate(q);
      for (final o in f.openings.where((o) => o.side == wantSide)) {
        // translate so o.cell lands on target
        final dx = target.$1 - o.cell.$1, dy = target.$2 - o.cell.$2;
        final placed = [for (final c in f.cells) (c.$1 + dx, c.$2 + dy)];
        if (placed.toSet().intersection(occupied).isNotEmpty) continue;
        final entry = DoorEdge(target, wantSide, DoorKind.open); // kind set by caller later
        final others = <DoorEdge>[];
        for (final op in f.openings) {
          final oc = (op.cell.$1 + dx, op.cell.$2 + dy);
          if (oc == target && op.side == wantSide) continue; // that's the entry
          others.add(DoorEdge(oc, op.side, DoorKind.open));
        }
        return Placement(cells: placed, entryDoor: entry, openDoors: others);
      }
    }
  }
  return null;
}
```

- [ ] **Step 4: Run it, expect PASS.**

Run: `flutter test test/dungeon/placement_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/dungeon/placement.dart test/dungeon/placement_test.dart
git commit -m "feat(dungeon): footprint placement (rotate + door-mate + fit)"
```

---

## Phase 1c — Engine: factions + generator

### Task 5: `faction.dart` — registry + 5/6 same-faction roll

**Files:**
- Create: `lib/engine/dungeon/faction.dart`
- Test: `test/dungeon/faction_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dungeon/faction.dart';

const _names = ['Rotfangs', 'Ashclaw Pack', 'Bonepickers'];

void main() {
  test('first organized monster of a type mints a new faction', () {
    final (reg, fac) = assignFaction(
        const FactionRegistry(), 'Goblins', 'room1', _names, Dice(Random(1)));
    expect(reg.factions, hasLength(1));
    expect(fac!.monsterType, 'Goblins');
    expect(_names, contains(fac.name));
    expect(fac.roomIds, ['room1']);
  });

  test('same type: 5/6 reuses, else mints new (deterministic under seed)', () {
    var reg = const FactionRegistry();
    (reg, _) = assignFaction(reg, 'Goblins', 'r1', _names, Dice(Random(1)));
    // roll many times over a fixed sequence; reuse must dominate ~5/6.
    var reuse = 0, mint = 0;
    final d = Dice(Random(7));
    for (var i = 0; i < 60; i++) {
      final before = reg.factions.length;
      (reg, _) = assignFaction(reg, 'Goblins', 'r$i', _names, d);
      if (reg.factions.length == before) reuse++; else mint++;
    }
    expect(reuse, greaterThan(mint));
  });
}
```

- [ ] **Step 2: Run it, expect FAIL.**

Run: `flutter test test/dungeon/faction_test.dart`
Expected: FAIL (uri missing).

- [ ] **Step 3: Implement `faction.dart`**

```dart
/// Tracked monster factions for a classic dungeon. Pure model + assignment.
/// The zine: on re-encountering an already-seen organized type there is a 5/6
/// chance they belong to an existing faction of that type, else a new one.
library;

import '../dice.dart';

class DungeonFaction {
  const DungeonFaction(
      {required this.id, required this.name, required this.monsterType, required this.roomIds});
  final String id;
  final String name;
  final String monsterType;
  final List<String> roomIds;

  DungeonFaction addRoom(String roomId) => DungeonFaction(
      id: id, name: name, monsterType: monsterType, roomIds: [...roomIds, roomId]);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'type': monsterType, 'rooms': roomIds};
  factory DungeonFaction.fromJson(Map<String, dynamic> j) => DungeonFaction(
        id: j['id'] as String,
        name: j['name'] as String,
        monsterType: j['type'] as String,
        roomIds: [for (final r in (j['rooms'] as List? ?? const [])) r as String],
      );
}

class FactionRegistry {
  const FactionRegistry({this.factions = const []});
  final List<DungeonFaction> factions;

  List<DungeonFaction> forType(String type) =>
      factions.where((f) => f.monsterType == type).toList();

  Map<String, dynamic> toJson() =>
      {'factions': [for (final f in factions) f.toJson()]};
  factory FactionRegistry.fromJson(dynamic j) {
    if (j is! Map) return const FactionRegistry();
    return FactionRegistry(factions: [
      for (final f in (j['factions'] as List? ?? const []))
        DungeonFaction.fromJson((f as Map).cast())
    ]);
  }
}

/// Resolve the faction for an organized [monsterType] appearing in [roomId].
/// Returns the extended registry and the assigned faction. Names are drawn from
/// [namePool]; when exhausted, a numbered fallback keeps them unique.
(FactionRegistry, DungeonFaction?) assignFaction(FactionRegistry reg,
    String monsterType, String roomId, List<String> namePool, Dice dice) {
  final existing = reg.forType(monsterType);
  DungeonFaction faction;
  List<DungeonFaction> next;
  // 5/6 reuse only when at least one faction of this type already exists.
  if (existing.isNotEmpty && dice.dN(6) <= 5) {
    final chosen = existing[dice.dN(existing.length) - 1];
    faction = chosen.addRoom(roomId);
    next = [for (final f in reg.factions) f.id == chosen.id ? faction : f];
  } else {
    final used = reg.factions.map((f) => f.name).toSet();
    final free = namePool.where((n) => !used.contains(n)).toList();
    final name = free.isNotEmpty
        ? free[dice.dN(free.length) - 1]
        : '${monsterType} Band ${reg.factions.length + 1}';
    faction = DungeonFaction(
        id: 'fac${reg.factions.length + 1}', name: name,
        monsterType: monsterType, roomIds: [roomId]);
    next = [...reg.factions, faction];
  }
  return (FactionRegistry(factions: next), faction);
}
```

- [ ] **Step 4: Run it, expect PASS.**

Run: `flutter test test/dungeon/faction_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/dungeon/faction.dart test/dungeon/faction_test.dart
git commit -m "feat(dungeon): tracked faction registry + 5/6 same-faction roll"
```

### Task 6: `generator.dart` — 4D6 room resolution + ref expansion + A2 effect

**Files:**
- Create: `lib/engine/dungeon/generator.dart`
- Test: `test/dungeon/generator_test.dart`

- [ ] **Step 1: Write the failing test** (uses a small hand-built `DungeonTables` so it never touches assets):

```dart
import 'dart:convert';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dice.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';
import 'package:juice_oracle/engine/dungeon/faction.dart';
import 'package:juice_oracle/engine/dungeon/generator.dart';
import 'package:juice_oracle/engine/dungeon/tables.dart';

DungeonTables _tables() => DungeonTables.fromJson(jsonDecode('''
{"A1":${jsonEncode(List.filled(12, 'Somewhere'))},
 "A2":{"2":{"name":"Vault","stock_double":true},"3":{"name":"X"},"4":{"name":"X"},
 "5":{"name":"X"},"6":{"name":"X"},"7":{"name":"Ruins"},"8":{"name":"X"},
 "9":{"name":"X"},"10":{"name":"Cursed","tier_bump":1},"11":{"name":"X"},"12":{"name":"X"}},
 "B2":["Nothing","Nothing","Nothing","Nothing","Nothing","Nothing"],
 "B5":["Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden","Wooden"],
 "C2":["Feature {ref:C3} + Monster","Nothing","Nothing","Feature {ref:C3}","Nothing","Nothing"],
 "G1":{"2":"Ambush","3":"a","4":"a","5":"a","6":"a","7":"Suspicious","8":"a","9":"a","10":"a","11":"a","12":"Friendly"},
 "G2":[{"text":"Goblins","count":"1","organized":true}],
 "faction_names":["Rotfangs"],
 "corridor_families":{"straight":[[11,66]]},
 "chamber_families":{"small":[[11,66]]},
 "label_fallbacks":{},
 "C3":["A fresco","A fresco"]}
''') as Map<String, dynamic>);

void main() {
  test('generateRoom returns a room type + entry door kind + detail text', () {
    final r = generateRoom(
        DungeonGenContext(level: 1, effect: const A2Type(name: 'Ruins'),
            tables: _tables(), factions: const FactionRegistry()),
        Dice(Random(3)));
    expect(r.type, anyOf(RoomType.corridor, RoomType.chamber));
    expect(r.entryDoorKind, isA<DoorKind>());
    expect(r.detail, isNotEmpty);
  });

  test('organized monster in a chamber extends the faction registry', () {
    // Force a chamber with the "Feature + Monster" stocking by seeding a run of
    // rolls that lands type>=4 and content==1. Loop a few seeds to find one.
    for (var s = 0; s < 50; s++) {
      final r = generateRoom(
          DungeonGenContext(level: 1, effect: const A2Type(name: 'Ruins'),
              tables: _tables(), factions: const FactionRegistry()),
          Dice(Random(s)));
      if (r.factions.factions.isNotEmpty) {
        expect(r.factions.factions.single.monsterType, 'Goblins');
        expect(r.detail, contains('Rotfangs'));
        return;
      }
    }
    fail('no seed produced an organized-monster chamber');
  });

  test('ref expansion is depth-capped (no infinite loop on self-ref)', () {
    final t = DungeonTables.fromJson(jsonDecode('''
{"A1":${jsonEncode(List.filled(12, 'x'))},"A2":{"2":{"name":"x"},"3":{"name":"x"},"4":{"name":"x"},"5":{"name":"x"},"6":{"name":"x"},"7":{"name":"x"},"8":{"name":"x"},"9":{"name":"x"},"10":{"name":"x"},"11":{"name":"x"},"12":{"name":"x"}},
 "B2":["Nothing","Nothing","Nothing","Nothing","Nothing","Nothing"],
 "B5":["W","W","W","W","W","W","W","W","W","W"],
 "C2":["Feature {ref:C3}","x","x","x","x","x"],
 "G1":{"2":"a","3":"a","4":"a","5":"a","6":"a","7":"a","8":"a","9":"a","10":"a","11":"a","12":"a"},
 "G2":[{"text":"g","count":"1","organized":false}],
 "faction_names":["N"],"corridor_families":{"straight":[[11,66]]},
 "chamber_families":{"small":[[11,66]]},"label_fallbacks":{},
 "C3":["loop {ref:C3}"]}
''') as Map<String, dynamic>);
    // must terminate, not stack-overflow
    final r = generateRoom(
        DungeonGenContext(level: 1, effect: const A2Type(name: 'x'),
            tables: t, factions: const FactionRegistry()),
        Dice(Random(0)));
    expect(r.detail, isNotEmpty);
  });
}
```

- [ ] **Step 2: Run it, expect FAIL.**

Run: `flutter test test/dungeon/generator_test.dart`
Expected: FAIL (uri missing).

- [ ] **Step 3: Implement `generator.dart`**

```dart
/// Pure 4D6 classic-dungeon room resolution over DungeonTables. Expands
/// {ref:XX} cross-reference tokens (depth-capped), applies the A2 dungeon-type
/// effect, rolls reaction + faction for organized monsters, and renders the
/// room's detail text. No Flutter, no I/O.
library;

import '../dice.dart';
import 'faction.dart';
import 'footprint.dart';
import 'tables.dart';

enum RoomType { corridor, chamber }

class DungeonGenContext {
  const DungeonGenContext(
      {required this.level, required this.effect, required this.tables, required this.factions});
  final int level;          // P1: always 1
  final A2Type effect;      // campaign-wide A2 dungeon-type effect
  final DungeonTables tables;
  final FactionRegistry factions;
}

class RoomResult {
  const RoomResult(
      {required this.type, required this.entryDoorKind, required this.shapeFamily,
       required this.detail, required this.factions});
  final RoomType type;
  final DoorKind entryDoorKind;
  final String shapeFamily;      // family id, resolved to a footprint at placement
  final String detail;           // multi-line text for DungeonRoom.detail
  final FactionRegistry factions;
}

/// D6 type die -> (roomType, entry door kind), per the zine's B1/C1 headers.
(RoomType, DoorKind) _typeDie(int d6) => switch (d6) {
      1 => (RoomType.corridor, DoorKind.locked),
      2 => (RoomType.corridor, DoorKind.door),
      3 => (RoomType.corridor, DoorKind.open),
      4 => (RoomType.chamber, DoorKind.open),
      5 => (RoomType.chamber, DoorKind.door),
      _ => (RoomType.chamber, DoorKind.locked),
    };

int _d66(Dice dice) => dice.dN(6) * 10 + dice.dN(6);

/// Expand {ref:XX} tokens in [text]. Recurses into referenced tables up to
/// [budget] levels; a P2-only or unknown ref becomes its fallback label. A
/// ref to a list-table rolls one row; a self-referential ref stops at budget.
String _expand(String text, DungeonTables t, Dice dice, {int budget = 4}) {
  final re = RegExp(r'\{ref:([A-Z]\d+)\}');
  return text.replaceAllMapped(re, (m) {
    final id = m.group(1)!;
    if (budget <= 0) return t.labelFallbacks[id] ?? id;
    final rows = (t.raw[id] as List?);
    if (rows == null) return t.labelFallbacks[id] ?? id;
    final row = rows[dice.dN(rows.length) - 1].toString();
    return _expand(row, t, dice, budget: budget - 1);
  });
}

RoomResult generateRoom(DungeonGenContext ctx, Dice dice) {
  final t = ctx.tables;
  final (type, entryKind) = _typeDie(dice.dN(6));
  final d66 = _d66(dice);
  final rangeMap = type == RoomType.corridor ? t.corridorFamilies : t.chamberFamilies;
  final catalog = type == RoomType.corridor ? kCorridorShapes : kChamberShapes;
  final family = shapesForRoll(d66, rangeMap, catalog).first.family;

  final lines = <String>['${type == RoomType.corridor ? "Corridor" : "Chamber"} ($family)'];
  var factions = ctx.factions;

  final stockTable = type == RoomType.corridor ? t.b2 : t.c2;
  final stock = stockTable[dice.dN(stockTable.length) - 1];
  final wantsMonster = stock.contains('Monster');
  lines.add(_expand(stock, t, dice));

  if (wantsMonster && t.upperMonsters.isNotEmpty) {
    // depth tier: level 1 -> upper (G2); effect.tierBump documented for P2 G3/G4.
    final mon = t.upperMonsters[dice.dN(t.upperMonsters.length) - 1];
    final n = ctx.effect.stockDouble ? 2 : 1;
    final reaction = t.reaction['${dice.dN(6) + dice.dN(6)}'] ?? '';
    lines.add('Monsters: ${n}x ${mon.text} (${mon.count}) — reaction: $reaction');
    if (mon.organized) {
      final DungeonFaction? fac;
      (factions, fac) = assignFaction(
          factions, mon.text, 'pending', t.factionNames, dice);
      if (fac != null) lines.add('Faction: ${fac.name}');
    }
  }

  return RoomResult(
      type: type, entryDoorKind: entryKind, shapeFamily: family,
      detail: lines.join('\n'), factions: factions);
}
```

Note: the faction is created with a placeholder `'pending'` roomId; Task 8's
notifier reconciles it to the real room id after the room is appended (the
faction's `roomIds` last entry is replaced). Keeping the generator pure means it
cannot know the id the notifier will mint.

- [ ] **Step 4: Run it, expect PASS.**

Run: `flutter test test/dungeon/generator_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/dungeon/generator.dart test/dungeon/generator_test.dart
git commit -m "feat(dungeon): 4D6 room generator, ref expansion, A2 effect, factions"
```

---

## Phase 1d — Model + state

### Task 7: Grow `DungeonRoom` with footprint/doors/roomType

**Files:**
- Modify: `lib/engine/models.dart` (`DungeonRoom` at ~line 3125)
- Test: `test/dungeon/dungeon_room_json_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('legacy single-cell room round-trips and defaults footprint to [(0,0)]', () {
    const r = DungeonRoom(id: 'a', x: 2, y: 3, title: 'Old');
    final j = r.toJson();
    final back = DungeonRoom.fromJson(j);
    expect(back.footprint, [(0, 0)]);
    expect(back.doors, isEmpty);
    expect(back.roomType, isNull);
  });

  test('footprint + doors + type round-trip', () {
    final r = DungeonRoom(id: 'b', x: 0, y: 0, title: 'New',
        footprint: const [(0, 0), (0, 1)],
        doors: const [DoorEdge((0, 1), Side.s, DoorKind.open)],
        roomType: 'chamber');
    final back = DungeonRoom.fromJson(r.toJson());
    expect(back.footprint, [(0, 0), (0, 1)]);
    expect(back.doors.single.kind, DoorKind.open);
    expect(back.roomType, 'chamber');
  });
}
```

- [ ] **Step 2: Run it, expect FAIL** (constructor lacks the new params).

Run: `flutter test test/dungeon/dungeon_room_json_test.dart`
Expected: FAIL (no `footprint` named param).

- [ ] **Step 3: Modify `DungeonRoom`** (add import `import 'dungeon/footprint.dart';` at the top of `models.dart` if not already re-exported; then extend the class). Replace the class body's constructor/fields/`copyWith`/`toJson`/`fromJson` to include the new optional fields:

```dart
// add fields after `status`:
  final List<(int, int)> footprint; // cell offsets from (x,y); default [(0,0)]
  final List<DoorEdge> doors;       // world-relative door edges (offsets from (x,y))
  final String? roomType;           // 'corridor' | 'chamber' | null (legacy)

// constructor: add
//   this.footprint = const [(0, 0)], this.doors = const [], this.roomType,

// copyWith: thread the three new fields through (nullable roomType with a
// clearRoomType bool is unnecessary — null just means "keep"; a legacy room
// never sets it).

// toJson: add (omit when default, to keep legacy JSON small)
  if (footprint.length != 1 || footprint.first != (0, 0))
    'fp': [for (final c in footprint) [c.$1, c.$2]],
  if (doors.isNotEmpty) 'dr': [for (final d in doors) d.toJson()],
  if (roomType != null) 'rt': roomType,

// fromJson: parse them
  footprint: (j['fp'] as List?)?.map((e) => ((e as List)[0] as int, e[1] as int)).toList() ?? const [(0, 0)],
  doors: (j['dr'] as List?)?.map((e) => DoorEdge.fromJson((e as Map).cast())).toList() ?? const [],
  roomType: j['rt'] as String?,
```

(Read the existing `toJson`/`fromJson`/`copyWith` first and splice these in; keep the existing `id/x/y/title/detail/status` handling verbatim.)

- [ ] **Step 4: Run it, expect PASS.**

Run: `flutter test test/dungeon/dungeon_room_json_test.dart`
Expected: PASS.

- [ ] **Step 5: Run the existing map tests to prove no regression.**

Run: `flutter test test/ -name '*map*'` (or the specific existing dungeon/map test files)
Expected: PASS (base pane unaffected).

- [ ] **Step 6: Commit**

```bash
git add lib/engine/models.dart test/dungeon/dungeon_room_json_test.dart
git commit -m "feat(dungeon): DungeonRoom gains optional footprint/doors/roomType"
```

### Task 8: `dungeonFactionsProvider` + `MapNotifier.addClassicRoom`

**Files:**
- Modify: `lib/state/providers.dart` (new notifier + `sessionScopedKeys` entry + `addClassicRoom`)
- Test: `test/dungeon/add_classic_room_test.dart`

- [ ] **Step 1: Write the failing test** (drives the notifier through a fake container with mock prefs + the real `dungeon_data.json` fixture; assert a multi-cell room + corridor appended, and a faction persisted when an organized monster lands). Model it on the existing `MapNotifier` test setup (read `test/` for the container-with-overrides + `SharedPreferences.setMockInitialValues({})` pattern). Core assertions:

```dart
// after enabling classic-dungeon and calling addClassicRoom twice:
final map = container.read(mapProvider).requireValue;
expect(map.rooms.length, 2);
expect(map.rooms[1].footprint.length, greaterThanOrEqualTo(1));
expect(map.corridors, contains(['<room0id>', '<room1id>']));
// entry door kind on room[1] came from the type die (not 'open' unless no-door)
expect(map.rooms[1].doors.any((d) => d.cell == /* mated cell */), isTrue);
```

- [ ] **Step 2: Run it, expect FAIL** (`addClassicRoom` undefined).

Run: `flutter test test/dungeon/add_classic_room_test.dart`
Expected: FAIL.

- [ ] **Step 3: Add the faction notifier** (session-scoped, mirrors `DecksNotifier`). In `lib/state/providers.dart`:

```dart
class DungeonFactionsNotifier extends AsyncNotifier<FactionRegistry> {
  static const _baseKey = 'juice.dungeon_factions.v1';
  String get _key => '$_baseKey.${ref.watch(activeSessionIdProvider)}';

  @override
  Future<FactionRegistry> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    return raw == null
        ? const FactionRegistry()
        : FactionRegistry.fromJson(jsonDecode(raw));
  }

  Future<void> save(FactionRegistry reg) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(reg.toJson()));
    state = AsyncData(reg);
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    state = const AsyncData(FactionRegistry());
  }
}

final dungeonFactionsProvider =
    AsyncNotifierProvider<DungeonFactionsNotifier, FactionRegistry>(
        DungeonFactionsNotifier.new);
```
Add `'juice.dungeon_factions.v1',` to the `sessionScopedKeys` list (line ~1696) so it exports/imports with the campaign. Add the needed imports (`dungeon/faction.dart`, `dungeon/generator.dart`, `dungeon/footprint.dart`, `dungeon/placement.dart`) — check `activeSessionIdProvider` is the correct name by reading how `DecksNotifier` derives its key, and mirror it exactly.

- [ ] **Step 4: Add `addClassicRoom`** to `MapNotifier`:

```dart
/// Generate + place one classic-dungeon room mated to [doorEdge] on room
/// [fromRoomId] (null = the first/entrance room at (0,0)). Persists the faction
/// registry when an organized monster is stocked. No-op returns false if no
/// footprint fits the chosen door.
Future<bool> addClassicRoom({
  required String? fromRoomId,
  required ({(int, int) cell, Side side})? doorEdge, // null for the entrance
  required DungeonTables tables,
  required A2Type effect,
  required Dice dice,
}) async {
  final s = state.valueOrNull ?? const MapState();
  final factions = ref.read(dungeonFactionsProvider).valueOrNull ?? const FactionRegistry();
  final gen = generateRoom(
      DungeonGenContext(level: 1, effect: effect, tables: tables, factions: factions),
      dice);

  final id = 'room${DateTime.now().microsecondsSinceEpoch}';
  List<(int, int)> footprintOffsets;
  List<DoorEdge> doors;
  int ax, ay;

  if (fromRoomId == null || doorEdge == null) {
    // Entrance at (0,0): use the first footprint of the rolled family; all
    // openings start open.
    final catalog = gen.type == RoomType.corridor ? kCorridorShapes : kChamberShapes;
    final fp = catalog[gen.shapeFamily]!.first.rotate(0);
    ax = 0; ay = 0;
    footprintOffsets = fp.normalizedCells;
    doors = [for (final o in fp.openings) DoorEdge(o.cell, o.side, DoorKind.open)];
  } else {
    final occupied = <(int, int)>{
      for (final r in s.rooms) for (final c in r.footprint) (r.x + c.$1, r.y + c.$2)
    };
    final catalog = gen.type == RoomType.corridor ? kCorridorShapes : kChamberShapes;
    final placed = placeRoom(occupied, doorEdge, catalog[gen.shapeFamily]!, dice);
    if (placed == null) return false;
    // anchor = min cell; store offsets relative to it
    final minX = placed.cells.map((c) => c.$1).reduce((a, b) => a < b ? a : b);
    final minY = placed.cells.map((c) => c.$2).reduce((a, b) => a < b ? a : b);
    ax = minX; ay = minY;
    footprintOffsets = [for (final c in placed.cells) (c.$1 - minX, c.$2 - minY)];
    doors = [
      DoorEdge((placed.entryDoor.cell.$1 - minX, placed.entryDoor.cell.$2 - minY),
          placed.entryDoor.side, gen.entryDoorKind),
      for (final d in placed.openDoors)
        DoorEdge((d.cell.$1 - minX, d.cell.$2 - minY), d.side, DoorKind.open),
    ];
  }

  final room = DungeonRoom(
      id: id, x: ax, y: ay, title: gen.detail.split('\n').first,
      detail: gen.detail, footprint: footprintOffsets, doors: doors,
      roomType: gen.type == RoomType.corridor ? 'corridor' : 'chamber');

  // Reconcile the 'pending' faction roomId -> real id, then persist.
  if (gen.factions.factions.isNotEmpty) {
    final reconciled = FactionRegistry(factions: [
      for (final f in gen.factions.factions)
        DungeonFaction(id: f.id, name: f.name, monsterType: f.monsterType,
            roomIds: [for (final rid in f.roomIds) rid == 'pending' ? id : rid])
    ]);
    await ref.read(dungeonFactionsProvider.notifier).save(reconciled);
  }

  final next = s.copyWith(
    rooms: [...s.rooms, room],
    corridors: fromRoomId == null ? s.corridors : [...s.corridors, [fromRoomId, id]],
    currentRoomId: id,
  );
  state = AsyncData(next);
  await _persist(next); // use whatever persistence call addRoom already uses
  return true;
}
```
(Read `MapNotifier.addRoom` first to reuse its exact persistence helper — replace `_persist(next)` with the real call.)

- [ ] **Step 5: Wire dungeon reset to also clear factions** — find `MapNotifier`'s dungeon-clear method (the one setting `rooms: const []`) and, after it, add a note in the plan's UI task to call `dungeonFactionsProvider.notifier.reset()` from the same button. (No code here; handled in Task 9.)

- [ ] **Step 6: Run it, expect PASS.**

Run: `flutter test test/dungeon/add_classic_room_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/state/providers.dart test/dungeon/add_classic_room_test.dart
git commit -m "feat(dungeon): dungeonFactionsProvider + MapNotifier.addClassicRoom"
```

---

## Phase 1e — UI: footprint painter + door-tap exploration

### Task 9: Footprint-aware painter + hit-test

**Files:**
- Modify: `lib/features/map_screen.dart` (`roomRectFor`, `roomIdAt`, the dungeon painter, add a door-hit-test)
- Test: `test/dungeon/painter_geometry_test.dart`

- [ ] **Step 1: Write the failing test** for the pure geometry helpers (painting itself is device-verified; geometry is unit-tested):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/dungeon/footprint.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/map_screen.dart';

void main() {
  test('multi-cell footprint hit-tests each of its cells', () {
    final rooms = [
      DungeonRoom(id: 'a', x: 0, y: 0, title: 'A',
          footprint: const [(0, 0), (0, 1)],
          doors: const [DoorEdge((0, 1), Side.s, DoorKind.open)]),
    ];
    // a point inside the second cell (0,1) still resolves to room 'a'
    final center = cellCenterFor(rooms.first, (0, 1), 0, 0, 56.0);
    expect(roomIdAt(rooms, center, 56.0), 'a');
  });

  test('door hit-test finds the open door edge under a point', () {
    final rooms = [
      DungeonRoom(id: 'a', x: 0, y: 0, title: 'A',
          footprint: const [(0, 0)],
          doors: const [DoorEdge((0, 0), Side.s, DoorKind.open)]),
    ];
    final p = doorMarkerCenter(rooms.first, rooms.first.doors.single, 0, 0, 56.0);
    final hit = doorEdgeAt(rooms, p, 56.0);
    expect(hit, isNotNull);
    expect(hit!.roomId, 'a');
    expect(hit.door.side, Side.s);
  });
}
```

- [ ] **Step 2: Run it, expect FAIL.**

Run: `flutter test test/dungeon/painter_geometry_test.dart`
Expected: FAIL (helpers missing).

- [ ] **Step 3: Generalize the geometry helpers** in `map_screen.dart`. `roomRectFor` currently takes a `DungeonRoom` and returns one rect; add a per-cell variant and update `roomIdAt` to test every footprint cell; add door-marker geometry + hit-test:

```dart
/// Pixel rect of one footprint cell of [r] (offset [cell]) in canvas space.
Rect cellRectFor(DungeonRoom r, (int, int) cell, int minX, int minY, double cell_) {
  final pad = cell_ / 2;
  final gx = r.x + cell.$1, gy = r.y + cell.$2;
  final left = (gx - minX) * cell_ + pad;
  final top = (gy - minY) * cell_ + pad;
  return Rect.fromLTWH(left + _roomInset, top + _roomInset,
      cell_ - 2 * _roomInset, cell_ - 2 * _roomInset);
}

Offset cellCenterFor(DungeonRoom r, (int, int) cell, int minX, int minY, double c) =>
    cellRectFor(r, cell, minX, minY, c).center;

// roomIdAt: iterate rooms, then each room's footprint cells:
//   for (final cell in r.footprint) if (cellRectFor(...).contains(local)) return r.id;

/// Center of a door marker: mid-point of the [door] edge on its cell.
Offset doorMarkerCenter(DungeonRoom r, DoorEdge door, int minX, int minY, double c) {
  final rect = cellRectFor(r, door.cell, minX, minY, c);
  return switch (door.side) {
    Side.n => rect.topCenter, Side.s => rect.bottomCenter,
    Side.e => rect.centerRight, Side.w => rect.centerLeft,
  };
}

class DoorHit { const DoorHit(this.roomId, this.door); final String roomId; final DoorEdge door; }

/// Nearest open door edge within half a cell of [local], else null.
DoorHit? doorEdgeAt(List<DungeonRoom> rooms, Offset local, double c) {
  if (rooms.isEmpty) return null;
  final minX = rooms.map((r) => r.x).reduce((a, b) => a < b ? a : b);
  final minY = rooms.map((r) => r.y).reduce((a, b) => a < b ? a : b);
  for (final r in rooms) {
    for (final d in r.doors) {
      if (d.kind == DoorKind.open &&
          (doorMarkerCenter(r, d, minX, minY, c) - local).distance < c / 3) {
        return DoorHit(r.id, d);
      }
    }
  }
  return null;
}
```
Note `roomRectFor`'s existing `minX/minY` computation uses `r.x`/`r.y`; keep that, and for multi-cell rooms the bounds must consider footprint extent — update the painter's `minX/minY` to `min` over `r.x + cell.$1`. Update the painter's `paint` loop to draw the union of `cellRectFor` for every footprint cell (rounded outline) plus a door glyph at each `doorMarkerCenter` (open = small arrow via `paintEncounterPin`-style TextPainter or a triangle; door = short bar; locked = lock icon codepoint).

- [ ] **Step 4: Run it, expect PASS.**

Run: `flutter test test/dungeon/painter_geometry_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/map_screen.dart test/dungeon/painter_geometry_test.dart
git commit -m "feat(dungeon): footprint-aware painter geometry + door hit-test"
```

### Task 10: Door-tap exploration + Enter action, gated on the system

**Files:**
- Modify: `lib/features/map_screen.dart` (`DungeonMapPane`: gesture handling, Enter button, hide blind "Roll Next Room" in classic mode)
- Modify: `lib/features/maps_tab.dart` (pass a `classicDungeon` flag into the pane)
- Test: `test/dungeon/classic_pane_widget_test.dart`

- [ ] **Step 1: Write the failing widget test** (pump `DungeonMapPane` with `classic-dungeon` enabled; tap Enter → one room appears; tap an open door → a second room appears mated). Follow the rootBundle-hang recipe — override `oracleProvider`, `verdantDataProvider`, `emulatorDataProvider`, ruleset providers, AND `dungeonDataProvider` with file fixtures, and `SharedPreferences.setMockInitialValues({'juice.sessions.v1': ..., 'juice.ai_enabled.v1': false})`. Key assertions:

```dart
await tester.tap(find.byKey(const Key('classic-enter')));
await tester.pumpAndSettle();
expect(find.byKey(const Key('dungeon-canvas')), findsOneWidget);
// one room now exists
expect(container.read(mapProvider).requireValue.rooms, hasLength(1));
// tap the first open door marker (via a known offset) -> second room
// (drive through the notifier if hit-testing a CustomPaint is impractical):
await container.read(mapProvider.notifier).addClassicRoom(/* ...mated... */);
await tester.pump();
expect(container.read(mapProvider).requireValue.rooms.length, 2);
```

- [ ] **Step 2: Run it, expect FAIL.**

Run: `flutter test test/dungeon/classic_pane_widget_test.dart`
Expected: FAIL (no `classic-enter` key / flag).

- [ ] **Step 3: Wire the UI.** In `maps_tab.dart`, compute `final classic = systems.contains('classic-dungeon');` and pass it to `DungeonMapPane(oracle: oracle, classic: classic)`. In `map_screen.dart`:
  - add the `classic` field to `DungeonMapPane`;
  - when `classic`, replace the `_newRoom` FAB/button with an **"Enter the dungeon"** button (`Key('classic-enter')`) shown only while `rooms.isEmpty` — it reads `dungeonDataProvider`, rolls A1/A2 (store the chosen `A2Type` in a `State` field so all subsequent rooms use the same effect), and calls `addClassicRoom(fromRoomId: null, doorEdge: null, tables: …, effect: …, dice: oracle.dice)`;
  - add a tap handler on the canvas that runs `doorEdgeAt(...)`; on a hit, call `addClassicRoom(fromRoomId: hit.roomId, doorEdge: (cell: worldCell, side: hit.door.side), tables: …, effect: _effect, dice: oracle.dice)` and `setState`; on `false` (no fit) show the snackbar "No room fits that way — try another exit";
  - hide the blind "Roll Next Room" button when `classic` is true;
  - in the dungeon-clear handler, also call `ref.read(dungeonFactionsProvider.notifier).reset()`.
  Read the existing `GestureDetector`/`InteractiveViewer` nesting (the pan-zoom section) and add the door tap without breaking pan (mirror how room-tap already coexists with pan).

- [ ] **Step 4: Run it, expect PASS.**

Run: `flutter test test/dungeon/classic_pane_widget_test.dart`
Expected: PASS.

- [ ] **Step 5: Device-verify** (per the preview workflow / device build): enable `classic-dungeon` on a campaign, open Map → Dungeon, tap Enter, then tap open doors to grow the dungeon; confirm polygons + door glyphs render and factions accumulate. Screenshot for the PR.

- [ ] **Step 6: Commit**

```bash
git add lib/features/map_screen.dart lib/features/maps_tab.dart test/dungeon/classic_pane_widget_test.dart
git commit -m "feat(dungeon): classic-dungeon door-tap exploration + Enter action"
```

---

## Phase 1f — Registration, attribution, docs

### Task 11: Register `classic-dungeon` across the system-metadata maps

**Files:**
- Modify: `lib/engine/models.dart` (`kKnownSystems`, `kSystemCategory`, `kSystemLabels`, `kSystemBlurbs`, `kSystemShortName`/`kPresetIcons` if present)
- Modify: `lib/engine/content_registry.dart` (`kContentAttributions`)
- Modify: `lib/features/settings_sheet.dart` (Sources dialog line — only if that dialog concatenates a manual list beyond `kContentAttributions`)
- Modify: `lib/engine/campaign_surfaces.dart` (`surfacesFor` — add the Dungeon-crawl surface when `classic-dungeon` present, if not already implied by the Map verb)
- Test: extend `test/` system-completeness test (the one asserting `kSystemCategory`/blurbs cover `kKnownSystems`)

- [ ] **Step 1: Run the existing system-completeness test to see it fail** once you add the id to `kKnownSystems` only.

Add `'classic-dungeon',` to `kKnownSystems`. Run the completeness test.
Run: `flutter test test/ -name '*system*'` (find the actual file, e.g. `test/system_registration_test.dart`)
Expected: FAIL (missing from `kSystemCategory`/labels).

- [ ] **Step 2: Fill in every map:**

```dart
// kSystemCategory:
  'classic-dungeon': SystemCategory.exploration,
// kSystemLabels:
  'classic-dungeon': 'Classic Dungeon',
// kSystemBlurbs (add):
  'classic-dungeon':
      'Roll 4 Ruin room-by-room dungeon crawler: explore openings to reveal '
      'shape-accurate rooms with depth-scaled monsters, treasure, and factions. '
      'Content © Nocturnal Peacock, CC-BY-NC-SA-4.0. Not affiliated.',
// kSystemShortName / kPresetIcons if those maps exist: add a sensible entry
//   (e.g. shortName 'Ruin', icon Icons.castle).
```
```dart
// kContentAttributions (content_registry.dart):
  'classic-dungeon':
      'Roll 4 Ruin: Classic Dungeon Generator © Nocturnal Peacock, licensed '
      'under CC-BY-NC-SA-4.0.',
```

- [ ] **Step 3: Verify the attribution shows** — since `settings-sources` already joins `kContentAttributions.values`, the new line appears automatically. Only edit `settings_sheet.dart` if `classic-dungeon` needs a bespoke note. Confirm by reading the dialog builder.

- [ ] **Step 4: Run the completeness test + full suite.**

Run: `flutter test`
Expected: PASS (all green).

- [ ] **Step 5: Analyze + format edited files.**

Run: `flutter analyze lib/ test/` (expect no new issues) and `dart format` on each file you touched.

- [ ] **Step 6: Commit**

```bash
git add lib/engine/models.dart lib/engine/content_registry.dart lib/engine/campaign_surfaces.dart lib/features/settings_sheet.dart test/
git commit -m "feat(dungeon): register classic-dungeon system + CC-BY-NC-SA attribution"
```

### Task 12: Docs — CLAUDE.md note + spec cross-link

**Files:**
- Modify: `CLAUDE.md` (add a `classic-dungeon` bullet in the project-notes style)
- Modify: the design spec (mark Status: shipped once merged)

- [ ] **Step 1: Add a CLAUDE.md bullet** summarizing: opt-in `classic-dungeon` (exploration, NOT in `kAllSystems`); `build_dungeon.py` → `assets/dungeon_data.json` rail (CC-BY-NC-SA-4.0, attribution in `kContentAttributions`); pure `lib/engine/dungeon/` (footprint/placement/faction/generator/tables); `DungeonRoom` grew footprint/doors/roomType; `MapNotifier.addClassicRoom` + `dungeonFactionsProvider` (`juice.dungeon_factions.v1`, sessionScoped); footprint painter + door-tap exploration on the Map → Dungeon pane; P2 deferred (caves D–F, multi-level, interactive traps). Reference the spec + this plan path.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md docs/superpowers/specs/2026-07-06-classic-dungeon-generator-design.md
git commit -m "docs(dungeon): CLAUDE.md note for classic-dungeon system"
```

- [ ] **Step 3: Final full verification before PR.**

Run: `python3 build_dungeon.py && flutter test && flutter analyze lib/ test/`
Expected: build self-check OK; all tests pass; no new analyzer issues.

---

## Self-review notes (author)

- **Spec coverage:** data rail (T1–2), footprints+placement (T3–4), faction (T5), generator/4D6/ref-expansion/A2 effect (T6), model growth (T7), notifier+provider+sessionScoped (T8), painter+door-tap UI gated on system (T9–10), registration+attribution (T11), docs (T12). Traps-as-text handled by generator ref-expansion rendering B4 as detail (no trigger mechanic) — matches decision 7. Directed exploration + Enter action = decision 1. Catalog (not 132 shapes) = decision 4.
- **Type consistency:** `DungeonTables`, `A2Type`, `MonsterRow`, `RoomFootprint`/`Opening`/`DoorEdge`/`Side`/`DoorKind`, `Placement`, `FactionRegistry`/`DungeonFaction`, `RoomType`/`DungeonGenContext`/`RoomResult`, `addClassicRoom` signature — used identically across tasks.
- **Known execution unknowns to resolve by reading, flagged inline:** exact `MapNotifier` persistence helper name (T8 S4), `activeSessionIdProvider` name (T8 S3), the system-completeness test filename (T11 S1), whether `pubspec.yaml` already globs `assets/` (T1 S5), and the exact existing `roomRectFor` min-bounds code (T9 S3). Each task says to read the file first.
