# Tarot Spreads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add positional multi-card tarot draws (spreads) to the card oracle — pick a spread, draw, see a labeled grid of cards with meanings, log the whole spread as one interpretable journal entry.

**Architecture:** A pure `tarot_spreads.dart` defines `TarotSpread` (id, name, position labels) + `kTarotSpreads` (3-card, 5-card Cross, 10-card Celtic Cross) + a `spreadBody` journal-text helper. `Oracle.drawSpread` loops the existing `drawCard`, threading `DeckState`. `DecksNotifier.drawSpread` persists the advanced tarot deck state and returns the result. The `fate_screen` Cards section gets a spread dropdown + Draw button + a uniform `Wrap` grid + a Log button.

**Tech Stack:** Dart, Flutter, flutter_riverpod, flutter_test. Reuses `drawCard`, `kTarotDeck`, `kTarotMeanings`/`tarotMeaningSuffix`/`readTarot`, `CardImage`, `DeckState`/`DecksState`.

---

## File Structure

- **Create** `lib/engine/tarot_spreads.dart` — `TarotSpread` class, `kTarotSpreads` const, `spreadBody()` helper. Pure, no Flutter.
- **Modify** `lib/engine/oracle.dart` — add `drawSpread` beside `drawCard` (card-deck oracle block, ~line 119).
- **Modify** `lib/state/providers.dart` — add `DecksNotifier.drawSpread` beside `drawAndLog` (~line 598).
- **Modify** `lib/features/fate_screen.dart` — Cards section: import, `_spread`/`_spreadLast` state, draw method, picker + button + grid + log UI (~line 436).
- **Create** `test/tarot_spreads_test.dart` — pure data + `spreadBody` tests.
- **Modify** `test/card_oracle_test.dart` — `drawSpread` engine + provider tests.
- **Modify** `test/fate_cards_test.dart` — spread widget test.

---

## Task 1: Spread data + journal-body helper

**Files:**
- Create: `lib/engine/tarot_spreads.dart`
- Test: `test/tarot_spreads_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/tarot_spreads_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/tarot_spreads.dart';

void main() {
  test('kTarotSpreads: unique ids, count matches positions, non-empty', () {
    final ids = kTarotSpreads.map((s) => s.id).toSet();
    expect(ids.length, kTarotSpreads.length); // ids unique
    for (final s in kTarotSpreads) {
      expect(s.positions, isNotEmpty, reason: '${s.id} has positions');
      expect(s.count, s.positions.length, reason: '${s.id} count');
      expect(s.name.trim(), isNotEmpty, reason: '${s.id} name');
    }
    expect(kTarotSpreads.first.count, 3); // three-card is first (UI default)
    expect(kTarotSpreads.any((s) => s.count == 10), isTrue); // celtic cross
  });

  test('spreadBody lists each position with a tarot meaning line', () {
    final body = spreadBody('Past · Present · Future', [
      (position: 'Past', shown: 'The Tower (reversed)'),
      (position: 'Present', shown: 'Three of Cups'),
      (position: 'Future', shown: 'Ace of Wands'),
    ]);
    expect(body, startsWith('Past · Present · Future'));
    expect(body, contains('Past — The Tower (reversed)'));
    expect(body, contains('Present — Three of Cups'));
    expect(body, contains('Future — Ace of Wands'));
    expect(body, contains('Reversed —')); // the Tower is reversed
    expect(body, contains('Upright —')); // the others upright
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/tarot_spreads_test.dart`
Expected: FAIL — `tarot_spreads.dart` / `kTarotSpreads` / `spreadBody` not defined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/engine/tarot_spreads.dart`:

```dart
// Authored, facts-only tarot spreads: a spread is a traditional *method*
// (non-copyrightable) and the position labels are this app's own short
// functional wording — no vendored booklet prose. Per-card meanings reuse the
// already-authored kTarotMeanings via tarotMeaningSuffix.

import 'tarot_meanings.dart';

/// A named tarot spread: an ordered list of position labels.
class TarotSpread {
  const TarotSpread(this.id, this.name, this.positions);
  final String id;
  final String name;
  final List<String> positions;
  int get count => positions.length;
}

/// The built-in spreads. The first is the UI default (kept small/common).
const kTarotSpreads = <TarotSpread>[
  TarotSpread('three-card', 'Past · Present · Future',
      ['Past', 'Present', 'Future']),
  TarotSpread('cross', 'Five-card Cross',
      ['Situation', 'Challenge', 'Past', 'Future', 'Outcome']),
  TarotSpread('celtic-cross', 'Celtic Cross', [
    'Present',
    'Challenge',
    'Foundation',
    'Recent Past',
    'Crown',
    'Near Future',
    'Self',
    'Environment',
    'Hopes & Fears',
    'Outcome',
  ]),
];

/// Multi-line journal body for a drawn spread: the spread name, then one
/// 'Position — Card' line per position with its tarot meaning folded in
/// (tarotMeaningSuffix prepends its own newline, so the meaning sits on the
/// next line). Shared by the Cards-section Log button so the stored text is
/// the canonical reading.
String spreadBody(
    String spreadName, List<({String position, String shown})> cards) {
  final b = StringBuffer(spreadName);
  for (final c in cards) {
    b.write('\n${c.position} — ${c.shown}${tarotMeaningSuffix(c.shown)}');
  }
  return b.toString();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/tarot_spreads_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/tarot_spreads.dart test/tarot_spreads_test.dart
git commit -m "feat(cards): tarot spread data + spreadBody journal helper

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: `Oracle.drawSpread` engine method

**Files:**
- Modify: `lib/engine/oracle.dart` (after `drawCard`, ~line 119)
- Test: `test/card_oracle_test.dart` (new test in the `Oracle.drawCard` group or a new `Oracle.drawSpread` group)

- [ ] **Step 1: Write the failing test**

Add to `test/card_oracle_test.dart` inside `void main()` (a new group after the `Oracle.drawCard` group). The file already imports `dart:math`, `oracle.dart`, `oracle_data.dart`, `models.dart`, and builds `data`; it must also import the spreads:

At the top of `test/card_oracle_test.dart`, add the import (beside the other `package:juice_oracle/engine/...` imports):

```dart
import 'package:juice_oracle/engine/tarot_spreads.dart';
```

Then add this group after the closing `});` of the `group('Oracle.drawCard', ...)`:

```dart
  group('Oracle.drawSpread', () {
    test('draws one card per position, advances state, builds rolls', () {
      final oracle = Oracle(data, Dice(Random(5)));
      final spread = kTarotSpreads.first; // three-card
      final out = oracle.drawSpread(
        deck: kTarotDeck,
        state: const DeckState(),
        spread: spread,
        reversible: true,
      );
      expect(out.cards, hasLength(3));
      expect(out.cards.map((c) => c.position).toList(), spread.positions);
      expect(out.next.drawn, 3); // advanced by the spread size
      expect(out.result.title, 'Tarot Spread');
      expect(out.result.summary, spread.name);
      expect(out.result.rolls, hasLength(3));
      expect(out.result.rolls.map((r) => r.label).toList(), spread.positions);
      // Every drawn card is a real tarot card (orientation suffix stripped).
      for (final c in out.cards) {
        final base = c.shown.replaceAll(' (reversed)', '');
        expect(kTarotDeck.contains(base), isTrue);
      }
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/card_oracle_test.dart`
Expected: FAIL — `drawSpread` not defined on `Oracle`.

- [ ] **Step 3: Write minimal implementation**

In `lib/engine/oracle.dart`, add the import at the top (beside the existing imports):

```dart
import 'tarot_spreads.dart';
```

Then, immediately after the `drawCard` method (after its closing `}` near line 119, still inside the `Oracle` class), add:

```dart
  /// Draws one card per position in [spread] from [deck], threading [state]
  /// through [drawCard] (so it reshuffles when exhausted). Each card is
  /// reversible when [reversible]. Returns the position→card mapping, the next
  /// DeckState to persist, and an aggregate GenResult (one Roll per position;
  /// summary = spread name). Meanings are NOT in the GenResult — they are
  /// folded into the journal body separately by spreadBody.
  ({
    List<({String position, String shown})> cards,
    DeckState next,
    GenResult result
  }) drawSpread({
    required List<String> deck,
    required DeckState state,
    required TarotSpread spread,
    bool reversible = false,
  }) {
    var st = state;
    final cards = <({String position, String shown})>[];
    for (final pos in spread.positions) {
      final r =
          drawCard(deck: deck, state: st, title: pos, reversible: reversible);
      st = r.next;
      cards.add((position: pos, shown: r.result.summary!));
    }
    return (
      cards: cards,
      next: st,
      result: GenResult(
        title: 'Tarot Spread',
        summary: spread.name,
        rolls: [for (final c in cards) Roll(label: c.position, value: c.shown)],
      ),
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/card_oracle_test.dart`
Expected: PASS (all existing + the new `drawSpread` test).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/oracle.dart test/card_oracle_test.dart
git commit -m "feat(cards): Oracle.drawSpread (threads drawCard over positions)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: `DecksNotifier.drawSpread` provider method

**Files:**
- Modify: `lib/state/providers.dart` (after `drawAndLog`, before `reshuffle`, ~line 598)
- Test: `test/card_oracle_test.dart` (new test in the `DecksNotifier` group)

- [ ] **Step 1: Write the failing test**

Add to `test/card_oracle_test.dart` inside the `group('DecksNotifier', ...)` block (after the `drawAndLog` test, before the group's closing `});`):

```dart
    test('drawSpread persists advanced tarot state; returns positioned cards',
        () async {
      SharedPreferences.setMockInitialValues({
        'juice.sessions.v1':
            '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      });
      final oracle = Oracle(data, Dice(Random(2)));
      final c = ProviderContainer(
          overrides: [oracleProvider.overrideWith((ref) async => oracle)]);
      addTearDown(c.dispose);
      await c.read(decksProvider.future);

      final spread = kTarotSpreads.first; // three-card
      final out =
          await c.read(decksProvider.notifier).drawSpread(oracle, spread);
      expect(out.cards, hasLength(3));
      expect(out.result.title, 'Tarot Spread');
      // Tarot deck advanced by 3; standard untouched.
      final s = c.read(decksProvider).valueOrNull!;
      expect(s.tarot.drawn, 3);
      expect(s.standard.order, isEmpty);
    });
```

This test needs `kTarotSpreads`; the Task 2 import already added it to this file.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/card_oracle_test.dart`
Expected: FAIL — `drawSpread` not defined on `DecksNotifier`.

- [ ] **Step 3: Write minimal implementation**

In `lib/state/providers.dart`, add the import at the top (beside the other `../engine/...` imports — confirm `tarot_meanings.dart` is already imported for `tarotMeaningSuffix`, add this one):

```dart
import '../engine/tarot_spreads.dart';
```

Then, in `DecksNotifier`, after the `drawAndLog` method's closing `}` and before `reshuffle`, add:

```dart
  /// Draws a [spread] from the tarot deck, persisting the advanced DeckState.
  /// Returns the positioned cards + aggregate GenResult for the caller to
  /// render and log (mirrors draw() + manual log, since the Cards section shows
  /// the spread before logging). Tarot-only — spreads use the 78-card deck.
  Future<
      ({
        List<({String position, String shown})> cards,
        GenResult result
      })> drawSpread(Oracle oracle, TarotSpread spread) async {
    final cur = state.valueOrNull ?? await future;
    final out = oracle.drawSpread(
      deck: kTarotDeck,
      state: cur.tarot,
      spread: spread,
      reversible: true,
    );
    await _save(cur.copyWith(tarot: out.next));
    return (cards: out.cards, result: out.result);
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/card_oracle_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/state/providers.dart test/card_oracle_test.dart
git commit -m "feat(cards): DecksNotifier.drawSpread (persist + return)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Cards-section spread UI (picker + draw + grid + log)

**Files:**
- Modify: `lib/features/fate_screen.dart`
- Test: `test/fate_cards_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `test/fate_cards_test.dart` inside `void main()` (after the existing tests). The file already has `pumpFate` (systems `["cards"]`), and imports `CardImage` + `journalProvider`:

```dart
  testWidgets('drawing a spread renders a card per position and logs one entry',
      (tester) async {
    final container = await pumpFate(tester);
    // Default spread is the three-card; draw it.
    await tester.tap(find.byKey(const Key('cards-draw-spread')));
    await tester.pumpAndSettle();
    // Three positions → three card images.
    expect(find.byType(CardImage), findsNWidgets(3));
    // Log the whole spread as one entry.
    await tester.tap(find.byKey(const Key('spread-log')));
    await tester.pumpAndSettle();
    final entries = container.read(journalProvider).valueOrNull ?? const [];
    expect(entries, hasLength(1));
    expect(entries.single.sourceTool, 'cards');
    expect(entries.single.body, contains('Past'));
    expect(entries.single.body, contains('Present'));
    expect(entries.single.body, contains('Future'));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/fate_cards_test.dart`
Expected: FAIL — no `cards-draw-spread` widget found.

- [ ] **Step 3a: Add the import and state fields**

In `lib/features/fate_screen.dart`, add the import (beside the existing `../engine/...` imports near line 6):

```dart
import '../engine/tarot_spreads.dart';
```

In `_FateScreenState`, after `GenResult? _cardLast;` (line 35), add:

```dart
  TarotSpread _spread = kTarotSpreads.first;
  List<({String position, String shown})>? _spreadLast;
```

- [ ] **Step 3b: Add the draw method**

In `_FateScreenState`, after the `_drawCard` method (ends ~line 54), add:

```dart
  Future<void> _drawSpread() async {
    final out =
        await ref.read(decksProvider.notifier).drawSpread(widget.oracle, _spread);
    if (mounted) setState(() => _spreadLast = out.cards);
  }
```

- [ ] **Step 3c: Add the picker + button + grid + log UI**

In `lib/features/fate_screen.dart`, find the single-card result block inside the Cards section that ends like this (~line 463):

```dart
                    _cardMeaning(theme, _cardLast!),
                  ],
                ],
              );
            }),
```

Insert the spread UI between the `]` that closes the `if (_cardLast != null) ...[` block and the next `]` that closes the `Column`'s `children`. Concretely, replace:

```dart
                    _cardMeaning(theme, _cardLast!),
                  ],
                ],
              );
            }),
```

with:

```dart
                    _cardMeaning(theme, _cardLast!),
                  ],
                  const SizedBox(height: 16),
                  const Divider(),
                  Text('Spreads', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButton<TarotSpread>(
                          key: const Key('spread-picker'),
                          isExpanded: true,
                          value: _spread,
                          items: [
                            for (final s in kTarotSpreads)
                              DropdownMenuItem(
                                value: s,
                                child: Text('${s.name}  (${s.count})'),
                              ),
                          ],
                          onChanged: (s) {
                            if (s != null) setState(() => _spread = s);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        key: const Key('cards-draw-spread'),
                        icon: const Icon(Icons.dashboard_outlined),
                        label: const Text('Draw spread'),
                        onPressed: _drawSpread,
                      ),
                    ],
                  ),
                  if (_spreadLast != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final c in _spreadLast!) _spreadTile(theme, c),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        key: const Key('spread-log'),
                        icon: const Icon(Icons.bookmark_add_outlined),
                        label: const Text('Log spread'),
                        onPressed: () {
                          ref.read(journalProvider.notifier).addResult(
                                'Tarot Spread',
                                spreadBody(_spread.name, _spreadLast!),
                                sourceTool: 'cards',
                              );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Added to journal')),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              );
            }),
```

- [ ] **Step 3d: Add the `_spreadTile` helper**

In `_FateScreenState`, after the `_cardBody` method (~line 73), add:

```dart
  /// One position tile in the spread grid: label, card art, name + orientation,
  /// and the authored meaning line. Uniform across all spreads.
  Widget _spreadTile(
      ThemeData theme, ({String position, String shown}) c) {
    final r = readTarot(c.shown);
    final meaning =
        r.meaning == null ? null : (r.reversed ? r.meaning!.reversed : r.meaning!.upright);
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.position,
              style: theme.textTheme.labelLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          CardImage(r.name, reversed: r.reversed, height: 120),
          const SizedBox(height: 4),
          Text('${r.name}${r.reversed ? ' (rev)' : ''}',
              style: theme.textTheme.bodySmall),
          if (meaning != null)
            Text(meaning,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/fate_cards_test.dart`
Expected: PASS (existing 4 + the new spread test).

- [ ] **Step 5: Run analyze + full suite**

Run: `flutter analyze` → expect `No issues found!`
Run: `flutter test` → expect All tests passed.

- [ ] **Step 6: Commit**

```bash
git add lib/features/fate_screen.dart test/fate_cards_test.dart
git commit -m "feat(cards): tarot spread picker + grid + log in Cards section

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Doc sync (CLAUDE.md card-oracle note)

**Files:**
- Modify: `CLAUDE.md` (the card-deck-oracles bullet, the one ending "Deferred: slash commands ... HUD quick-draw, jokers.")

- [ ] **Step 1: Update the card-oracle note**

In `CLAUDE.md`, find the card-deck-oracles bullet. After the sentence describing the `fate_screen` Cards section UI, add a sentence noting spreads, and remove nothing from the licensing/deferred text. Insert after the "a drawn card logs as a `result` entry ..." sentence:

```
  A **Spreads** sub-block (`spread-picker` + `cards-draw-spread`) draws a
  positional multi-card layout (`kTarotSpreads`: 3-card, 5-card Cross, 10-card
  Celtic Cross in `lib/engine/tarot_spreads.dart`) via `Oracle.drawSpread`
  (threads `drawCard` over the positions) / `DecksNotifier.drawSpread`; the grid
  is uniform (no bespoke Celtic-Cross geometry) and `spread-log` writes one
  `cards` journal entry (`spreadBody` folds each position's meaning in). See
  `docs/superpowers/specs/2026-06-23-tarot-spreads-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: note tarot spreads in the card-oracle CLAUDE.md bullet

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Self-Review

**Spec coverage:**
- §1 Data → Task 1 (`TarotSpread`, `kTarotSpreads`, `spreadBody`). ✓
- §2 Engine `drawSpread` → Task 2. ✓
- §3 Provider `drawSpread` → Task 3. ✓
- §4 UI (picker, draw, grid, log, `_spreadTile`) → Task 4. ✓
- §5 Deck state reuse (tarot `DeckState`, advance by N) → asserted in Task 3 test (`s.tarot.drawn == 3`). ✓
- Testing (§Testing: spreads pure, oracle, fate_cards widget) → Tasks 1/2/4. ✓
- Out-of-scope items intentionally absent. ✓

**Type consistency:**
- Record type `({String position, String shown})` identical across Tasks 1–4. ✓
- `drawSpread` engine returns `({cards, next, result})`; provider returns `({cards, result})` — matches spec §2/§3. ✓
- `GenResult(title:'Tarot Spread', summary: spread.name, rolls:[Roll(label,value)])` consistent (Task 2 builds, Task 2/3 tests assert). ✓
- `spreadBody(String, List<({String position, String shown})>)` signature identical in Task 1 def + Task 4 call. ✓
- UI keys: `spread-picker`, `cards-draw-spread`, `spread-log` consistent between Task 4 impl + test. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Note on the Log button:** it intentionally omits `payload:` (the spread is logged as text only — `spreadBody` is the canonical reading; a single-card payload schema doesn't fit a multi-card spread, and re-render isn't needed). This is a deliberate deviation from the single-card path's `payload: g.toPayload()` and is consistent with spec §4 (the entry is "interpretable via the standard per-entry Interpret", which reads body text).
