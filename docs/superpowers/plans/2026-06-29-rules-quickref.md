# Rules QuickRef Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Authored facts-only per-system Rules QuickRef cards, rendered by one `QuickRefView` reachable from the Encounter screen, the Run dashboard, a `/rules` slash command, and the Reference view.

**Architecture:** A pure `quick_ref.dart` (model + `kSystemQuickRefs` map keyed by canonical system id + `resolveSystemQuickRef` reusing the existing `resolveSystem`). A read-only `QuickRefView` + `showQuickRef` opener. Four thin surface wirings.

**Tech Stack:** Flutter, Riverpod, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-29-rules-quickref-design.md`

**Environment:** `flutter` at `$HOME/development/flutter/bin` — `export PATH="$HOME/development/flutter/bin:$PATH"`. Package `juice_oracle`.

**Key facts (verified):**
- `resolveSystem(Set systems, Set rulesets)` in `lib/engine/system_primer.dart:76` returns the active system key — and returns `'starforged'`/`'sundered_isles'` (NOT `'ironsworn'`) when those rulesets are enabled. So the Ironsworn card must be registered under all three keys.
- `resolvedSystemProvider` (`lib/state/providers.dart:1836`) exposes the resolved key.
- `ContentType` enum (`lib/engine/content_registry.dart:4`) = `{ all, monsters, spells }`.
- `_openReference(query, type)` (`lib/features/journal_screen.dart:410`) pushes a Scaffold with `ReferenceView(initialQuery, initialType)`.

---

## Task 1: Engine — model + 7 cards + resolver + provider (TDD)

**Files:**
- Create: `lib/engine/quick_ref.dart`
- Modify: `lib/state/providers.dart`
- Test: `test/quick_ref_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/quick_ref_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/quick_ref.dart';

void main() {
  group('resolveSystemQuickRef', () {
    test('priority: dnd wins, cairn resolves, ironsworn-family shares a card', () {
      expect(resolveSystemQuickRef({'dnd', 'ironsworn'}, {})?.system, 'dnd');
      expect(resolveSystemQuickRef({'cairn'}, {})?.system, 'cairn');
      // starforged/sundered_isles rulesets resolve to the ironsworn card
      final sf = resolveSystemQuickRef({'ironsworn'}, {'starforged'});
      expect(sf, isNotNull);
      expect(sf, same(kSystemQuickRefs['ironsworn']));
    });

    test('null when the resolved system has no card', () {
      expect(resolveSystemQuickRef({'shadowdark'}, {}), isNull); // not in P1
      expect(resolveSystemQuickRef({}, {}), isNull);
    });
  });

  group('kSystemQuickRefs content integrity', () {
    test('each card is well-formed (drop-in guard)', () {
      kSystemQuickRefs.forEach((key, card) {
        expect(card.title.trim(), isNotEmpty, reason: '$key title');
        expect(card.sections.length, greaterThanOrEqualTo(3),
            reason: '$key needs >= 3 sections');
        for (final s in card.sections) {
          expect(s.title.trim(), isNotEmpty, reason: '$key section title');
          expect(s.lines, isNotEmpty, reason: '$key section "${s.title}" lines');
          expect(s.lines.every((l) => l.trim().isNotEmpty), isTrue,
              reason: '$key section "${s.title}" has an empty line');
        }
      });
    });

    test('the 7 P1 systems are present (ironsworn under 3 keys)', () {
      for (final k in [
        'argosa', 'cairn', 'knave', 'ose', 'kal-arath', 'dnd', 'ironsworn',
        'starforged', 'sundered_isles',
      ]) {
        expect(kSystemQuickRefs.containsKey(k), isTrue, reason: k);
      }
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/quick_ref_test.dart` → FAIL (URI doesn't exist).

- [ ] **Step 3: Create `lib/engine/quick_ref.dart`**

```dart
import 'system_primer.dart' show resolveSystem;

/// One titled block of facts-only reference lines.
class QuickRefSection {
  const QuickRefSection(this.title, this.lines);
  final String title;
  final List<String> lines;
}

/// A per-system mechanics quick reference (facts-only: procedures + condition/
/// save names + one-line generic effects; no rulebook prose, no attribution).
class QuickRefCard {
  const QuickRefCard({
    required this.system,
    required this.title,
    required this.sections,
  });
  final String system;
  final String title;
  final List<QuickRefSection> sections;
}

const _dnd = QuickRefCard(system: 'dnd', title: 'D&D 5e — Quick Reference', sections: [
  QuickRefSection('Resolution', [
    'd20 + modifier vs a Difficulty Class (DC).',
    'Advantage / disadvantage: roll 2d20, take the higher / lower.',
    'On attacks, a natural 20 always hits (and crits); a natural 1 always misses.',
  ]),
  QuickRefSection('Combat round', [
    'Roll initiative (d20 + DEX); act highest to lowest.',
    'Your turn: move up to your speed + one action + one bonus action (if you have one).',
    'One reaction per round (e.g. opportunity attack when a foe leaves your reach).',
  ]),
  QuickRefSection('Common actions', [
    'Attack, Cast a Spell, Dash, Disengage, Dodge, Help, Hide, Ready, Search, Use an Object.',
  ]),
  QuickRefSection('Attacks & damage', [
    'Attack roll: d20 + ability mod + proficiency vs target AC.',
    'On a hit, roll the weapon/spell damage + ability mod.',
  ]),
  QuickRefSection('Damage & death', [
    '0 HP = unconscious; make a death save each turn: d20, 10+ succeeds, under fails.',
    '3 successes = stable; 3 failures = dead. Taking damage at 0 HP = 1 failure (a crit = 2).',
  ]),
  QuickRefSection('Conditions', [
    'Blinded, Charmed, Deafened, Frightened, Grappled, Incapacitated, Invisible,',
    'Paralyzed, Petrified, Poisoned, Prone, Restrained, Stunned, Unconscious, Exhaustion.',
  ]),
  QuickRefSection('Rest', [
    'Short rest (~1 hr): spend Hit Dice to regain HP.',
    'Long rest (~8 hr): regain all HP and half your Hit Dice.',
  ]),
]);

const _ironsworn = QuickRefCard(
    system: 'ironsworn', title: 'Ironsworn — Quick Reference', sections: [
  QuickRefSection('Resolution', [
    'Roll your action die (d6) + stat + adds vs two challenge dice (d10 each).',
    'Beat both = strong hit; beat one = weak hit; beat neither = miss.',
  ]),
  QuickRefSection('Momentum', [
    'Track momentum (-6..+10). Burn it to replace BOTH challenge dice with its value.',
    'Negative momentum cancels a matching action-die result.',
  ]),
  QuickRefSection('Combat (moves)', [
    'There is no initiative count — you "have the initiative" or you don\'t.',
    'Enter the Fray, then Strike (you have it) / Clash (you don\'t) / Secure an Advantage.',
    'Strong hits keep or seize the initiative; misses hand it to the enemy.',
  ]),
  QuickRefSection('Harm & death', [
    'Suffer harm → lose health. At 0 health, harm hits momentum or forces Face Death.',
  ]),
  QuickRefSection('Conditions (debilities)', [
    'Banes: wounded, shaken, unprepared, encumbered, maimed, corrupted.',
    'Burdens: cursed, tormented. Each marked debility lowers your max momentum.',
  ]),
]);

const _cairn = QuickRefCard(system: 'cairn', title: 'Cairn — Quick Reference', sections: [
  QuickRefSection('Resolution', [
    'Roll d20 UNDER the relevant ability (STR / DEX / WIL) to save.',
    '1 always succeeds, 20 always fails. Only roll when there is real risk and uncertainty.',
  ]),
  QuickRefSection('Combat round', [
    'Attacker rolls the weapon die − target Armor; deal the remainder to HP.',
    'Several attackers on one foe: roll all damage dice, keep the single highest.',
  ]),
  QuickRefSection('Impaired & enhanced', [
    'Impaired (cover, bound) = roll d4 for damage.',
    'Enhanced (helpless foe, daring move) = roll d12. Blast attacks hit everything in area.',
  ]),
  QuickRefSection('Damage & death', [
    'HP is luck/avoidance. At 0 HP, excess damage reduces STR.',
    'Then make a STR save or take Critical Damage: out of the fight, dying without aid.',
  ]),
  QuickRefSection('Deprivation & rest', [
    'A short rest with water restores HP. Deprived (no food/light/rest) = cannot recover.',
    'A day spent deprived adds Fatigue, which fills an inventory slot until you recover safely.',
  ]),
]);

const _knave = QuickRefCard(system: 'knave', title: 'Knave 2e — Quick Reference', sections: [
  QuickRefSection('Resolution', [
    'Roll d20 + ability bonus (0–10), meet or beat the target.',
    'Saves: d20 + relevant bonus vs DC 11 (or 11 + an opposing factor).',
  ]),
  QuickRefSection('Combat round', [
    'Roll initiative. Attack: d20 + bonus vs the target\'s Armor Class.',
    'On a hit, roll the weapon\'s damage die.',
  ]),
  QuickRefSection('Damage & death', [
    'Lose HP when hit. At 0 HP you start taking Wounds.',
    'Accumulating too many Wounds means death (track on the sheet).',
  ]),
  QuickRefSection('Inventory', [
    'Carry slots = 10 + CON. Exceeding them leaves you encumbered (slowed).',
  ]),
  QuickRefSection('Rest', [
    'Rest to recover HP; longer downtime and care to mend Wounds.',
  ]),
]);

const _ose = QuickRefCard(system: 'ose', title: 'OSE / B-X — Quick Reference', sections: [
  QuickRefSection('Resolution', [
    'Mostly attack rolls and saving throws on a d20 vs a fixed target.',
    'Ability checks are rare and by ruling.',
  ]),
  QuickRefSection('Combat round', [
    'Declare → initiative (d6 per side) → movement → missiles → spells → melee.',
    'Attack: d20 + modifiers vs the target\'s AC, using THAC0 or the to-hit table.',
  ]),
  QuickRefSection('Saving throws', [
    'Five saves: Death/Poison, Wands, Paralysis/Petrify, Breath, Spells/Rods/Staves.',
    'Roll d20; meet or beat the listed target number.',
  ]),
  QuickRefSection('AC & death', [
    'Descending AC — lower is better. On a hit, roll weapon damage.',
    '0 HP = dead (or unconscious by table ruling).',
  ]),
  QuickRefSection('Rest', [
    'Recover slowly with rest (e.g. ~1 HP per day); full recovery needs extended downtime.',
  ]),
]);

const _argosa = QuickRefCard(
    system: 'argosa', title: 'Tales of Argosa — Quick Reference', sections: [
  QuickRefSection('Resolution', [
    'Roll d20 UNDER your stat to succeed (roll-under).',
    'Roll ≤ half the stat = Great Success. 1 is best, 20 is worst.',
  ]),
  QuickRefSection('Combat round', [
    'Determine order, act, then resolve. Attack vs defense; on a hit, roll weapon damage − armor.',
  ]),
  QuickRefSection('Luck', [
    'Spend Luck to reroll or improve a result.',
    'Reset Luck to 10 + ⌈level / 2⌉ on a rest.',
  ]),
  QuickRefSection('Damage & staggered', [
    'Lose HP when hit. Staggered when current HP ≤ half max (and above 0): under pressure.',
    '0 HP = down / dying.',
  ]),
  QuickRefSection('Rest', [
    'Rest restores HP and Luck; serious wounds need longer recovery.',
  ]),
]);

const _kalArath = QuickRefCard(
    system: 'kal-arath', title: 'Kal-Arath — Quick Reference', sections: [
  QuickRefSection('Resolution', [
    'Roll 2d6 + stat, total ≥ 8 to succeed.',
    'Double 6s = Critical Success; double 1s = Critical Failure.',
  ]),
  QuickRefSection('Combat round', [
    'Act in the fiction; resolve a strike with 2d6 + stat ≥ 8 (or vs the foe).',
    'On success, deal damage minus the target\'s damage reduction.',
  ]),
  QuickRefSection('Fate & pacts', [
    'Spend a Fate Point (about one per session) to reroll or turn a failure.',
    'Demonic pacts grant power at the cost of mounting Doom.',
  ]),
  QuickRefSection('Damage & death', [
    'Lose HP when struck (after damage reduction). 0 HP = dying / out of the fight.',
    'Recover slowly or with aid.',
  ]),
]);

/// Authored facts-only cards, keyed by canonical system id (see resolveSystem).
/// Ironsworn shares one card across classic/starforged/sundered_isles.
const Map<String, QuickRefCard> kSystemQuickRefs = {
  'dnd': _dnd,
  'cairn': _cairn,
  'knave': _knave,
  'ose': _ose,
  'argosa': _argosa,
  'kal-arath': _kalArath,
  'ironsworn': _ironsworn,
  'starforged': _ironsworn,
  'sundered_isles': _ironsworn,
};

/// The active system's card, or null when the resolved system has none.
QuickRefCard? resolveSystemQuickRef(Set<String> systems, Set<String> rulesets) =>
    kSystemQuickRefs[resolveSystem(systems, rulesets)];
```

Confirm `resolveSystem` is exported from `system_primer.dart` (it is a top-level
function there). If the `show resolveSystem` import clause errors, use a plain
`import 'system_primer.dart';`.

- [ ] **Step 4: Add the provider in `lib/state/providers.dart`**

Add the import (with the other engine imports): `import '../engine/quick_ref.dart';`
Then, near `resolvedSystemProvider` (~line 1836):

```dart
final systemQuickRefProvider = Provider<QuickRefCard?>(
    (ref) => kSystemQuickRefs[ref.watch(resolvedSystemProvider)]);
```

- [ ] **Step 5: Run tests + analyze**

Run: `flutter test test/quick_ref_test.dart` → PASS.
Run: `flutter analyze lib/engine/quick_ref.dart lib/state/providers.dart test/quick_ref_test.dart` → no new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/engine/quick_ref.dart lib/state/providers.dart test/quick_ref_test.dart
git commit -m "feat(quickref): QuickRef model + 7 authored system cards + provider"
```

---

## Task 2: `QuickRefView` widget + opener (TDD)

**Files:**
- Create: `lib/features/quick_ref_view.dart`
- Test: `test/quick_ref_view_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/quick_ref_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/quick_ref.dart';
import 'package:juice_oracle/features/quick_ref_view.dart';

void main() {
  testWidgets('renders a card title, section titles and lines', (tester) async {
    const card = QuickRefCard(system: 'x', title: 'X — Quick Reference', sections: [
      QuickRefSection('Resolution', ['roll a die']),
      QuickRefSection('Combat', ['hit it']),
    ]);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: QuickRefView(card: card))));
    expect(find.text('Resolution'), findsOneWidget);
    expect(find.text('roll a die'), findsOneWidget);
    expect(find.text('Combat'), findsOneWidget);
  });

  testWidgets('shows the empty state when card is null', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: QuickRefView(card: null))));
    expect(find.byKey(const Key('quickref-empty')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run → FAIL (URI doesn't exist).**

- [ ] **Step 3: Create `lib/features/quick_ref_view.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/quick_ref.dart';
import '../state/providers.dart';

/// Read-only render of a system's QuickRef card. Pass [card] explicitly, or
/// leave it null to read the active system's card from [systemQuickRefProvider].
class QuickRefView extends ConsumerWidget {
  const QuickRefView({super.key, this.card, this.useProvider = false});
  final QuickRefCard? card;
  final bool useProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = useProvider ? ref.watch(systemQuickRefProvider) : card;
    if (resolved == null) {
      return Center(
        key: const Key('quickref-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No quick reference for this system yet.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    return ListView(
      key: const Key('quickref-list'),
      padding: const EdgeInsets.all(12),
      children: [
        Text(resolved.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final s in resolved.sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(s.title, style: theme.textTheme.titleSmall),
          ),
          for (final line in s.lines)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text('• $line', style: theme.textTheme.bodyMedium),
            ),
        ],
      ],
    );
  }
}

/// Opens the active system's QuickRef in a modal bottom sheet.
Future<void> showQuickRef(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.85,
        child: QuickRefView(useProvider: true),
      ),
    );
```

- [ ] **Step 4: Run tests + analyze → PASS / clean.**

Run: `flutter test test/quick_ref_view_test.dart`
Run: `flutter analyze lib/features/quick_ref_view.dart test/quick_ref_view_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/quick_ref_view.dart test/quick_ref_view_test.dart
git commit -m "feat(quickref): read-only QuickRefView + showQuickRef opener"
```

---

## Task 3: Wire the four surfaces

**Files:** `lib/features/encounter_screen.dart`, `lib/features/run_screen.dart`,
`lib/features/journal_screen.dart`, `lib/features/reference_view.dart`,
`lib/engine/content_registry.dart`.

- [ ] **Step 1: Encounter header button**

In `lib/features/encounter_screen.dart`, add `import 'quick_ref_view.dart';`. In
`_header(...)`, add an `IconButton` immediately before the `end-encounter` IconButton:

```dart
          IconButton(
            key: const Key('enc-rules'),
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Rules quick reference',
            onPressed: () => showQuickRef(context),
          ),
```

- [ ] **Step 2: Run dashboard panel**

In `lib/features/run_screen.dart`, add `import 'quick_ref_view.dart';`. Add a panel widget
near `_ReferencePanel`:

```dart
class _QuickRefPanel extends StatelessWidget {
  const _QuickRefPanel();
  @override
  Widget build(BuildContext context) {
    return const _Panel(
      k: Key('run-panel-quickref'),
      title: 'Rules',
      child: SizedBox(height: 320, child: QuickRefView(useProvider: true)),
    );
  }
}
```

In `RunScreen.build`, add `const quickref = _QuickRefPanel();` with the other panel
locals, then place it after `initiative` in BOTH layouts:
- Wide: in the left `Column`, after `initiative,` add `SizedBox(height: 12), quickref,`
  (before `SizedBox(height: 12), party,`).
- Narrow: in the `ListView` children, after `initiative,` add
  `SizedBox(height: 12), quickref,` (before the `party` entry).

- [ ] **Step 3: `/rules` slash command**

First add a `rules` value to the `ContentType` enum in
`lib/engine/content_registry.dart:4`:

```dart
enum ContentType { all, monsters, spells, rules }
```

Search `lib/` for exhaustive switches on `ContentType` (e.g. in `content_registry.dart`
`searchContent`, and `reference_view.dart`). If any `switch (type)` lacks a default and
now errors on the missing `rules` case, add a `case ContentType.rules:` that returns an
empty `ContentResults(monsters: [], spells: [])` for search (the view never calls search in
rules mode — Step 4 — but the switch must stay total). Run `flutter analyze
lib/engine/content_registry.dart` to confirm.

In `lib/features/journal_screen.dart`, add a `_BuiltinSlashRow` next to the `/lookup`/
`/spell`/`/monster` rows (~line 1288+):

```dart
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-rules'),
                icon: Icons.menu_book,
                command: '/rules',
                description: 'Rules quick reference for this system',
                onTap: () {
                  _composer.clear();
                  _openReference('', ContentType.rules);
                },
              ),
```

- [ ] **Step 4: Reference "Rules" mode**

In `lib/features/reference_view.dart`, add `import 'quick_ref_view.dart';`. Add a Rules
segment to the `SegmentedButton<ContentType>` (~line 108):

```dart
            ButtonSegment(value: ContentType.rules, label: Text('Rules')),
```

In the build, when `_type == ContentType.rules`, render `QuickRefView(useProvider: true)`
in place of the search-results list, and hide/disable the search `TextField` (rules aren't
searchable in P1). Concretely, wrap the results body:

```dart
        if (_type == ContentType.rules)
          const Expanded(child: QuickRefView(useProvider: true))
        else
          // ... existing search field + results list ...
```

(Place the search field inside the `else` branch, or leave it visible but ignored — the
key requirement is that `searchContent` is NOT called and the QuickRef shows. Match the
file's existing layout; keep the `reference-sources` footer visible in both modes.)

- [ ] **Step 5: Analyze + smoke test**

Add a light surface test `test/quickref_surfaces_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/quick_ref.dart';
import 'package:juice_oracle/features/quick_ref_view.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  testWidgets('showQuickRef opens the active card', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        systemQuickRefProvider.overrideWithValue(kSystemQuickRefs['cairn']),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showQuickRef(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Cairn — Quick Reference'), findsOneWidget);
  });
}
```

Run: `flutter test test/quickref_surfaces_test.dart` → PASS.
Run: `flutter analyze lib/features/encounter_screen.dart lib/features/run_screen.dart lib/features/journal_screen.dart lib/features/reference_view.dart lib/engine/content_registry.dart` → no new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/features/encounter_screen.dart lib/features/run_screen.dart \
  lib/features/journal_screen.dart lib/features/reference_view.dart \
  lib/engine/content_registry.dart test/quickref_surfaces_test.dart
git commit -m "feat(quickref): wire encounter, run panel, /rules, reference surfaces"
```

---

## Task 4: Full verification + bookkeeping + PR

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze` → no new errors.
Run: `flutter test` → all pass (suite was 1700; +~6 here). If a pre-existing test pins the
`ContentType` value count or a `/lookup`-area slash-row count, update it to include the new
`rules` value / `/rules` row.

- [ ] **Step 2: Update CLAUDE.md**

Add a bullet (near the content-library / reference notes): the Rules QuickRef — authored
facts-only per-system cards in `lib/engine/quick_ref.dart` (`QuickRefCard`/`kSystemQuickRefs`,
7 cards: dnd/ironsworn[+starforged/sundered_isles]/cairn/knave/ose/argosa/kal-arath),
resolved via `resolveSystemQuickRef`/`systemQuickRefProvider` (reuses `resolveSystem`),
rendered read-only by `QuickRefView`/`showQuickRef` on four surfaces (encounter `enc-rules`,
`run-panel-quickref`, `/rules` slash → `ContentType.rules`, Reference Rules segment).
Facts-only (no attribution); remaining systems are drop-in consts. Reference the spec.

- [ ] **Step 3: Commit + push + PR**

```bash
git add CLAUDE.md
git commit -m "docs: note Rules QuickRef cards"
git push -u origin feat/rules-quickref
gh pr create --title "feat(quickref): per-system rules quick reference cards" \
  --body "Implements docs/superpowers/specs/2026-06-29-rules-quickref-design.md"
```

---

## Self-Review notes

- **Spec coverage:** model + 7 cards + resolver reusing `resolveSystem` (T1) ✓; ironsworn
  under 3 keys (T1) ✓; provider (T1) ✓; `QuickRefView` + empty state + `showQuickRef`
  (T2) ✓; all 4 surfaces (T3) ✓; structural self-check test (T1) ✓. Facts-only (names +
  generic effects, no prose); no custom card; no editing — all honored.
- **Watch-outs:** `resolveSystem` returns `starforged`/`sundered_isles` keys — the map
  registers the ironsworn card under all three (T1). Adding `ContentType.rules` may break
  exhaustive switches — T3 Step 3 makes them total. A pre-existing `ContentType`-count or
  slash-row-count test may need updating (T4 Step 1).
- **Type consistency:** `QuickRefCard{system,title,sections}`, `QuickRefSection{title,lines}`,
  `kSystemQuickRefs`, `resolveSystemQuickRef`, `systemQuickRefProvider`, `QuickRefView`,
  `showQuickRef`, keys `enc-rules`/`run-panel-quickref`/`slash-cmd-rules`/`quickref-empty`
  — consistent across tasks.
