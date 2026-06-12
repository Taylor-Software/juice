# Party Emulator Phase 2 (Triple-O Check + Character.emulation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Party Emulator tool's decision engine: define a character's (or the group's) **Obvious / Option / Odd**, roll the Triple-O check or Double-Down, and let doubles grow the character's Traits — all journaled. Plus the additive `Character.emulation` state it writes to.

**Spec:** docs/superpowers/specs/2026-06-12-party-emulator-design.md (§2 "Party Emulator", §3 "Character extension"). Phase 1 already shipped `EmulatorData`/`emulatorDataProvider` and the Party group.

**Branch:** `feat/party-emulator-p2` off `main` (after PR #28 merges).

Hard rules: analyze exactly 1 pre-existing info; suite green (current count after p1: 357); TDD; exact commit messages, no co-author lines.

---

### Task 1: Model — `CharacterEmulation` (TDD)

**Files:**
- Modify: `lib/engine/models.dart` (new class + `Character.emulation` field)
- Test: extend `test/character_sheet_test.dart` (read first, match style)

Binding shape (spec §3):

```dart
class CharacterEmulation {
  const CharacterEmulation({
    this.agendaKey,        // int? 2-12 into pet.agenda
    this.focusKey,         // int? 2-12 into pet.focus
    this.mood,             // String? sidekick mood id ('default'...)
    this.tokens = 0,
    this.prominentTags = const [],
    this.usedTags = const [],
    this.hexIndex,         // int? 0-18 hexflower position
  });
  // copyWith with clearAgenda/clearFocus/clearMood/clearHex flags for the
  // nullable ints/string (house pattern: clearThreadId).
  // toJson omits null fields; fromJson tolerant (missing/junk -> defaults,
  // whereType for the lists, int guards on keys).
}
```

`Character`: `this.emulation` (nullable), `copyWith({CharacterEmulation? emulation, bool clearEmulation = false})`, toJson writes `'emulation'` ONLY when non-null (existing characters/campaign files byte-stable), tolerant fromJson.

- [ ] Steps: failing tests (round-trip incl. all fields; null omitted from
  JSON — assert `'emulation'` key absent; legacy character JSON parses;
  junk tolerated; copyWith clear flags) → implement → gates →

```bash
git add lib/engine/models.dart test/character_sheet_test.dart
git commit -m "feat: additive CharacterEmulation state on Character (null-stable JSON)"
```

---

### Task 2: Engine — Triple-O check (TDD)

**Files:**
- Modify: `lib/engine/party_emulator.dart`
- Test: extend `test/party_emulator_test.dart`

Binding API:

```dart
enum TripleOBand { obvious, option, odd }

TripleOBand bandFor(int d6); // 4-6 obvious, 2-3 option, 1 odd

class TripleOResult {
  // single roll: die != null, dice == null
  // double-down: dice != null (both), die == null; band is NOT decided
  // by the engine for double-down — the USER picks the favorite die in
  // the UI; isDoubles flags trait growth.
  final int? die;
  final (int, int)? dice;
  bool get isDoubles;
  TripleOBand? get band; // non-null only for single roll
}

TripleOResult rollTripleO(Dice dice);
TripleOResult rollDoubleDown(Dice dice);

/// Group assignment: three d6s; returns indices of [courses] ordered
/// [obvious, option, odd] = highest, middle, lowest roll. Ties broken by
/// earlier list position keeping its higher slot (deterministic).
List<int> assignCourses(Dice dice); // returns permutation of [0,1,2]
```

- [ ] Steps: failing tests (band edges 1/2/3/4/6; doubles detection;
  double-down has no band; assignCourses orderings incl. tie cases with a
  seeded Dice that produces ties) → implement → gates →

```bash
git add lib/engine/party_emulator.dart test/party_emulator_test.dart
git commit -m "feat: Triple-O check engine — bands, double-down, group assignment"
```

---

### Task 3: Party Emulator tool (TDD)

**Files:**
- Create: `lib/features/party_emulator_screen.dart`
- Modify: `lib/shared/tool_registry.dart` (ToolDef 'party-emulator', group 'Party', icon Icons.theater_comedy? — taken; use Icons.psychology_outlined, badge 'Triple-O', placed BEFORE behavior-tables)
- Tests: `test/party_emulator_screen_test.dart`; update tool_registry counts (14→15 / 15→16)

Screen behavior (spec §2; phase 2 scope only — PET buttons come in
phase 3):
- **Character picker**: dropdown of characters (charactersProvider) +
  'No one' (null). Key('pe-character').
- **Triple-O check card**: three TextFields — Key('pe-obvious') (label
  'The Obvious'), Key('pe-option'), Key('pe-odd') (both optional, hint
  '(define after the roll)'). Buttons Key('pe-roll') 'Roll d6' and
  Key('pe-double-down') 'Double-Down (2d6)'.
  - Single roll → result card: band name ('The Obvious/Option/Odd'),
    die value, the matching course text (or '(undefined — make it up
    now)' when that field was blank).
  - Double-down → result card shows BOTH dice with two buttons 'Keep N'
    (Key('pe-keep-0')/('pe-keep-1')) — picking one resolves the band from
    that die. If doubles: after resolution show a banner
    Key('pe-doubles') 'Doubles — this behavior grows' with actions:
    'Mark trait prominent' (only when a character is selected — opens a
    picker of the character's tags; chosen tag added to
    emulation.prominentTags via charactersProvider.replace) and 'Add new
    trait' (text dialog → appends to character.tags). No character →
    banner text only.
- **Group mode**: switch Key('pe-group-mode'). When on, the three fields
  are courses; button Key('pe-assign') 'Assign by dice' rolls
  assignCourses and REORDERS the field values into obvious/option/odd
  slots (showing the three dice); then the normal check applies.
- **Journal**: result card bookmark Key('pe-log') → title
  'Triple-O — The Option' (band), body lines: character name when
  selected, each course labeled, the roll(s). Doubles note included.
- Attribution footer (both lines, as behavior tables).

- [ ] Steps: failing widget tests (mock prefs with one character with
  tags; AppTheme.light(); cover: single roll renders band + course text;
  blank option rolled into → undefined hint; double-down keep flow;
  doubles banner mark-prominent writes prominentTags (read provider);
  add-new-trait appends tags; group assign reorders; journal entry title/
  body) → implement → registry/count tests → gates →

```bash
git add lib/features/party_emulator_screen.dart lib/shared/tool_registry.dart test/party_emulator_screen_test.dart test/tool_registry_test.dart
git commit -m "feat: Party Emulator tool — Triple-O check, double-down trait growth, group mode"
```

---

### Task 4: Sheet surface + docs

**Files:**
- Modify: `lib/features/tracker_screen.dart` (character sheet editor: read-only emulation summary line when emulation != null — e.g. 'Emulation: 2 prominent traits · 3 tokens'; full editing lives in the Party tool, keep this minimal)
- Modify: `README.md` (extend the Party paragraph: Triple-O check + trait growth)
- Test: one widget test in `test/character_sheet_ui_test.dart` for the summary line presence/absence.

```bash
git add lib/features/tracker_screen.dart test/character_sheet_ui_test.dart README.md
git commit -m "feat: emulation summary on character sheet; docs for the Triple-O check"
```

---

## Verification (controller)

Browser: Party Emulator → pick character → fill Obvious → Double-Down →
keep a die → (if doubles) mark trait → check tracker sheet shows summary →
journal entry. PR → CI → merge → bookkeeping.
