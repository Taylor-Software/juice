# Card Jokers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in 54-card standard deck (the two jokers as name-only identity cards) to the card oracle.

**Architecture:** Two facts-only constants (`kPlayingJokers`, `kPlayingDeckWithJokers`) + a persisted `DecksState.jokers` flag. `DecksNotifier.draw` picks the 52- or 54-card list by the flag; `setJokers` toggles it and resets the standard deck. A `FilterChip` in the Cards section flips it and the readout denominator follows. No art, no mechanic.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Reuses `Oracle.drawCard` (auto-reshuffles on deck-size change), `decksProvider`, the Cards section in `fate_screen`.

---

## File Structure

- **Modify** `lib/engine/models.dart` — `kPlayingJokers`, `kPlayingDeckWithJokers`; `DecksState.jokers` (+ copyWith/toJson/fromJson).
- **Modify** `lib/state/providers.dart` — `_standardDeck` selection in `DecksNotifier.draw`; `setJokers`.
- **Modify** `lib/features/fate_screen.dart` — jokers `FilterChip` + readout denominator.
- **Modify** `test/card_oracle_test.dart` — deck consts + `DecksState.jokers` JSON + `setJokers`/draw provider tests.
- **Modify** `test/fate_cards_test.dart` — toggle widget test.

---

## Task 1: Data + DecksState.jokers

**Files:**
- Modify: `lib/engine/models.dart`
- Test: `test/card_oracle_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/card_oracle_test.dart` inside `void main()` (after the existing tests; the file already imports `models.dart`):

```dart
  group('jokers deck + state', () {
    test('kPlayingDeckWithJokers is 54 with both jokers; base deck stays 52', () {
      expect(kPlayingDeck, hasLength(52));
      expect(kPlayingDeckWithJokers, hasLength(54));
      expect(kPlayingDeckWithJokers, containsAll(['Red Joker', 'Black Joker']));
      expect(kPlayingDeckWithJokers.take(52), kPlayingDeck); // jokers appended
    });

    test('DecksState.jokers round-trips; missing key defaults false', () {
      const on = DecksState(jokers: true);
      expect(DecksState.fromJson(on.toJson()).jokers, isTrue);
      // A legacy payload with no 'jokers' key → false.
      final legacy = DecksState.fromJson(const {
        'standard': {'order': <int>[], 'drawn': 0},
        'tarot': {'order': <int>[], 'drawn': 0},
      });
      expect(legacy.jokers, isFalse);
      // copyWith preserves the flag.
      expect(const DecksState().copyWith(jokers: true).jokers, isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/card_oracle_test.dart`
Expected: FAIL — `kPlayingJokers`/`kPlayingDeckWithJokers`/`DecksState.jokers` undefined.

- [ ] **Step 3: Implement**

In `lib/engine/models.dart`:

(a) After the `kPlayingDeck` definition (the `final List<String> kPlayingDeck = [ ... ];` block near line 2333), add:

```dart
/// The two jokers, by identity only (no asserted meaning). Used by the opt-in
/// 54-card variant.
const kPlayingJokers = ['Red Joker', 'Black Joker'];

/// The standard deck plus the two jokers (54 cards), for the opt-in variant.
final List<String> kPlayingDeckWithJokers = [...kPlayingDeck, ...kPlayingJokers];
```

(b) In `DecksState`, add the `jokers` field. Change:

```dart
  const DecksState({
    this.standard = const DeckState(),
    this.tarot = const DeckState(),
  });
  final DeckState standard;
  final DeckState tarot;

  DecksState copyWith({DeckState? standard, DeckState? tarot}) => DecksState(
        standard: standard ?? this.standard,
        tarot: tarot ?? this.tarot,
      );

  Map<String, dynamic> toJson() =>
      {'standard': standard.toJson(), 'tarot': tarot.toJson()};

  factory DecksState.fromJson(Map<String, dynamic> j) => DecksState(
        standard: DeckState.fromJson(j['standard']),
        tarot: DeckState.fromJson(j['tarot']),
      );
```

to:

```dart
  const DecksState({
    this.standard = const DeckState(),
    this.tarot = const DeckState(),
    this.jokers = false,
  });
  final DeckState standard;
  final DeckState tarot;
  final bool jokers;

  DecksState copyWith({DeckState? standard, DeckState? tarot, bool? jokers}) =>
      DecksState(
        standard: standard ?? this.standard,
        tarot: tarot ?? this.tarot,
        jokers: jokers ?? this.jokers,
      );

  Map<String, dynamic> toJson() => {
        'standard': standard.toJson(),
        'tarot': tarot.toJson(),
        'jokers': jokers,
      };

  factory DecksState.fromJson(Map<String, dynamic> j) => DecksState(
        standard: DeckState.fromJson(j['standard']),
        tarot: DeckState.fromJson(j['tarot']),
        jokers: j['jokers'] == true, // tolerant: missing/non-bool → false
      );
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/card_oracle_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/models.dart test/card_oracle_test.dart
git commit -m "feat(cards): jokers deck constants + DecksState.jokers flag

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Draw selection + setJokers

**Files:**
- Modify: `lib/state/providers.dart`
- Test: `test/card_oracle_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/card_oracle_test.dart` inside the existing `group('DecksNotifier', ...)` block (after the last test, before the group's closing `});`):

```dart
    test('setJokers persists the flag, resets the standard deck, and draws 54',
        () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final oracle = Oracle(data, Dice(Random(4)));
      final c = ProviderContainer(
          overrides: [oracleProvider.overrideWith((ref) async => oracle)]);
      addTearDown(c.dispose);
      await c.read(decksProvider.future);

      // Default off → standard draw builds a 52-card order.
      await c.read(decksProvider.notifier).draw(oracle, tarot: false);
      expect(c.read(decksProvider).valueOrNull!.standard.order, hasLength(52));

      // Turn jokers on: flag persists and the standard deck resets.
      await c.read(decksProvider.notifier).setJokers(true);
      final afterToggle = c.read(decksProvider).valueOrNull!;
      expect(afterToggle.jokers, isTrue);
      expect(afterToggle.standard.order, isEmpty); // reset

      // Next standard draw builds a 54-card order.
      await c.read(decksProvider.notifier).draw(oracle, tarot: false);
      expect(c.read(decksProvider).valueOrNull!.standard.order, hasLength(54));
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/card_oracle_test.dart`
Expected: FAIL — `setJokers` undefined; draw still uses the 52-card deck.

- [ ] **Step 3: Implement**

In `lib/state/providers.dart`, `DecksNotifier`:

(a) Add the deck-selection helper (place it just above the `draw` method):

```dart
  List<String> _standardDeck(DecksState s) =>
      s.jokers ? kPlayingDeckWithJokers : kPlayingDeck;
```

(b) In `draw`, change the `deck:` argument of the `oracle.drawCard(...)` call from:

```dart
      deck: tarot ? kTarotDeck : kPlayingDeck,
```

to:

```dart
      deck: tarot ? kTarotDeck : _standardDeck(cur),
```

(c) Add `setJokers` (place it beside `reshuffle`):

```dart
  /// Toggles the jokers variant for the standard deck, resetting the standard
  /// DeckState so the next draw reshuffles a full 52- or 54-card deck (keeps the
  /// remaining-readout denominator coherent).
  Future<void> setJokers(bool value) async {
    final cur = state.valueOrNull ?? await future;
    await _save(cur.copyWith(jokers: value, standard: const DeckState()));
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/card_oracle_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/card_oracle_test.dart
git commit -m "feat(cards): DecksNotifier jokers draw selection + setJokers

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Cards-section toggle + readout

**Files:**
- Modify: `lib/features/fate_screen.dart`
- Test: `test/fate_cards_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/fate_cards_test.dart` inside `void main()` (after the existing tests; the file already has `pumpFate`):

```dart
  testWidgets('jokers toggle switches the standard deck readout to /54',
      (tester) async {
    await pumpFate(tester);
    expect(find.textContaining('/52'), findsOneWidget); // default 52
    await tester.tap(find.byKey(const Key('cards-jokers-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('/54'), findsOneWidget); // jokers on
    expect(find.textContaining('/52'), findsNothing);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/fate_cards_test.dart`
Expected: FAIL — no `cards-jokers-toggle`; readout is always `/52`.

- [ ] **Step 3: Implement**

In `lib/features/fate_screen.dart`, inside the Cards-section `Consumer` builder:

(a) After the line `final decks = ref.watch(decksProvider).valueOrNull ?? const DecksState();`, add:

```dart
              final deckLen = decks.jokers
                  ? kPlayingDeckWithJokers.length
                  : kPlayingDeck.length;
```

(b) Change the standard-deck readout `Text` from:

```dart
                      Text(
                          'Deck ${decks.standard.remainingOf(kPlayingDeck.length)}'
                          '/${kPlayingDeck.length}',
                          style: theme.textTheme.bodySmall),
```

to:

```dart
                      Text(
                          'Deck ${decks.standard.remainingOf(deckLen)}/$deckLen',
                          style: theme.textTheme.bodySmall),
```

(c) Add the jokers chip right after the standard `cards-reshuffle` `TextButton` (the one whose `onPressed` calls `reshuffle(tarot: false)`), still inside the same `Wrap`'s `children`:

```dart
                      FilterChip(
                        key: const Key('cards-jokers-toggle'),
                        label: const Text('Jokers'),
                        selected: decks.jokers,
                        onSelected: (v) =>
                            ref.read(decksProvider.notifier).setJokers(v),
                      ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/fate_cards_test.dart`
Expected: PASS (existing + new).

- [ ] **Step 5: Run analyze + full suite**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/features/fate_screen.dart test/fate_cards_test.dart
git commit -m "feat(cards): Jokers toggle + 54-card readout in the Cards section

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Doc sync — CLAUDE.md card-oracle note

**Files:**
- Modify: `CLAUDE.md` (the card-deck-oracles bullet)

- [ ] **Step 1: Update the deck description + drop jokers from Deferred**

In `CLAUDE.md`, find the card-deck-oracles bullet. It currently describes a 52-card deck and lists `jokers` under Deferred. Make two edits:

Change the deck-intro phrase:

```
a 52-card
  deck (`kPlayingDeck`) and a 78-card tarot deck (`kTarotDeck` = `kTarotMajor` +
  minor),
```

to:

```
a 52-card
  deck (`kPlayingDeck`, opt-in 54 with the two name-only jokers via
  `kPlayingDeckWithJokers` + the `cards-jokers-toggle` / `DecksState.jokers`
  flag) and a 78-card tarot deck (`kTarotDeck` = `kTarotMajor` +
  minor),
```

Change the deferred line:

```
  Deferred: a `/spread` slash command (needs a picker), jokers. See
```

to:

```
  Deferred: a `/spread` slash command (needs a picker). See
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note the opt-in jokers deck in CLAUDE.md

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 Data (`kPlayingJokers`, `kPlayingDeckWithJokers`) → Task 1. ✓
- §2 `DecksState.jokers` (+ copyWith/JSON, tolerant) → Task 1. ✓
- §3 `_standardDeck` in `draw`; `setJokers` (resets standard) → Task 2. ✓ (drawAndLog inherits via draw — not separately changed, matching the spec.)
- §4 UI chip + `deckLen` readout → Task 3. ✓
- §5 No `card_images` change → none of the tasks touch it. ✓
- Testing: deck/state (Task 1), provider draw+setJokers (Task 2), toggle widget (Task 3). ✓

**Type consistency:**
- `DecksState.jokers` is `bool` default `false`; `copyWith({..., bool? jokers})`; `setJokers(bool)` — consistent across Tasks 1-3. ✓
- `_standardDeck(DecksState) -> List<String>` defined + used in Task 2. ✓
- `kPlayingDeckWithJokers.length` (54) used in Task 1 test + Task 3 readout. ✓
- Key `cards-jokers-toggle` consistent between Task 3 impl + test. ✓

**Placeholder scan:** No TBD/TODO; every code step has complete code. ✓

**Risk note:** Task 3's readout uses `find.textContaining('/54')` — the readout string is `'Deck 54/54'` after toggle (standard reset → full), so `/54` matches once and `/52` disappears. The tarot readout is `'Tarot N/78'`, which contains neither `/52` nor `/54`, so the finders stay unambiguous.
