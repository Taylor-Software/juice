# Card meanings + guide/reference + PD images — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every tarot card an AI-free authored meaning (upright + reversed), surfaced on draw / in the journal / a browsable reference + a how-to guide, then bundle public-domain card art for both decks.

**Architecture:** Pure authored data (`tarot_meanings.dart`) + a pure parse helper (`readTarot`) feed three surfaces (draw card, journal entry, reference screen) and a Help page. Phase 2 adds pure image-path helpers (`card_images.dart`) backed by bundled PD/CC0 assets fetched by provenance scripts; reversed = 180° rotation; no BlobStore (bundled assets are always present).

**Tech Stack:** Flutter, flutter_riverpod, flutter_test. Assets via `pubspec.yaml`. Python fetch/optimize scripts (Pillow) for P2.

Spec: `docs/superpowers/specs/2026-06-22-card-meanings-images-design.md`

---

## File structure

| File | Phase | Responsibility |
|------|-------|----------------|
| `lib/engine/tarot_meanings.dart` | P1 | `TarotMeaning`, `kTarotMeanings` (78), `readTarot` parse |
| `lib/features/tarot_reference.dart` | P1 | sections+search reference screen (+thumbnails P2) |
| `lib/features/fate_screen.dart` | P1/P2 | on-draw meaning, "Card meanings" button (+image P2) |
| `lib/features/journal_screen.dart` | P1/P2 | log meaning into card entry (+render image P2) |
| `assets/help_data.json` | P1 | "Reading tarot" guide page |
| `lib/engine/card_images.dart` | P2 | slug + asset-path helpers |
| `assets/tarot/*`, `assets/playing/*`, `pubspec.yaml` | P2 | bundled images |
| `fetch_tarot_images.py`, `fetch_playing_images.py` | P2 | provenance + fetch/optimize |

---

# PHASE 1 — meanings + guide + reference (text)

## Task 1: `TarotMeaning` + `readTarot` (parse), seeded with a few cards

**Files:**
- Create: `lib/engine/tarot_meanings.dart`
- Test: `test/tarot_meanings_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/tarot_meanings.dart';

void main() {
  test('readTarot parses orientation and looks up meaning', () {
    final up = readTarot('The Fool');
    expect(up.name, 'The Fool');
    expect(up.reversed, isFalse);
    expect(up.meaning, isNotNull);

    final rev = readTarot('The Tower (reversed)');
    expect(rev.name, 'The Tower');
    expect(rev.reversed, isTrue);
    expect(rev.meaning, isNotNull);
  });

  test('readTarot returns null meaning for a non-tarot (standard) card', () {
    final r = readTarot('Ace of Spades');
    expect(r.name, 'Ace of Spades');
    expect(r.meaning, isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/tarot_meanings_test.dart`
Expected: FAIL — `tarot_meanings.dart` missing.

- [ ] **Step 3: Implement structure + parse + a few entries**

Create `lib/engine/tarot_meanings.dart`:

```dart
// Original, authored generic tarot associations (no source/attribution).
// Upright + reversed, one to two short clauses each. Keyed by the exact card
// names in kTarotDeck (lib/engine/models.dart).

class TarotMeaning {
  const TarotMeaning(this.upright, this.reversed);
  final String upright;
  final String reversed;
}

const Map<String, TarotMeaning> kTarotMeanings = {
  'The Fool': TarotMeaning(
      'A fresh start, a leap of faith, open road and open mind.',
      'A reckless leap, cold feet at the edge, a risk taken without looking.'),
  'The Tower': TarotMeaning(
      'Sudden upheaval, a shock that breaks a false structure, hard truth.',
      'Disaster narrowly avoided, clinging to what should fall, slow collapse.'),
  // remaining 76 entries added in Task 2
};

const _reversedSuffix = ' (reversed)';

/// Parse a drawn card string ("The Tower (reversed)") into name + orientation
/// + meaning (null when the name isn't a tarot card, e.g. a standard draw).
({String name, bool reversed, TarotMeaning? meaning}) readTarot(String shown) {
  final reversed = shown.endsWith(_reversedSuffix);
  final name = reversed
      ? shown.substring(0, shown.length - _reversedSuffix.length)
      : shown;
  return (name: name, reversed: reversed, meaning: kTarotMeanings[name]);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/tarot_meanings_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/tarot_meanings.dart test/tarot_meanings_test.dart
git commit -m "feat(cards): TarotMeaning + readTarot parser (seed entries)"
```

---

## Task 2: Author all 78 meanings + full-coverage test

**Files:**
- Modify: `lib/engine/tarot_meanings.dart`
- Test: `test/tarot_meanings_test.dart`

- [ ] **Step 1: Add the coverage test (failing until populated)**

Append to `test/tarot_meanings_test.dart`, and add the import:

```dart
import 'package:juice_oracle/engine/models.dart';

// inside main():
  test('every tarot card has an authored meaning, upright != reversed', () {
    for (final card in kTarotDeck) {
      final m = kTarotMeanings[card];
      expect(m, isNotNull, reason: 'missing meaning for "$card"');
      expect(m!.upright.trim(), isNotEmpty, reason: 'upright "$card"');
      expect(m.reversed.trim(), isNotEmpty, reason: 'reversed "$card"');
      expect(m.upright, isNot(m.reversed), reason: 'distinct "$card"');
    }
    expect(kTarotMeanings.length, kTarotDeck.length); // no stray keys
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/tarot_meanings_test.dart`
Expected: FAIL — most cards missing.

- [ ] **Step 3: Author all 78 entries**

Fill `kTarotMeanings` with all 78 cards (22 Majors from `kTarotMajor`; 56 Minors
as `'<Rank> of <Suit>'` for ranks `Ace,Two..Ten,Page,Knight,Queen,King` ×
suits `Wands,Cups,Swords,Pentacles`). Write each entry concisely:
- **Majors:** distinct, evocative (e.g. `'Strength': TarotMeaning('Quiet courage, patience, mastering impulse with a gentle hand.', 'Self-doubt, raw nerves, force used where patience was needed.')`).
- **Minors:** compose from suit theme × rank — Wands = drive/creativity/action,
  Cups = emotion/relationship/intuition, Swords = intellect/conflict/truth,
  Pentacles = work/money/body; Ace = pure seed of the suit, 2–10 = a
  progression, Page = curious learner, Knight = pursuer, Queen = nurturing
  master, King = commanding master. Keep each 1–2 clauses, upright + reversed.
  Example: `'Ace of Cups': TarotMeaning('An open heart, new love or feeling, a cup that overflows.', 'A closed or spilled heart, feeling withheld, emotion gone sour.')`.
- Keep voice consistent and generic (no esoteric depth, no quoted source).

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/tarot_meanings_test.dart`
Expected: PASS (all coverage assertions).

- [ ] **Step 5: Commit**

```bash
git add lib/engine/tarot_meanings.dart test/tarot_meanings_test.dart
git commit -m "feat(cards): author generic upright/reversed meanings for all 78 tarot cards"
```

---

## Task 3: Show the meaning on draw (fate_screen)

**Files:**
- Modify: `lib/features/fate_screen.dart` (the Cards section, after the `_cardLast` `ResultCard`, ~line 400-408)
- Test: `test/fate_cards_test.dart` (create) — or extend an existing fate test

- [ ] **Step 1: Write the failing test**

Create `test/fate_cards_test.dart`. Mirror an existing fate_screen test's pump
(real oracle from `assets/oracle_data.json` via dart:io; `cards` system enabled;
seed the dice so the draw is deterministic). Assert that after tapping
`cards-draw-tarot`, the drawn card's authored meaning text is shown. To make the
draw deterministic, override `decksProvider`/oracle dice with a fixed seed and
read which card index comes up, OR assert that SOME `kTarotMeanings` upright or
reversed string is present:

```dart
testWidgets('drawing a tarot card shows its authored meaning', (tester) async {
  await pumpFate(tester, systems: {'cards'}); // helper enables cards + oracle
  await tester.tap(find.byKey(const Key('cards-draw-tarot')));
  await tester.pumpAndSettle();
  final drawn = /* read _cardLast via the result card text */;
  final r = readTarot(drawn);
  expect(find.textContaining(r.meaning!.reversed.split(',').first), ... );
});
```

If reading the exact drawn card is awkward, assert the presence of a
`Key('card-meaning')` widget instead (added in Step 3) — simpler and robust.

```dart
  expect(find.byKey(const Key('card-meaning')), findsOneWidget);
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/fate_cards_test.dart`
Expected: FAIL — no `card-meaning` widget.

- [ ] **Step 3: Render the meaning**

In `lib/features/fate_screen.dart`, add `import '../engine/tarot_meanings.dart';`.
Immediately after the `_cardLast` `ResultCard` (inside the
`if (_cardLast != null) ...[ … ]` block), add:

```dart
                    Builder(builder: (context) {
                      final r = readTarot(_cardLast!.summary);
                      if (r.meaning == null) return const SizedBox.shrink();
                      final text = r.reversed
                          ? r.meaning!.reversed
                          : r.meaning!.upright;
                      return Padding(
                        key: const Key('card-meaning'),
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${r.reversed ? 'Reversed' : 'Upright'} — $text',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      );
                    }),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/fate_cards_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/fate_screen.dart test/fate_cards_test.dart
git commit -m "feat(cards): show authored meaning under a drawn tarot card"
```

---

## Task 4: Fold the meaning into the journal entry

**Files:**
- Modify: `lib/features/fate_screen.dart` (the `_cardLast` `ResultCard` `onAdd`, ~line 403-407)
- Test: `test/fate_cards_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('logging a tarot card writes the meaning into the entry',
    (tester) async {
  final container = await pumpFate(tester, systems: {'cards'});
  await tester.tap(find.byKey(const Key('cards-draw-tarot')));
  await tester.pumpAndSettle();
  // tap the result card's add-to-journal action (existing key in ResultCard)
  await tester.tap(find.byKey(const Key('result-add'))); // confirm the real key
  await tester.pumpAndSettle();
  final entries = await container.read(journalProvider.future);
  expect(entries.first.sourceTool, 'cards');
  expect(entries.first.body, contains('—')); // "Card (orientation) — meaning"
});
```

(Confirm the ResultCard add-action key by reading `lib/shared/...ResultCard`;
use whatever it exposes.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/fate_cards_test.dart`
Expected: FAIL — body has no meaning.

- [ ] **Step 3: Enrich the logged body**

In the `_cardLast` `ResultCard`'s `onAdd` (currently logs
`_cardLast!.asText`), build a body that appends the tarot meaning when present:

```dart
                      onAdd: () {
                        final r = readTarot(_cardLast!.summary);
                        final body = r.meaning == null
                            ? _cardLast!.asText
                            : '${_cardLast!.asText}\n'
                                '${r.reversed ? 'Reversed' : 'Upright'} — '
                                '${r.reversed ? r.meaning!.reversed : r.meaning!.upright}';
                        ref.read(journalProvider.notifier).addResult(
                              _cardLast!.title,
                              body,
                              sourceTool: 'cards',
                              payload: _cardLast!.toPayload(),
                            );
                      },
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/fate_cards_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/fate_screen.dart test/fate_cards_test.dart
git commit -m "feat(cards): include the tarot meaning in the logged journal entry"
```

---

## Task 5: Browsable reference screen (`tarot_reference.dart`)

**Files:**
- Create: `lib/features/tarot_reference.dart`
- Test: `test/tarot_reference_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/tarot_reference.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: TarotReference())));
    await tester.pumpAndSettle();
  }

  testWidgets('shows suit + arcana section headers', (tester) async {
    await pump(tester);
    expect(find.text('Major Arcana'), findsOneWidget);
    expect(find.text('Wands'), findsOneWidget);
  });

  testWidgets('search filters to matching cards', (tester) async {
    await pump(tester);
    await tester.enterText(find.byKey(const Key('tarot-ref-search')), 'tower');
    await tester.pumpAndSettle();
    expect(find.text('The Tower'), findsOneWidget);
    expect(find.text('Wands'), findsNothing); // non-matching group hidden
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/tarot_reference_test.dart`
Expected: FAIL — `tarot_reference.dart` missing.

- [ ] **Step 3: Implement the reference**

Create `lib/features/tarot_reference.dart`. Group cards into Major Arcana (the 22
`kTarotMajor`) + the four suits (each `'<Rank> of <Suit>'` for that suit), render
`ExpansionTile` sections with a search `TextField` (`tarot-ref-search`),
mirroring `tables_screen.dart` (sections + filter; while searching use a
non-PageStorage key so matches show expanded). Each card row shows the name +
upright and reversed text from `kTarotMeanings`.

```dart
import 'package:flutter/material.dart';
import '../engine/models.dart';
import '../engine/tarot_meanings.dart';

class TarotReference extends StatefulWidget {
  const TarotReference({super.key});
  @override
  State<TarotReference> createState() => _TarotReferenceState();
}

class _TarotReferenceState extends State<TarotReference> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() { _search.dispose(); super.dispose(); }

  List<({String label, List<String> cards})> get _groups => [
        (label: 'Major Arcana', cards: kTarotMajor),
        for (final suit in const ['Wands', 'Cups', 'Swords', 'Pentacles'])
          (
            label: suit,
            cards: [
              for (final c in kTarotDeck)
                if (c.endsWith(' of $suit')) c
            ]
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _q.trim().toLowerCase();
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          key: const Key('tarot-ref-search'),
          controller: _search,
          decoration: const InputDecoration(
            isDense: true,
            hintText: 'Search cards…',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            for (final g in _groups)
              if (g.cards
                  .where((c) => c.toLowerCase().contains(q))
                  .toList() case final cards when cards.isNotEmpty)
                ExpansionTile(
                  key: q.isEmpty
                      ? PageStorageKey('tarot-ref-${g.label}')
                      : ValueKey('tarot-ref-search-${g.label}'),
                  initiallyExpanded: true,
                  title: Text(g.label, style: theme.textTheme.titleMedium),
                  children: [for (final c in cards) _row(theme, c)],
                ),
          ],
        ),
      ),
    ]);
  }

  Widget _row(ThemeData theme, String card) {
    final m = kTarotMeanings[card];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(card, style: theme.textTheme.titleSmall),
            if (m != null) ...[
              const SizedBox(height: 4),
              Text('Upright — ${m.upright}', style: theme.textTheme.bodySmall),
              Text('Reversed — ${m.reversed}', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/tarot_reference_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/tarot_reference.dart test/tarot_reference_test.dart
git commit -m "feat(cards): browsable tarot reference (sections + search)"
```

---

## Task 6: "Card meanings" entry point in the Cards section

**Files:**
- Modify: `lib/features/fate_screen.dart` (Cards section, near the draw buttons)
- Test: `test/fate_cards_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
testWidgets('Card meanings button opens the reference', (tester) async {
  await pumpFate(tester, systems: {'cards'});
  await tester.tap(find.byKey(const Key('cards-reference')));
  await tester.pumpAndSettle();
  expect(find.byType(TarotReference), findsOneWidget);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/fate_cards_test.dart`
Expected: FAIL — no `cards-reference`.

- [ ] **Step 3: Add the button**

In `fate_screen.dart` add `import 'tarot_reference.dart';`, and in the Cards
section (after the reshuffle `Wrap`) add:

```dart
                  TextButton.icon(
                    key: const Key('cards-reference'),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: const Text('Card meanings'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Tarot meanings')),
                          body: const TarotReference(),
                        ),
                      ),
                    ),
                  ),
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/fate_cards_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/features/fate_screen.dart test/fate_cards_test.dart
git commit -m "feat(cards): Card meanings button opens the tarot reference"
```

---

## Task 7: "Reading tarot" guide page (Help)

**Files:**
- Modify: `assets/help_data.json`
- Test: `test/help_asset_test.dart` or `test/help_data_test.dart` (add an assertion)

- [ ] **Step 1: Add a failing assertion**

In the existing help-data test, assert the new page exists:

```dart
  test('help includes the Reading tarot page', () {
    final ids = <String>[
      for (final s in data.sections) for (final p in s.pages) p.id,
    ];
    expect(ids, contains('reading-tarot'));
  });
```

(Match the test's existing `data` loader / `HelpData` API.)

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/help_data_test.dart`
Expected: FAIL — no such page.

- [ ] **Step 3: Add the page to `assets/help_data.json`**

Under the *User guide* section's `pages` array, add a page (match the existing
block schema — `kind` of `h`/`p`/`tip`/`steps`):

```json
{
  "id": "reading-tarot",
  "title": "Reading tarot",
  "blocks": [
    {"kind": "p", "text": "The tarot deck is an oracle: draw a card and read its image and meaning against your story. These are generic starting points — not fixed truths."},
    {"kind": "h", "text": "Upright vs reversed"},
    {"kind": "p", "text": "A card can land upright or reversed. Reversed usually softens, blocks, or inverts the upright meaning — resistance, delay, or the shadow side."},
    {"kind": "h", "text": "Major vs Minor"},
    {"kind": "p", "text": "The 22 Major Arcana mark big themes and turning points. The 56 Minor cards (Wands, Cups, Swords, Pentacles) cover everyday matters: Wands = drive and creativity, Cups = emotion and bonds, Swords = mind and conflict, Pentacles = work and the material world."},
    {"kind": "tip", "text": "Stuck on a card? Open Card meanings from the Cards panel to look up any card's upright and reversed reading."}
  ]
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/help_data_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add assets/help_data.json test/help_data_test.dart
git commit -m "docs(cards): add a Reading tarot guide page to Help"
```

---

## Task 8: Phase 1 full verification

- [ ] **Step 1:** `flutter analyze` — clean (allow only the pre-existing `card_oracle_test.dart:44` info lint).
- [ ] **Step 2:** `flutter test` — all pass.
- [ ] **Step 3:** Commit any straggler test fixups.

---

# PHASE 2 — bundled public-domain images

> P2 needs network asset acquisition + per-image license verification. Each
> fetched file MUST be PD or CC0; the script records source + license and the
> reviewer rejects anything else (no LGPL/attribution sets).

## Task 9: `card_images.dart` — slug + asset-path helpers (pure)

**Files:**
- Create: `lib/engine/card_images.dart`
- Test: `test/card_images_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/card_images.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('slugs and asset paths', () {
    expect(cardSlug('The Tower'), 'the-tower');
    expect(cardSlug('Ace of Wands'), 'ace-of-wands');
    expect(tarotImageAsset('The Tower'), 'assets/tarot/the-tower.png');
    expect(playingCardImageAsset('Ace of Spades'),
        'assets/playing/ace-of-spades.png');
  });

  test('cardImageAsset resolves tarot then playing, null otherwise', () {
    expect(cardImageAsset('The Fool'), startsWith('assets/tarot/'));
    expect(cardImageAsset('King of Hearts'), startsWith('assets/playing/'));
    expect(cardImageAsset('Not A Card'), isNull);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/card_images_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
import 'models.dart';

String cardSlug(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-|-$'), '');

String? tarotImageAsset(String name) =>
    kTarotDeck.contains(name) ? 'assets/tarot/${cardSlug(name)}.png' : null;

String? playingCardImageAsset(String name) =>
    kPlayingDeck.contains(name) ? 'assets/playing/${cardSlug(name)}.png' : null;

String? cardImageAsset(String name) =>
    tarotImageAsset(name) ?? playingCardImageAsset(name);
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/card_images_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/card_images.dart test/card_images_test.dart
git commit -m "feat(cards): pure card-image asset-path helpers"
```

---

## Task 10: Fetch + optimize PD/CC0 images (provenance scripts)

**Files:**
- Create: `fetch_tarot_images.py`, `fetch_playing_images.py`
- Create (generated): `assets/tarot/*.png`, `assets/playing/*.png`, `assets/CARD_ART_SOURCES.md`
- Modify: `pubspec.yaml`

- [ ] **Step 1:** Write `fetch_tarot_images.py`: for each of the 78 cards, a
  documented Wikimedia Commons PD source URL (RWS, Smith 1909); download, verify
  the HTTP 200 + that the Commons license tag is `PD`/`PD-old`/`PD-US`, resize to
  max ~600 px long edge (Pillow), save `assets/tarot/<slug>.png`. Append a row
  `slug | source URL | license` to `assets/CARD_ART_SOURCES.md`. Abort the whole
  run if any card's license isn't PD.
- [ ] **Step 2:** Write `fetch_playing_images.py` similarly for the 52 standard
  cards from a **CC0** set (e.g. Dmitry Fomin's Commons deck). Abort if any file
  isn't CC0/PD.
- [ ] **Step 3:** Run both: `python3 fetch_tarot_images.py && python3 fetch_playing_images.py`. Expect 78 + 52 files + `CARD_ART_SOURCES.md`.
- [ ] **Step 4:** Register assets in `pubspec.yaml` under `flutter: assets:`:
  ```yaml
    assets:
      - assets/tarot/
      - assets/playing/
  ```
  Run `flutter pub get`.
- [ ] **Step 5:** Add a test asserting bundled coverage (every deck card has a
  file on disk):
  ```dart
  // test/card_assets_test.dart
  import 'dart:io';
  import 'package:flutter_test/flutter_test.dart';
  import 'package:juice_oracle/engine/card_images.dart';
  import 'package:juice_oracle/engine/models.dart';
  void main() {
    test('every tarot + playing card has a bundled image', () {
      for (final c in [...kTarotDeck, ...kPlayingDeck]) {
        final p = cardImageAsset(c)!;
        expect(File(p).existsSync(), isTrue, reason: p);
      }
    });
  }
  ```
  Run: `flutter test test/card_assets_test.dart` → PASS.
- [ ] **Step 6: Commit**
  ```bash
  git add fetch_tarot_images.py fetch_playing_images.py assets/tarot assets/playing assets/CARD_ART_SOURCES.md pubspec.yaml test/card_assets_test.dart
  git commit -m "feat(cards): bundle PD/CC0 tarot + standard card images (+provenance)"
  ```

---

## Task 11: Render images — draw card, reference thumbnails, journal entry

**Files:**
- Modify: `lib/features/fate_screen.dart`, `lib/features/tarot_reference.dart`, `lib/features/journal_screen.dart`
- Test: extend `test/fate_cards_test.dart`, `test/tarot_reference_test.dart`

- [ ] **Step 1: Write failing tests** — assert an `Image` (asset) renders for a
  drawn card and in a reference row, and that a `cards`-sourced journal entry
  shows a card image. Use `find.byKey(const Key('card-image'))`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** a shared `CardImage` widget:
  ```dart
  // in card_images.dart or a small widget file
  // Widget that shows cardImageAsset(name), rotated 180° when reversed.
  class CardImage extends StatelessWidget {
    const CardImage(this.cardName, {super.key, this.reversed = false, this.height = 120});
    final String cardName; final bool reversed; final double height;
    @override Widget build(BuildContext context) {
      final asset = cardImageAsset(cardName);
      if (asset == null) return const SizedBox.shrink();
      final img = Image.asset(asset, height: height, key: const Key('card-image'),
          errorBuilder: (_, __, ___) => const SizedBox.shrink());
      return reversed ? RotatedBox(quarterTurns: 2, child: img) : img;
    }
  }
  ```
  Use it: in fate_screen on-draw (parse `readTarot(_cardLast!.summary)` for
  reversed + base name), in each reference `_row` (leading thumbnail), and in
  `journal_screen` where a `sourceTool == 'cards'` entry renders — parse the card
  from the entry payload/body and show `CardImage`.
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit**
  ```bash
  git commit -am "feat(cards): render bundled card images on draw, reference, journal"
  ```

---

## Task 12: Credit + Phase 2 verification

- [ ] **Step 1:** Append a courtesy credit to the "Reading tarot" guide page (or
  the About/licenses page): `{"kind": "p", "text": "Card images: Rider–Waite–Smith (1909) and a CC0 standard deck — public domain."}`. Update the help-data test if it asserts block counts.
- [ ] **Step 2:** `flutter analyze` clean; `flutter test` all pass.
- [ ] **Step 3:** Commit.

---

## Self-review notes (done)

- **Spec coverage:** P1.1 meanings→T1/T2; P1.2 on-draw→T3; P1.3 journal→T4;
  P1.4 reference→T5/T6; P1.5 guide→T7. P2.1 assets→T10; P2.2 helpers→T9;
  P2.3 rotate + P2.4 render→T11; P2.5 credit→T12. Licensing diligence→T10 (abort
  on non-PD/CC0). All covered.
- **Type consistency:** `TarotMeaning(upright,reversed)`, `readTarot`,
  `kTarotMeanings`, `cardSlug`/`tarotImageAsset`/`playingCardImageAsset`/
  `cardImageAsset`, `CardImage`, keys `card-meaning`/`cards-reference`/
  `tarot-ref-search`/`card-image` — used identically across tasks.
- **Risk flags:** T3/T4/T6 reference a `pumpFate` helper + the `ResultCard`
  add-action key — confirm both against the real `fate_screen` tests / ResultCard
  widget at execution time. T10 is network + license-gated; the run aborts on any
  non-PD/CC0 asset.
```
