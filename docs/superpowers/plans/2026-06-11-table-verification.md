# BEST-EFFORT Table Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Encode the two missing OCR-ambiguous Juice tables — the Wilderness Monster Encounter grid and the NPC Dialog 5×5 grid — verified against the PDF, wired into engine + UI + tests.

**Architecture:** Same pipeline as everything else: data + mechanics encoded and self-verified in `build_oracle.py` → emitted into `assets/oracle_data.json` → typed accessors in `oracle_data.dart` → roll logic in `oracle.dart` (mirroring the Python) → generator buttons in `generators_screen.dart`. Dialog is a stateful grid walk; v1 keeps conversation state in the `Oracle` instance (in-memory, resets on app restart — persistence arrives with the crawl-modes roadmap item).

**Tech Stack:** Python 3 (build pipeline), Dart/Flutter, `package:test` via `flutter test`.

---

**Source material:** `/tmp/juice-roll/reference/` (re-clone if missing:
`git clone --depth 1 https://github.com/johnkord/juice-roll /tmp/juice-roll`).
- PDF ground truth: `juice_081425_pocketfold_usletter-1.pdf` (the tables) and
  `juice_081425_instructions-1.md` (the mechanics, already plain text).
- Cross-check only (known-imperfect OCR): `juice-oracle-text-tables/wilderness-monster-encounter.md`, `juice-oracle-text-tables/dialog.md`.

**Mechanics summary (from instructions, sections "Monster"/"Encounter
Generator" ~lines 2390–2510 and the NPC Dialog walkthrough ~lines 3100–3200):**

*Monster Encounter:* Current environment row (1–0 on the Wilderness table)
gives a formula `+M@S` = roll 1d6 at skew S (`-` disadvantage, `0` straight,
`+` advantage) plus modifier M → row on the Monster grid. Doubles on the
skewed 2d6 → `**` Bandits row. Forest (env row 6) rolling a 6 → `*` Blights
row. Then 2d10: first die = difficulty (1–4 Easy → columns 1–2, 5–8 Medium →
columns 1–3, 9–0 Hard → columns 1–4), doubles → add 1 boss (column 5).
Quantity per non-boss monster: 1d6−1 skewed by the monster's prefix
(`+` advantage, none straight, `-` disadvantage). Tracks-only roll: stop after
the row (column 1 names the tracks).

*NPC Dialog:* 5×5 grid, marker starts center ("Fact", row 3 col 3). Each beat:
2d10. Die 1 = direction + tone: 1–2 Neutral/up, 3–5 Defensive/left,
6–8 Aggressive/right, 9–0 Helpful/down; move one cell, wrapping at edges.
Die 2 = subject: 1–2 Them, 3–5 Me, 6–8 You, 9–0 Us. Doubles = conversation
ends (reset marker to center). Rows 1–2 = past tense, rows 3–5 = present.

### Task 1: Verify table content against the PDF

**Files:** none (research; results feed Tasks 2–3)

- [ ] **Step 1: Read the grids in the PDF**

Use the Read tool on `/tmp/juice-roll/reference/juice_081425_pocketfold_usletter-1.pdf`
(it is short — read all pages). Locate the Wilderness Monster Encounter grid
and the Dialog grid.

- [ ] **Step 2: Confirm or correct the candidate data below**

Candidate monster grid (from the cross-check transcription; abbreviations
expanded to 5e SRD names — verify each cell and each `+`/`-` prefix against
the PDF):

| Row | Tracks (col 1) | Easy (col 2) | Medium (col 3) | Hard (col 4) | Boss (col 5) |
|---|---|---|---|---|---|
| 1 | + Wolf | - Ice Mephit | - Winter Wolf | Yeti | Werebear |
| 2 | + Skeleton | - Warhorse Skeleton | - Wight | - Nightmare | Wraith |
| 3 | + Drow | - Giant Spider | - Quaggoth | - Phase Spider | Drider |
| 4 | + Goblin | - Worg | + Hobgoblin | + Bugbear | Hobgoblin Captain |
| 5 | Orc | - Orog | Orc Eye of Gruumsh | - Troll | Orc War Chief |
| 6* | Kobold | + Giant Weasel | + Winged Kobold | + Stirge | Young Dragon |
| 7 | Lizardfolk | Giant Lizard | Lizardfolk Shaman | - Giant Crocodile | Lizard King |
| 8 | + Zombie | Ghoul | - Mummy | Ogre Zombie | Vampire Spawn |
| 9 | Yuan-ti Pureblood | - Cockatrice | - Yuan-ti Malison | Basilisk | Medusa |
| 0 | Gnoll | - Giant Hyena | Gnoll Pack Lord | + Jackalwere | Lamia |
| * | + Twig Blight | + Needle Blight | + Vine Blight | - Shambling Mound | Green Hag |
| ** | + Bandit | Thug | Scout | - Veteran | Bandit Captain |

Candidate environment formulas (Monster column of the Wilderness table,
row → `(modifier, skew)` with skew −1/0/+1):
1 Arctic (0,−1) · 2 Mountains (0,0) · 3 Cavern (1,−1) · 4 Hills (1,0) ·
5 Grassland (3,−1) · 6 Forest (2,0) · 7 Swamp (3,+1) · 8 Water (3,0) ·
9 Coast (4,−1) · 0 Desert (4,+1)

Candidate dialog grid (5×5; the transcription's matrix is malformed — trust
the PDF; instructions confirm center = Fact, top two rows past tense):

```
Fact    Denial   Query   Denial   Action
Want    Query    Need    Query    Fact
Action  Need     Fact    Action   Denial
Need    Query    Denial  Query    Want
Query   Support  Query   Support  Need
```

- [ ] **Step 3: Record corrections**

Note any cell that differs from the candidates directly into the Task 2/3 code
before writing it. If the PDF is illegible for a cell, keep the transcription
value and add a `# UNCONFIRMED:` comment — do not guess silently.

### Task 2: Encode monster grid + mechanics in build_oracle.py

**Files:**
- Modify: `build_oracle.py` (data after `EXT_DIALOG_TOPIC` ~line 338; mechanics near `roll_table` ~line 380; checks inside `verify()` ~line 403; emission inside `emit_json()` ~line 481)

- [ ] **Step 1: Add the data (corrected per Task 1)**

```python
# Wilderness Monster Encounter (pocketfold left extension), verified vs PDF.
# Quantity prefix per monster: '+' = 1d6-1@adv, '' = 1d6-1, '-' = 1d6-1@dis.
# Row keys: '1'..'0' (d6+mod result), '*' = Forest special, '**' = doubles/Bandits.
MONSTER_GRID = {
    "1":  ["+ Wolf", "- Ice Mephit", "- Winter Wolf", "Yeti", "Werebear"],
    "2":  ["+ Skeleton", "- Warhorse Skeleton", "- Wight", "- Nightmare", "Wraith"],
    "3":  ["+ Drow", "- Giant Spider", "- Quaggoth", "- Phase Spider", "Drider"],
    "4":  ["+ Goblin", "- Worg", "+ Hobgoblin", "+ Bugbear", "Hobgoblin Captain"],
    "5":  ["Orc", "- Orog", "Orc Eye of Gruumsh", "- Troll", "Orc War Chief"],
    "6":  ["Kobold", "+ Giant Weasel", "+ Winged Kobold", "+ Stirge", "Young Dragon"],
    "7":  ["Lizardfolk", "Giant Lizard", "Lizardfolk Shaman", "- Giant Crocodile", "Lizard King"],
    "8":  ["+ Zombie", "Ghoul", "- Mummy", "Ogre Zombie", "Vampire Spawn"],
    "9":  ["Yuan-ti Pureblood", "- Cockatrice", "- Yuan-ti Malison", "Basilisk", "Medusa"],
    "0":  ["Gnoll", "- Giant Hyena", "Gnoll Pack Lord", "+ Jackalwere", "Lamia"],
    "*":  ["+ Twig Blight", "+ Needle Blight", "+ Vine Blight", "- Shambling Mound", "Green Hag"],
    "**": ["+ Bandit", "Thug", "Scout", "- Veteran", "Bandit Captain"],
}

# Wilderness env row (1..10) -> (modifier, skew) for the 1d6 monster-row roll.
MONSTER_ENV_FORMULA = {
    1: (0, -1), 2: (0, 0), 3: (1, -1), 4: (1, 0), 5: (3, -1),
    6: (2, 0), 7: (3, 1), 8: (3, 0), 9: (4, -1), 10: (4, 1),
}
```

(Write the dict in one literal with all 12 keys — the staged assignments above
just show the special-row handling; collapse them when writing.)

- [ ] **Step 2: Add the mechanics function (next to `roll_table`)**

```python
def monster_encounter(env_row, rng_doubles_to_bandits=True):
    """Roll a monster encounter for wilderness environment row 1..10."""
    mod, skew = MONSTER_ENV_FORMULA[env_row]
    a, b = d(6), d(6)
    if skew > 0:
        pick = max(a, b)
    elif skew < 0:
        pick = min(a, b)
    else:
        pick = a
    if skew != 0 and a == b and rng_doubles_to_bandits:
        row_key = "**"
    else:
        row = min(pick + mod, 10)
        row_key = "0" if row == 10 else str(row)
        if env_row == 6 and row == 6:
            row_key = "*"  # Forest special: Blights
    d1, d2 = d(10), d(10)
    band = 2 if d1 <= 4 else (3 if d1 <= 8 else 4)  # columns 1..band
    boss = d1 == d2
    monsters = []
    for cell in MONSTER_GRID[row_key][:band]:
        prefix, name = (cell[0], cell[2:]) if cell[:2] in ("+ ", "- ") else ("", cell)
        q1, q2 = d(6), d(6)
        qty = (max(q1, q2) if prefix == "+" else min(q1, q2) if prefix == "-" else q1) - 1
        if qty > 0:
            monsters.append((name, qty))
    if boss:
        monsters.append((MONSTER_GRID[row_key][4], 1))
    return {"row": row_key, "difficulty": {2: "Easy", 3: "Medium", 4: "Hard"}[band],
            "boss": boss, "monsters": monsters}
```

- [ ] **Step 3: Add verification checks inside `verify()`**

```python
    # 6. Monster grid shape + mechanics.
    if set(MONSTER_GRID) != {"1","2","3","4","5","6","7","8","9","0","*","**"}:
        failures.append("monster grid keys wrong")
    for k, row in MONSTER_GRID.items():
        if len(row) != 5:
            failures.append(f"monster row {k} len {len(row)} != 5")
        for cell in row:
            if cell[:2] not in ("+ ", "- ") and cell[0] in "+-":
                failures.append(f"monster cell malformed: {cell!r}")
    if len(MONSTER_ENV_FORMULA) != 10:
        failures.append("env formula must cover rows 1..10")
    encs = [monster_encounter(d(10)) for _ in range(N)]
    boss_rate = sum(e["boss"] for e in encs) / N
    if abs(boss_rate - 0.10) > 0.005:
        failures.append(f"boss rate {boss_rate:.4f} != ~0.10")
    diff = Counter(e["difficulty"] for e in encs)
    if abs(diff["Easy"]/N - 0.4) > 0.01 or abs(diff["Hard"]/N - 0.2) > 0.01:
        failures.append("difficulty bands off (want 40/40/20)")
    if not any(e["row"] == "*" for e in (monster_encounter(6) for _ in range(5000))):
        failures.append("forest special row never reached from env 6")
```

- [ ] **Step 4: Run the build to verify failure-free**

Run: `python3 build_oracle.py`
Expected: `All engine verifications passed.` (emission test comes in Task 4)

- [ ] **Step 5: Commit**

```bash
git add build_oracle.py
git commit -m "feat: encode wilderness monster encounter grid, PDF-verified"
```

### Task 3: Encode dialog grid in build_oracle.py

**Files:**
- Modify: `build_oracle.py` (data after `MONSTER_ENV_FORMULA`; checks in `verify()`; emission in Task 4)

- [ ] **Step 1: Add the data (corrected per Task 1)**

```python
# NPC Dialog 5x5 grid walk, verified vs PDF. Marker starts center (2,2).
# Rows 0-1 are past tense; rows 2-4 present (instructions p96).
DIALOG_GRID = [
    ["Fact", "Denial", "Query", "Denial", "Action"],
    ["Want", "Query", "Need", "Query", "Fact"],
    ["Action", "Need", "Fact", "Action", "Denial"],
    ["Need", "Query", "Denial", "Query", "Want"],
    ["Query", "Support", "Query", "Support", "Need"],
]
# d10 die 1 -> (tone, drow, dcol); die 2 -> subject.
DIALOG_DIRECTION = [  # (max_roll, tone, drow, dcol)
    (2, "Neutral", -1, 0), (5, "Defensive", 0, -1),
    (8, "Aggressive", 0, 1), (10, "Helpful", 1, 0),
]
DIALOG_SUBJECT = [(2, "Them"), (5, "Me"), (8, "You"), (10, "Us")]
```

- [ ] **Step 2: Add verification checks inside `verify()`**

```python
    # 7. Dialog grid shape and anchor.
    if len(DIALOG_GRID) != 5 or any(len(r) != 5 for r in DIALOG_GRID):
        failures.append("dialog grid not 5x5")
    if DIALOG_GRID[2][2] != "Fact":
        failures.append("dialog grid center must be Fact")
    if DIALOG_DIRECTION[-1][0] != 10 or DIALOG_SUBJECT[-1][0] != 10:
        failures.append("dialog bands must cover 1..10")
```

- [ ] **Step 3: Run the build**

Run: `python3 build_oracle.py`
Expected: `All engine verifications passed.`

- [ ] **Step 4: Commit**

```bash
git add build_oracle.py
git commit -m "feat: encode NPC dialog 5x5 grid, PDF-verified"
```

### Task 4: Emit new data and refresh the asset

**Files:**
- Modify: `build_oracle.py:481-505` (`emit_json`)
- Modify: `assets/oracle_data.json` (regenerated, not hand-edited)

- [ ] **Step 1: Extend `emit_json` data dict (after the `"ext"` entry)**

```python
        "monster_encounter": {
            "grid": MONSTER_GRID,
            "env_formula": {str(k): list(v) for k, v in MONSTER_ENV_FORMULA.items()},
        },
        "dialog": {
            "grid": DIALOG_GRID,
            "direction": [list(x) for x in DIALOG_DIRECTION],
            "subject": [list(x) for x in DIALOG_SUBJECT],
        },
```

- [ ] **Step 2: Regenerate and copy the asset**

```bash
python3 build_oracle.py && cp oracle_data.json assets/oracle_data.json
python3 -c "import json; d=json.load(open('assets/oracle_data.json')); print(sorted(d)); print(len(d['dialog']['grid']), len(d['monster_encounter']['grid']))"
```

Expected: key list includes `dialog` and `monster_encounter`; prints `5 12`.

- [ ] **Step 3: Commit**

```bash
git add build_oracle.py assets/oracle_data.json
git commit -m "feat: emit monster encounter + dialog data into oracle asset"
```

### Task 5: Dart accessors (failing test first)

**Files:**
- Modify: `test/fate_engine_test.dart` (append a group)
- Modify: `lib/engine/oracle_data.dart` (append getters before `allTableKeys`)

- [ ] **Step 1: Write the failing test**

Append to `test/fate_engine_test.dart` (it already loads `OracleData` from the
asset in `setUpAll` — reuse that instance, named `data` there):

```dart
  group('Monster encounter + dialog data integrity', () {
    test('monster grid is 12 rows of 5', () {
      expect(data.monsterGrid.length, 12);
      for (final row in data.monsterGrid.values) {
        expect(row.length, 5);
      }
      expect(data.monsterEnvFormula.length, 10);
    });

    test('dialog grid is 5x5 with Fact center', () {
      expect(data.dialogGrid.length, 5);
      for (final row in data.dialogGrid) {
        expect(row.length, 5);
      }
      expect(data.dialogGrid[2][2], 'Fact');
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/fate_engine_test.dart`
Expected: FAIL — `monsterGrid` getter not defined.

- [ ] **Step 3: Add the accessors to `lib/engine/oracle_data.dart`**

```dart
  // Monster encounter ------------------------------------------------------
  Map<String, dynamic> get _monster =>
      _json['monster_encounter'] as Map<String, dynamic>;

  /// Row key ('1'..'0', '*', '**') -> 5 cells (tracks, easy, medium, hard, boss).
  Map<String, List<String>> get monsterGrid =>
      (_monster['grid'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as List).cast<String>()));

  /// Env row '1'..'10' -> [modifier, skew].
  Map<String, List<int>> get monsterEnvFormula =>
      (_monster['env_formula'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as List).cast<int>()));

  // NPC dialog ---------------------------------------------------------------
  Map<String, dynamic> get _dialog => _json['dialog'] as Map<String, dynamic>;

  /// 5x5 fragment grid; rows 0-1 are past tense.
  List<List<String>> get dialogGrid => (_dialog['grid'] as List)
      .map((r) => (r as List).cast<String>())
      .toList();

  /// [maxRoll, tone, dRow, dCol] bands for die 1.
  List<List<dynamic>> get dialogDirection =>
      (_dialog['direction'] as List).map((e) => e as List).toList();

  /// [maxRoll, subject] bands for die 2.
  List<List<dynamic>> get dialogSubject =>
      (_dialog['subject'] as List).map((e) => e as List).toList();
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/fate_engine_test.dart`
Expected: PASS, all groups.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle_data.dart test/fate_engine_test.dart
git commit -m "feat: typed accessors for monster encounter and dialog data"
```

### Task 6: Dart engine — monster encounter (failing test first)

**Files:**
- Modify: `test/fate_engine_test.dart` (append a group)
- Modify: `lib/engine/oracle.dart` (new methods after `dialogTopic()` at the end of the composite-generators section)

- [ ] **Step 1: Write the failing test**

```dart
  group('Monster encounter generator', () {
    test('always yields difficulty, environment, and at least a boss-or-mob list', () {
      final oracle = Oracle(data);
      for (var i = 0; i < 2000; i++) {
        final r = oracle.monsterEncounter();
        expect(r.title, 'Monster Encounter');
        expect(r.rolls, isNotEmpty);
        final labels = r.rolls.map((x) => x.label).toList();
        expect(labels, contains('Environment'));
        expect(labels, contains('Difficulty'));
      }
    });

    test('boss appears roughly 10% of the time', () {
      final oracle = Oracle(data);
      var bosses = 0;
      const n = 20000;
      for (var i = 0; i < n; i++) {
        final r = oracle.monsterEncounter();
        if (r.rolls.any((x) => x.label == 'Boss')) bosses++;
      }
      expect(bosses / n, closeTo(0.10, 0.01));
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/fate_engine_test.dart`
Expected: FAIL — `monsterEncounter` not defined.

- [ ] **Step 3: Implement in `lib/engine/oracle.dart`**

```dart
  /// Wilderness Monster Encounter (pocketfold left extension). Rolls the
  /// current environment too; pass [envRow] (1..10) to pin it instead.
  GenResult monsterEncounter({int? envRow}) {
    final env = envRow ?? dice.d10Index();
    final envName = data.table('wilderness_environment')[env - 1];
    final formula = data.monsterEnvFormula['$env']!; // [modifier, skew]
    final mod = formula[0], skew = formula[1];
    final a = dice.dN(6), b = dice.dN(6);
    final pick = skew > 0
        ? (a > b ? a : b)
        : skew < 0
            ? (a < b ? a : b)
            : a;
    String rowKey;
    if (skew != 0 && a == b) {
      rowKey = '**'; // doubles: bandits, any biome
    } else {
      final row = (pick + mod).clamp(1, 10);
      rowKey = row == 10 ? '0' : '$row';
      if (env == 6 && row == 6) rowKey = '*'; // Forest special: blights
    }
    final gridRow = data.monsterGrid[rowKey]!;
    final d1 = dice.dN(10), d2 = dice.dN(10);
    final band = d1 <= 4 ? 2 : (d1 <= 8 ? 3 : 4);
    final difficulty = const {2: 'Easy', 3: 'Medium', 4: 'Hard'}[band]!;
    final rolls = <Roll>[
      Roll(label: 'Environment', value: envName, detail: 'd10 ${d10Label(env)}'),
      Roll(label: 'Difficulty', value: difficulty, detail: 'd10 ${d10Label(d1)}'),
    ];
    for (final cell in gridRow.take(band)) {
      final hasPrefix = cell.startsWith('+ ') || cell.startsWith('- ');
      final prefix = hasPrefix ? cell[0] : '';
      final name = hasPrefix ? cell.substring(2) : cell;
      final q1 = dice.dN(6), q2 = dice.dN(6);
      final qty = (prefix == '+'
              ? (q1 > q2 ? q1 : q2)
              : prefix == '-'
                  ? (q1 < q2 ? q1 : q2)
                  : q1) -
          1;
      if (qty > 0) {
        rolls.add(Roll(label: 'Monster', value: '$qty× $name'));
      }
    }
    if (d1 == d2) {
      rolls.add(Roll(label: 'Boss', value: gridRow[4]));
    }
    if (!rolls.any((r) => r.label == 'Monster' || r.label == 'Boss')) {
      rolls.add(const Roll(label: 'Monster', value: 'None — signs only'));
    }
    return GenResult(title: 'Monster Encounter', rolls: rolls);
  }

  /// Creature tracks only: environment-tuned monster type, no difficulty.
  GenResult creatureTracks({int? envRow}) {
    final full = monsterEncounter(envRow: envRow);
    final env = full.rolls.firstWhere((r) => r.label == 'Environment');
    // Re-derive the row monster name cheaply: roll again honestly.
    final envIdx = envRow ?? dice.d10Index();
    final formula = data.monsterEnvFormula['$envIdx']!;
    final a = dice.dN(6), b = dice.dN(6);
    final pick = formula[1] > 0
        ? (a > b ? a : b)
        : formula[1] < 0
            ? (a < b ? a : b)
            : a;
    String rowKey;
    if (formula[1] != 0 && a == b) {
      rowKey = '**';
    } else {
      final row = (pick + formula[0]).clamp(1, 10);
      rowKey = row == 10 ? '0' : '$row';
      if (envIdx == 6 && row == 6) rowKey = '*';
    }
    final cell = data.monsterGrid[rowKey]![0];
    final name = cell.startsWith('+ ') || cell.startsWith('- ')
        ? cell.substring(2)
        : cell;
    return GenResult(title: 'Creature Tracks', rolls: [
      env,
      Roll(label: 'Tracks', value: name),
    ]);
  }
```

(Self-review note: `creatureTracks` above re-rolls rather than sharing the row
with `monsterEncounter` — extract the row-pick into a private
`String _monsterRowKey(int envRow)` helper and call it from both methods
instead of duplicating; the duplication shown here is for completeness of
both call paths.)

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/fate_engine_test.dart`
Expected: PASS (boss-rate test included).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle.dart test/fate_engine_test.dart
git commit -m "feat: monster encounter + creature tracks generators in Dart engine"
```

### Task 7: Dart engine — dialog walk (failing test first)

**Files:**
- Modify: `test/fate_engine_test.dart` (append a group)
- Modify: `lib/engine/oracle.dart` (state field + method)

- [ ] **Step 1: Write the failing test**

```dart
  group('NPC dialog walk', () {
    test('walks the grid, wraps, and ends on doubles', () {
      final oracle = Oracle(data);
      var sawEnd = false;
      var sawPast = false;
      var sawPresent = false;
      for (var i = 0; i < 2000; i++) {
        final r = oracle.npcDialog();
        if (r.summary == 'Conversation ends') {
          sawEnd = true;
          continue;
        }
        final labels = r.rolls.map((x) => x.label).toList();
        expect(labels, containsAll(['Fragment', 'Tone', 'Subject']));
        final tense =
            r.rolls.firstWhere((x) => x.label == 'Fragment').detail!;
        if (tense.contains('past')) sawPast = true;
        if (tense.contains('present')) sawPresent = true;
      }
      expect(sawEnd, isTrue, reason: 'doubles (10%) must end conversations');
      expect(sawPast && sawPresent, isTrue,
          reason: 'walk must reach both tense bands over 2000 beats');
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/fate_engine_test.dart`
Expected: FAIL — `npcDialog` not defined.

- [ ] **Step 3: Implement in `lib/engine/oracle.dart`**

Add the state field next to the `data`/`dice` fields:

```dart
  /// NPC dialog marker (row, col) on the 5x5 grid; starts and resets at
  /// center "Fact". In-memory only — persisted state arrives with the
  /// crawl-modes work.
  int _dialogRow = 2, _dialogCol = 2;
```

Add the method after `dialogTopic()`:

```dart
  /// One beat of NPC dialog: move the marker, read the fragment.
  /// Doubles end the conversation and reset the marker (instructions p96).
  GenResult npcDialog() {
    final d1 = dice.dN(10), d2 = dice.dN(10);
    if (d1 == d2) {
      _dialogRow = 2;
      _dialogCol = 2;
      return GenResult(
        title: 'NPC Dialog',
        summary: 'Conversation ends',
        rolls: [
          Roll(label: 'Dice', value: '$d1, $d2', detail: 'doubles'),
        ],
      );
    }
    final dir = data.dialogDirection
        .firstWhere((band) => d1 <= (band[0] as int));
    final tone = dir[1] as String;
    _dialogRow = (_dialogRow + (dir[2] as int)) % 5;
    _dialogCol = (_dialogCol + (dir[3] as int)) % 5;
    if (_dialogRow < 0) _dialogRow += 5;
    if (_dialogCol < 0) _dialogCol += 5;
    final subject = data.dialogSubject
        .firstWhere((band) => d2 <= (band[0] as int))[1] as String;
    final fragment = data.dialogGrid[_dialogRow][_dialogCol];
    final tense = _dialogRow <= 1 ? 'past' : 'present';
    return GenResult(title: 'NPC Dialog', rolls: [
      Roll(label: 'Fragment', value: fragment, detail: tense),
      Roll(label: 'Tone', value: tone, detail: 'd10 ${d10Label(d1)}'),
      Roll(label: 'Subject', value: subject, detail: 'd10 ${d10Label(d2)}'),
    ]);
  }
```

(Dart `%` on a negative int already returns a non-negative result, so the two
`if (< 0)` guards are redundant — keep or drop them, but if dropped, say so in
the commit body.)

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/fate_engine_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle.dart test/fate_engine_test.dart
git commit -m "feat: stateful NPC dialog grid walk in Dart engine"
```

### Task 8: Wire generators into the UI

**Files:**
- Modify: `lib/features/generators_screen.dart:27-55` (`_gens` list)

- [ ] **Step 1: Register the three new generators**

Insert after the `'Natural Hazard'` entry:

```dart
    _Gen('Monster Encounter', (o) => o.monsterEncounter()),
    _Gen('Creature Tracks', (o) => o.creatureTracks()),
```

Insert after the `'NPC Dialog Topic'` entry:

```dart
    _Gen('NPC Dialog', (o) => o.npcDialog()),
```

- [ ] **Step 2: Analyze + full test suite**

Run: `flutter analyze && flutter test`
Expected: no new analyze issues; all tests pass.

- [ ] **Step 3: Run the app and exercise both generators**

Build + serve via the existing preview config:
`flutter build web && (preview_start name=flutter-web)` — tap Generators →
Monster Encounter and NPC Dialog via the semantics tree, confirm result cards
render (Environment/Difficulty/Monster rows; Fragment/Tone/Subject rows).

- [ ] **Step 4: Commit**

```bash
git add lib/features/generators_screen.dart
git commit -m "feat: surface monster encounter, creature tracks, NPC dialog generators"
```

### Task 9: Documentation sync

**Files:**
- Modify: `README.md:71-88` (flagged-tables section)
- Modify: `CLAUDE.md` (project notes, only if generator count is mentioned)

- [ ] **Step 1: Update the README flagged list**

Remove the two bullets at `README.md:76-80` (monster grid, dialog grid).
Replace with one line above the remaining bullets:

```markdown
- ~~Wilderness Monster Encounter grid~~ / ~~NPC Dialog grid~~ — encoded and
  verified against the PDF (see `build_oracle.py` verify section 6–7).
```

- [ ] **Step 2: Commit and push everything**

```bash
git add README.md CLAUDE.md
git commit -m "docs: monster + dialog grids now PDF-verified"
git push
```

- [ ] **Step 3: Confirm CI green**

Run: `gh run list --repo Taylor-Software/juice --limit 1`
Expected: `completed success` (requires the web-deploy-ci plan to have landed;
otherwise verify locally with `flutter analyze && flutter test`).

## Self-review notes

- Spec coverage: roadmap item is exactly the two grids; both encoded, both
  verified in Python (`verify()` sections 6–7), both tested in Dart, both
  surfaced in UI, docs synced. Name-generator skew, abstract icons, and
  location grid stay flagged in README (separate roadmap entries).
- Type consistency: `monsterGrid` returns `Map<String, List<String>>`; both
  Task 6 call sites index it with string keys built the same way. Dialog
  accessors return positional lists matching the Python emission order.
- Known judgment calls an executor must honor: Task 1 corrections override
  every candidate table cell; `# UNCONFIRMED:` comments are mandatory where
  the PDF is illegible; the `creatureTracks` duplication must be extracted
  into `_monsterRowKey` as noted.
