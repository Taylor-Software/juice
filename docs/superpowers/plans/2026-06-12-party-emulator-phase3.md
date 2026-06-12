# Party Emulator Phase 3 (PET Procedures) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The PET (Player Emulator with Tags) procedures on the Party Emulator tool: a per-character emulation panel (Agenda / Focus / tokens) and the ACT, REFOCUS, Tag-spend, Session-start, and Consequence procedures — all journaled, all persisting through `Character.emulation` (phase 2).

**Spec:** docs/superpowers/specs/2026-06-12-party-emulator-design.md (§2 "Party Emulator" PET bullet, §3). Phase 2 shipped `CharacterEmulation` (agendaKey/focusKey/tokens/usedTags), the Party Emulator screen, and `charactersProvider.replace` write paths.

**Branch:** `feat/party-emulator-p3` off `main` (after PR #29 merges).

Hard rules: analyze exactly 1 pre-existing info (lib/engine/models.dart:2); suite green (current count after p2: 382); TDD; exact commit messages, no co-author lines; no new dependencies.

**Asset shape** (already shipped, `assets/emulator_data.json`): `pet.agenda` keys '2'..'12' → `{group, name, ask, flavor}`; `pet.focus` keys '2'..'12' → `{name, blurb}`; `pet.personality_tags` [36]; `pet.consequences` [6]; `pet.real_life` [6].

---

### Task 1: Engine — PET accessors + rollers (TDD)

**Files:**
- Modify: `lib/engine/emulator_data.dart`
- Modify: `lib/engine/party_emulator.dart`
- Tests: extend `test/emulator_data_test.dart`, `test/party_emulator_test.dart`

Binding API (emulator_data.dart):

```dart
class AgendaEntry { final int key; final String group, name, ask, flavor; }
class FocusEntry  { final int key; final String name, blurb; }

AgendaEntry agendaEntry(int key); // 2-12; ArgumentError outside
FocusEntry focusEntry(int key);   // 2-12; ArgumentError outside
List<String> get personalityTags; // 36
List<String> get consequences;    // 6
List<String> get realLife;        // 6
```

Binding API (party_emulator.dart):

```dart
/// 2d6 curved roll for agenda/focus keys (the in-play method; the source's
/// flat-d12 creation variant is not surfaced in UI and is out of scope).
int roll2d6Key(Dice dice); // sum of two d6 → 2..12

enum ActMode { asWritten, inverted, exaggerated }

class ActResult {
  final int agendaKey;     // 2d6
  final bool heads;        // coin: true = Ask as written, false = inverted
  final int modifierDie;   // d6: 1-2 asWritten, 3-4 inverted, 5-6 exaggerated
  ActMode get modifier;
  /// Combined reading per Pettish: coin sets the base reading of the Ask,
  /// the modifier die layers as-written/inverted/exaggerated guidance.
}

ActResult rollAct(Dice dice);
String actModeLabel(ActMode m); // 'as written' / 'inverted' / 'exaggerated'
```

- [ ] Steps: failing tests (agendaEntry(2).name == 'DRAMA', ask text pinned;
  focusEntry(2).name == 'PLAYFUL'; agendaEntry(13)/focusEntry(1) throw;
  personalityTags length 36 first 'chatty'; consequences[0] 'expose a
  weakness'; realLife[5] 'victorious'; roll2d6Key seeded determinism + range
  2-12 over 200 rolls; rollAct seeded: agendaKey/heads/modifierDie all from
  the same Dice in documented order — agenda 2d6, coin d2, modifier d6;
  modifier banding 1/2→asWritten 3/4→inverted 5/6→exaggerated) → implement →
  gates →

```bash
git add lib/engine/emulator_data.dart lib/engine/party_emulator.dart test/emulator_data_test.dart test/party_emulator_test.dart
git commit -m "feat: PET engine — agenda/focus accessors, ACT coin + modifier roller"
```

---

### Task 2: Emulation panel + PET procedures UI (TDD)

**Files:**
- Modify: `lib/features/party_emulator_screen.dart`
- Tests: extend `test/party_emulator_screen_test.dart`

Screen additions (between the character picker and the Triple-O card):

- **Emulation panel** Key('pe-emulation') — always visible; reads the
  selected character's `emulation` (or a transient in-screen
  `CharacterEmulation` when 'No one', mirroring phase-2 patterns):
  - Agenda line: `Agenda: DRAMA — Ask: what would be the worst thing…`
    (name + ask; em-dash separator) or `Agenda: —` when null.
  - Focus line: `Focus: PLAYFUL — a focus on relaxing…` (name + blurb,
    blurb ellipsized by Text overflow) or `Focus: —`.
  - Tokens row: `Tokens: N` with − / + IconButtons
    Key('pe-token-minus') / Key('pe-token-plus'); minus clamps at 0.
  - Buttons: Key('pe-roll-agenda') 'Roll Agenda', Key('pe-roll-focus')
    'Roll Focus' — 2d6 via roll2d6Key; persist via
    `emulation.copyWith(agendaKey/focusKey)` + `charactersProvider.replace`
    (create `CharacterEmulation()` when null, phase-2 pattern). For
    'No one' update the transient state only.
- **PET actions card** Key('pe-pet-actions') with four buttons:
  - Key('pe-act') 'ACT': `rollAct`; if the character has no agenda set,
    first set the rolled agendaKey (and say so in the result); if the
    rolled agendaKey EQUALS the character's current agendaKey → +1 token
    (persisted) and the result notes 'Agenda match — +1 token'. Result
    card Key('pe-pet-result') shows: agenda name, the Ask (as written or
    with '(inverted)' suffix per the coin), modifier line
    'Modifier: exaggerated' per the die, the raw rolls.
  - Key('pe-refocus') 'REFOCUS': roll2d6Key → set focusKey (persist);
    result card shows new focus name + blurb.
  - Key('pe-tag-spend') 'Spend tag': enabled only when the selected
    character has at least one tag not in `usedTags`; opens a
    SimpleDialog picker (house pattern) of unspent tags; on pick: roll
    TWO ActResults, result card shows both readings side-labeled
    'Reading 1' / 'Reading 2' plus 'Spent: <tag>'; add tag to
    `usedTags` (persist). No agenda-match token on tag-spend rolls.
  - Key('pe-session-start') 'Session start': roll2d6Key for a new Focus
    + d6 over `realLife` ('Real life: stressed'); CLEARS `usedTags`;
    persists; result card shows both lines.
  - Key('pe-consequence') 'Consequence': d6 over `consequences`; result
    card line 'Consequence: take it away'. No persistence.
- **Journal**: the PET result card gets a bookmark Key('pe-pet-log').
  Titles: `ACT — DRAMA (inverted)` (mode = coin reading), `REFOCUS —
  PLAYFUL`, `Tag spend — <tag>`, `Session start`, `Consequence`. Body:
  the result card's lines (character name first when selected).
- Sheet summary (tracker_screen) needs no change — counts update via the
  same `emulation` writes.

- [ ] Steps: failing widget tests (seeded Dice injection from phase 2;
  cover: roll-agenda persists agendaKey and renders name+ask;
  roll-focus persists; token +/− clamps at 0 and persists; ACT
  agenda-match grants token and notes it (seed the character's
  agendaKey to the value the seeded dice will roll); ACT no-match
  grants none; ACT with null agenda sets it; refocus persists; tag
  spend: button disabled when all tags used, picker lists only unspent,
  marks used, two readings render; session start clears usedTags +
  shows real-life line; consequence renders; journal entries for ACT
  and tag-spend titles/bodies; 'No one' transient: rolls render but
  charactersProvider state unchanged) → implement → gates →

```bash
git add lib/features/party_emulator_screen.dart test/party_emulator_screen_test.dart
git commit -m "feat: PET procedures — emulation panel, ACT/REFOCUS/tag spend/session start/consequences"
```

---

### Task 3: Docs

**Files:**
- Modify: `README.md` (extend the Party paragraph: PET procedures sentence — agendas/focuses/tokens, ACT coin+modifier, tag spend, session start; PET attribution already present)

```bash
git add README.md
git commit -m "docs: PET procedures on the Party Emulator"
```

---

## Verification (controller)

Browser: Party Emulator → pick character → Roll Agenda/Focus → ACT (match
& token) → Spend tag → Session start (usedTags reset) → journal entries →
sheet tokens count. PR → CI → merge → bookkeeping.
