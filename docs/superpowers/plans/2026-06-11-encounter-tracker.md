# Encounter Tracker (Redesign Phase 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An initiative tracker tool — combatants from character sheets (live first-track link) or ad-hoc, initiative order with drag override, turn pointer + round counter, statuses/defeated, end-of-encounter summary into the journal.

**Architecture:** New `Combatant`/`EncounterState` models + an `EncounterNotifier` persisted session-scoped at `juice.encounter.v1.<sessionId>` (same shape as `CrawlNotifier`). Linked combatants don't copy HP — their track steppers read/write the character's FIRST track through `charactersProvider` (damage in the fight lands on the sheet); ad-hoc combatants carry their own `CharTrack`. The screen is a launcher tool in the existing 'Encounters & Combat' group.

**Tech Stack:** Existing rails. Spec: `docs/superpowers/specs/2026-06-11-journal-redesign-design.md` (Phase 5). Baseline: 154 tests green; `flutter analyze --no-fatal-infos` = 1 pre-existing info (models.dart dangling doc comment).

---

### Task 1: Models + notifier

**Files:**
- Modify: `lib/engine/models.dart` (after CharTrack), `lib/state/providers.dart` (after CrawlNotifier; also `sessionScopedKeys`), `lib/state/campaign_io.dart` (validation branch)
- Test: `test/encounter_test.dart`

**Models (binding):**

```dart
/// One combatant in the encounter. Linked combatants ([characterId] != null)
/// read/write the character's first track; ad-hoc ones own [track].
class Combatant {
  const Combatant({
    required this.id,
    required this.name,
    this.characterId,
    required this.initiative,
    this.track,
    this.tags = const [],
    this.defeated = false,
  });
  final String id;
  final String name;
  final String? characterId;
  final int initiative;
  final CharTrack? track; // null for linked combatants
  final List<String> tags;
  final bool defeated;

  Combatant copyWith({
    int? initiative,
    CharTrack? track,
    List<String>? tags,
    bool? defeated,
  });
  Map<String, dynamic> toJson();
  factory Combatant.fromJson(Map<String, dynamic> j); // tolerant like Character:
  // missing tags -> [], missing defeated -> false, track via CharTrack.maybeFromJson
}

/// Turn-ordered encounter. [combatants] order IS the turn order.
class EncounterState {
  const EncounterState({
    this.combatants = const [],
    this.turnIndex = 0,
    this.round = 1,
  });
  final List<Combatant> combatants;
  final int turnIndex;
  final int round;
  EncounterState copyWith({List<Combatant>? combatants, int? turnIndex, int? round});
  Map<String, dynamic> toJson();
  factory EncounterState.fromJson(Map<String, dynamic> j); // tolerant defaults
}
```

**Notifier (providers.dart, modeled on CrawlNotifier):**

```dart
class EncounterNotifier extends AsyncNotifier<EncounterState> {
  static const _baseKey = 'juice.encounter.v1';
  // build(): watch sessionsProvider, load scoped key, default EncounterState()
  // save(EncounterState): persist + state

  /// Insert keeping initiative order (descending); on ties new combatant
  /// goes AFTER existing equals. turnIndex adjusts so the current turn's
  /// combatant stays current.
  Future<void> addCombatant(Combatant c);

  /// Manual order override from drag: move oldIndex -> newIndex; turnIndex
  /// follows the combatant it pointed at.
  Future<void> reorder(int oldIndex, int newIndex);

  Future<void> updateCombatant(Combatant c); // match by id
  Future<void> removeCombatant(String id);   // turnIndex clamps/follows

  /// Advance to the next non-defeated combatant. Wrapping past the end
  /// increments round. If all combatants are defeated (or list empty): no-op.
  Future<void> nextTurn();

  Future<void> reset(); // fresh EncounterState
}
final encounterProvider = AsyncNotifierProvider<...>(EncounterNotifier.new);
```

Add `'juice.encounter.v1'` to `sessionScopedKeys` (after `'juice.crawl.v1'`). In `parseCampaign` add a validation branch: `if (key == 'juice.encounter.v1') { EncounterState.fromJson(value as Map<String, dynamic>); }` (object, not list — mirrors the crawl branch). Additive v2 key, no version bump. Session delete/export/import coverage comes free from `sessionScopedKeys`.

- [ ] **Step 1: Failing tests** (`test/encounter_test.dart`) — model round-trip + tolerant parse, and notifier behaviors against a `ProviderContainer` with mock prefs (house style from `test/journal_test.dart`):
  - round-trip: full Combatant (ad-hoc with track + tags + defeated) and linked (characterId, null track) through EncounterState.toJson/fromJson
  - tolerant: `EncounterState.fromJson({})` → empty, round 1, turn 0; combatant entry missing tags/defeated parses
  - addCombatant keeps descending initiative; tie goes after equals; turnIndex follows current (seed 3 combatants, set turnIndex 1, insert with higher initiative than all → turnIndex becomes 2)
  - nextTurn skips defeated and wraps with round++ (3 combatants, middle defeated: turn 0 → next → 2 → next → 0 with round 2)
  - nextTurn no-ops when all defeated and when empty
  - reorder moves and turnIndex follows the pointed-at combatant
  - removeCombatant: removing before the pointer shifts turnIndex down; removing the pointed combatant clamps within range
  - persistence: save then fresh container (same mock store) reloads state under same session key
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement.** nextTurn reference logic:

```dart
Future<void> nextTurn() async {
  final s = state.valueOrNull ?? await future;
  final n = s.combatants.length;
  if (n == 0 || s.combatants.every((c) => c.defeated)) return;
  var i = s.turnIndex;
  var round = s.round;
  do {
    i++;
    if (i >= n) {
      i = 0;
      round++;
    }
  } while (s.combatants[i].defeated);
  await save(s.copyWith(turnIndex: i, round: round));
}
```

(Termination guaranteed by the not-all-defeated guard.) addCombatant: find first index where `existing.initiative < c.initiative`, insert there (ties: keep scanning past equals); `turnIndex += (insertIndex <= turnIndex && combatants.isNotEmpty) ? 1 : 0` — careful with empty list (turnIndex stays 0). reorder: standard ReorderableListView index fixup (`if (newIndex > oldIndex) newIndex--`), then recompute turnIndex by tracking the previously-pointed combatant's new position (match by id; if list was empty nothing to do). removeCombatant: capture pointed id first; if removed combatant IS pointed, clamp turnIndex to `min(turnIndex, n-2)` floor 0; else recompute by id.

- [ ] **Step 4: Full** `flutter test` green; analyze 1 baseline info.
- [ ] **Step 5: Commit** `git add -A lib test && git commit -m "feat: encounter model + notifier (initiative order, turns, rounds)"`

### Task 2: Encounter screen

**Files:**
- Create: `lib/features/encounter_screen.dart`
- Test: `test/encounter_screen_test.dart`

`class EncounterScreen extends ConsumerWidget` (stateless — all state in providers). Layout: Column:

1. Header Padding Row: `Text('Round ${s.round}', titleMedium)`, Spacer, `FilledButton.tonal(key: Key('next-turn'), child: Text('Next turn'))` → `nextTurn()`, IconButton(key `Key('end-encounter')`, Icons.flag_outlined, tooltip 'End encounter') → confirm AlertDialog ('End encounter?' body 'A summary is added to the journal and the tracker resets.') → on confirm: build summary (`'Round ${s.round} — ${defeatedNames.isEmpty ? 'no combatants defeated' : 'defeated: ${defeatedNames.join(', ')}'}'` over title 'Encounter ended'), `journalProvider.notifier.add('Encounter ended', summary)`, `encounterProvider.notifier.reset()`, SnackBar 'Added to journal'.
2. Expanded ReorderableListView (`buildDefaultDragHandles: true` is fine on desktop+mobile long-press; key each row `ValueKey(c.id)`; `onReorder: notifier.reorder`). Each row a Card+ListTile:
   - leading: CircleAvatar with initiative number (greyed when defeated)
   - title: name, struck through + muted when defeated; when linked and character missing → suffix ' (missing)' and no track row
   - subtitle: track line when available — linked: read character's first track LIVE from charactersProvider; ad-hoc: own track. Rendered as Row: IconButton(key `Key('enc-minus-$i')`, remove_circle_outline), Text('${t.current}/${t.max}', key: Key('enc-track-$i')), IconButton(key `Key('enc-plus-$i')`, add_circle_outline). Linked stepper writes through: `charactersProvider.notifier.replace(char.copyWith(tracks: [first.adjusted(±1), ...rest]))`. Ad-hoc stepper: `encounterProvider.notifier.updateCombatant(c.copyWith(track: t.adjusted(±1)))`. Below (same subtitle column) a small Wrap: InputChip per tag (onDeleted → updateCombatant with tag removed) + a compact ActionChip '+' (key `Key('enc-tag-add-$i')`) → dialog with field key `Key('enc-tag-input')` Cancel/Add (trimmed, dedup) → updateCombatant with tag appended.
   - trailing: Row(min): IconButton skull/defeated toggle (Icons.heart_broken_outlined when alive → tooltip 'Mark defeated'; Icons.favorite_outline when defeated → 'Revive'; key `Key('enc-defeat-$i')`) → updateCombatant(copyWith(defeated: !)); IconButton delete_outline → removeCombatant. Turn pointer: the row at `s.turnIndex` gets `selected: true` + leading avatar emphasized (primaryContainer).
3. Bottom Padding Row of two OutlinedButton.icon: key `Key('add-character')` 'From characters' → dialog listing characters not already linked (ListTiles; tap → addCombatant(Combatant(id: new, name: c.name, characterId: c.id, initiative: from a small initiative field at the top of the dialog — default 10, key `Key('init-input')`))); empty state text when none left. Key `Key('add-adhoc')` 'Ad-hoc' → dialog: name (key `Key('adhoc-name')`), HP max (number, key `Key('adhoc-hp')`, floor 1, track starts full), initiative (number, key `Key('adhoc-init')`, default 10) → addCombatant with own track.

Empty state (no combatants): centered helper text 'No combatants. Add from your characters or ad-hoc.' (list area only; header+buttons still shown).

- [ ] **Step 1: Failing tests** (`test/encounter_screen_test.dart`) — house pump style (mock prefs with session + seeded characters + seeded encounter where useful; `ProviderScope`/`MaterialApp`/`Scaffold(body: EncounterScreen())`):
  - seeded ad-hoc combatants render in initiative order with round header; turn row 0 selected
  - Next turn advances pointer and skips a defeated combatant; wrap increments the round header
  - ad-hoc stepper updates `enc-track-$i` text and persists via container read of encounterProvider
  - linked combatant stepper writes through to the character (seed character 'Ash' HP 7/10, encounter with linked combatant; tap `enc-plus-0`; expect charactersProvider single .tracks.single.current == 8 and UI '8/10')
  - End encounter: tap `end-encounter`, confirm dialog button 'End', expect journalProvider single entry title 'Encounter ended' and encounterProvider reset (combatants empty, round 1)
  - defeat toggle greys/struck name and Next skips it
  - status tag add via `enc-tag-add-0` dialog persists on the combatant; chip delete removes it
- [ ] **Step 2: Run** — FAIL (file missing).
- [ ] **Step 3: Implement** per layout above.
- [ ] **Step 4: Full** `flutter test` green; analyze no new infos.
- [ ] **Step 5: Commit** `git add -A lib test && git commit -m "feat: encounter tracker screen (initiative, turns, live sheet link, journal summary)"`

### Task 3: Registry + docs + ship (controller-run)

- [ ] Registry entry in `lib/shared/tool_registry.dart` ('Encounters & Combat' group, after gen-encounters):

```dart
ToolDef(
  id: 'encounter',
  label: 'Encounter Tracker',
  icon: Icons.shield_outlined,
  group: 'Encounters & Combat',
  builder: (_) => const EncounterScreen(),
),
```

- [ ] `test/tool_registry_test.dart`: counts 11→12 / 12→13; add 'encounter' to core ids.
- [ ] Gates: analyze, `flutter test`, `python3 build_oracle.py`, `flutter build web`.
- [ ] Browser verify (seed localStorage: session + characters + encounter state): rows render in order, Next turn moves pointer + round wraps, linked stepper updates character storage, End encounter writes journal entry + resets. Dialog typing headless-impossible — covered by widget tests; disclose.
- [ ] README: feature sentence (encounter tracker: initiative, rounds, statuses, sheet-linked HP, journal summary). ROADMAP: phase 5 Done; phase 6 next.
- [ ] PR `feat/encounter-tracker`, CI green BEFORE merge, squash-merge, deploy verify.
