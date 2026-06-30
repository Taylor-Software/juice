# User-Authored Ref Cards Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** App-global user-authored ref cards that reuse the `QuickRefCard` model and render in `QuickRefView` alongside the authored system card, on every QuickRef surface.

**Architecture:** `UserRefCard` + `parseRefSections` in `quick_ref.dart` (pure); an app-global `userRefCardsProvider` (mirrors `CustomTablesNotifier`); the `QuickRefView(useProvider:true)` path becomes a composite (authored card + user cards + Add) with a `showRefCardEditor` dialog. Surfaces unchanged (they already embed the provider view).

**Tech Stack:** Flutter, Riverpod, SharedPreferences, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-06-29-user-ref-cards-design.md`

**Environment:** `flutter` at `$HOME/development/flutter/bin` — `export PATH="$HOME/development/flutter/bin:$PATH"`. Package `juice_oracle`.

**Reference shapes (verified):**
- `lib/engine/quick_ref.dart` — `QuickRefSection(title, lines)` (positional), `QuickRefCard{system,title,sections}`.
- `CustomTablesNotifier` (`lib/state/providers.dart`) — the exact template: `static const _key`, `build()` decodes via `maybeFromJson`, `_ready`, `_save(list)` sets `state = AsyncData(list)`, `add/remove/replace`. `customTablesProvider = AsyncNotifierProvider<CustomTablesNotifier, List<CustomTable>>(...)`.
- `lib/features/quick_ref_view.dart` — current `QuickRefView` (read full file before editing); `systemQuickRefProvider` from providers.dart.

---

## Task 1: Engine — UserRefCard + parseRefSections + section JSON (TDD)

**Files:** Modify `lib/engine/quick_ref.dart`; Test `test/user_ref_card_test.dart`.

- [ ] **Step 1: Write the failing test**

```dart
// test/user_ref_card_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/quick_ref.dart';

void main() {
  group('parseRefSections', () {
    test('empty input -> []', () {
      expect(parseRefSections(''), isEmpty);
      expect(parseRefSections('   \n\n'), isEmpty);
    });
    test('headings split sections; bullets attach to current', () {
      final s = parseRefSections('# Combat\nroll to hit\ndeal damage\n# Rest\nsleep');
      expect(s.map((e) => e.title).toList(), ['Combat', 'Rest']);
      expect(s[0].lines, ['roll to hit', 'deal damage']);
      expect(s[1].lines, ['sleep']);
    });
    test('pre-heading lines go under a leading Notes section', () {
      final s = parseRefSections('house rule: crits explode\n# Combat\nhit');
      expect(s.first.title, 'Notes');
      expect(s.first.lines, ['house rule: crits explode']);
      expect(s[1].title, 'Combat');
    });
    test('blank lines ignored; empty headings dropped', () {
      final s = parseRefSections('# A\n\nx\n#\n# B\ny');
      // '#' with no following lines before '# B' is dropped (no lines).
      expect(s.map((e) => e.title).toList(), ['A', 'B']);
    });
  });

  group('UserRefCard', () {
    test('toQuickRefCard carries title + sections', () {
      const c = UserRefCard(
          id: '1', title: 'My Rules', sections: [QuickRefSection('A', ['x'])]);
      final q = c.toQuickRefCard();
      expect(q.title, 'My Rules');
      expect(q.sections.single.lines, ['x']);
    });
    test('JSON round-trips; maybeFromJson tolerant', () {
      const c = UserRefCard(
          id: '1', title: 'T', sections: [QuickRefSection('A', ['x', 'y'])]);
      final back = UserRefCard.maybeFromJson(c.toJson());
      expect(back?.id, '1');
      expect(back?.title, 'T');
      expect(back?.sections.single.title, 'A');
      expect(back?.sections.single.lines, ['x', 'y']);
      expect(UserRefCard.maybeFromJson(null), isNull);
      expect(UserRefCard.maybeFromJson(const {'id': 1}), isNull); // bad types
    });
  });
}
```

- [ ] **Step 2: Run → FAIL.** `flutter test test/user_ref_card_test.dart`

- [ ] **Step 3: Edit `lib/engine/quick_ref.dart`**

Add `toJson`/`maybeFromJson` to `QuickRefSection` (keep the positional constructor):

```dart
class QuickRefSection {
  const QuickRefSection(this.title, this.lines);
  final String title;
  final List<String> lines;

  Map<String, dynamic> toJson() => {'title': title, 'lines': lines};

  static QuickRefSection? maybeFromJson(Object? raw) {
    if (raw is! Map) return null;
    final t = raw['title'], l = raw['lines'];
    if (t is! String || l is! List) return null;
    return QuickRefSection(t, l.whereType<String>().toList());
  }
}
```

Append, at the end of the file:

```dart
/// A user-authored ref card. Renders as a [QuickRefCard].
class UserRefCard {
  const UserRefCard({required this.id, required this.title, required this.sections});
  final String id;
  final String title;
  final List<QuickRefSection> sections;

  QuickRefCard toQuickRefCard() =>
      QuickRefCard(system: 'custom', title: title, sections: sections);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sections': [for (final s in sections) s.toJson()],
      };

  static UserRefCard? maybeFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], title = raw['title'], secs = raw['sections'];
    if (id is! String || title is! String || secs is! List) return null;
    return UserRefCard(
      id: id,
      title: title,
      sections: secs.map(QuickRefSection.maybeFromJson).whereType<QuickRefSection>().toList(),
    );
  }
}

/// Parses an editor body into sections (pure). A line starting with '#' begins a
/// new section with that heading; other non-empty lines are bullets of the
/// current section; non-empty lines before the first heading go under a leading
/// 'Notes' section; blank lines are ignored; headings with no bullets are dropped.
List<QuickRefSection> parseRefSections(String text) {
  final out = <QuickRefSection>[];
  var title = 'Notes';
  var lines = <String>[];
  void flush() {
    if (lines.isNotEmpty) out.add(QuickRefSection(title, List.of(lines)));
    lines = [];
  }

  for (final raw in text.split('\n')) {
    final t = raw.trim();
    if (t.isEmpty) continue;
    if (t.startsWith('#')) {
      flush();
      final h = t.replaceFirst(RegExp(r'^#+\s*'), '').trim();
      title = h.isEmpty ? 'Notes' : h;
    } else {
      lines.add(t);
    }
  }
  flush();
  return out;
}
```

- [ ] **Step 4: Run → PASS + analyze.**

`flutter test test/user_ref_card_test.dart`
`flutter analyze lib/engine/quick_ref.dart test/user_ref_card_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/engine/quick_ref.dart test/user_ref_card_test.dart
git commit -m "feat(user-ref-cards): UserRefCard model + parseRefSections (pure)"
```

---

## Task 2: App-global provider (mirror CustomTablesNotifier)

**Files:** Modify `lib/state/providers.dart`.

- [ ] **Step 1: Add the notifier + provider**

Place near `customTablesProvider`. `UserRefCard`/quick_ref is already imported (the
QuickRef feature added `import '../engine/quick_ref.dart';`); if not, add it.

```dart
class UserRefCardsNotifier extends AsyncNotifier<List<UserRefCard>> {
  static const _key = 'juice.userrefcards.v1';

  @override
  Future<List<UserRefCard>> build() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    return (jsonDecode(raw) as List)
        .map(UserRefCard.maybeFromJson)
        .whereType<UserRefCard>()
        .toList();
  }

  Future<List<UserRefCard>> get _ready async => state.valueOrNull ?? await future;

  Future<void> _save(List<UserRefCard> list) async {
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(list.map((c) => c.toJson()).toList()));
    state = AsyncData(list);
  }

  Future<void> add(UserRefCard c) async => _save([...await _ready, c]);
  Future<void> remove(String id) async =>
      _save((await _ready).where((c) => c.id != id).toList());
  Future<void> replace(UserRefCard c) async =>
      _save((await _ready).map((e) => e.id == c.id ? c : e).toList());
}

final userRefCardsProvider =
    AsyncNotifierProvider<UserRefCardsNotifier, List<UserRefCard>>(
        UserRefCardsNotifier.new);
```

- [ ] **Step 2: Analyze**

`flutter analyze lib/state/providers.dart` → no new issues.

- [ ] **Step 3: Commit**

```bash
git add lib/state/providers.dart
git commit -m "feat(user-ref-cards): app-global userRefCardsProvider"
```

---

## Task 3: QuickRefView composite + editor dialog (TDD)

**Files:** Modify `lib/features/quick_ref_view.dart`; Test `test/user_ref_cards_view_test.dart`.

First READ the current `lib/features/quick_ref_view.dart` in full.

- [ ] **Step 1: Write the failing widget test**

```dart
// test/user_ref_cards_view_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/quick_ref.dart';
import 'package:juice_oracle/features/quick_ref_view.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, List<Override> overrides) async {
    await tester.pumpWidget(ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
          home: Scaffold(body: QuickRefView(useProvider: true))),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders a user card + the Add button (no system card)',
      (tester) async {
    await pump(tester, [
      systemQuickRefProvider.overrideWithValue(null),
      userRefCardsProvider.overrideWith(() => _FakeUserCards([
            const UserRefCard(
                id: '1', title: 'House Rules', sections: [
              QuickRefSection('Crits', ['crits explode']),
            ]),
          ])),
    ]);
    expect(find.text('House Rules'), findsOneWidget);
    expect(find.text('Crits'), findsOneWidget);
    expect(find.byKey(const Key('quickref-add')), findsOneWidget);
    expect(find.byKey(const Key('quickref-edit-1')), findsOneWidget);
    expect(find.byKey(const Key('quickref-delete-1')), findsOneWidget);
  });

  testWidgets('empty state still shows the Add button', (tester) async {
    await pump(tester, [
      systemQuickRefProvider.overrideWithValue(null),
      userRefCardsProvider.overrideWith(() => _FakeUserCards(const [])),
    ]);
    expect(find.byKey(const Key('quickref-empty')), findsOneWidget);
    expect(find.byKey(const Key('quickref-add')), findsOneWidget);
  });
}

class _FakeUserCards extends UserRefCardsNotifier {
  _FakeUserCards(this._initial);
  final List<UserRefCard> _initial;
  @override
  Future<List<UserRefCard>> build() async => _initial;
}
```

- [ ] **Step 2: Run → FAIL** (`quickref-add` not found / overrideWith signature).

If `UserRefCardsNotifier` can't be subclassed for the fake cleanly, instead override with
`userRefCardsProvider.overrideWith(() => UserRefCardsNotifier())` after seeding
`SharedPreferences.setMockInitialValues({'juice.userrefcards.v1': jsonEncode([...])})`; pick
whichever compiles. The assertions on keys/text are the contract.

- [ ] **Step 3: Rewrite `lib/features/quick_ref_view.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/quick_ref.dart';
import '../state/providers.dart';

/// Read-only render of a system's QuickRef card. Pass [card] explicitly (pure,
/// single-card), or set [useProvider] to render the active system's authored
/// card PLUS the user's app-global cards + an Add control.
class QuickRefView extends ConsumerWidget {
  const QuickRefView({super.key, this.card, this.useProvider = false});
  final QuickRefCard? card;
  final bool useProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (!useProvider) {
      final c = card;
      if (c == null) return _empty(context);
      return ListView(
        key: const Key('quickref-list'),
        padding: const EdgeInsets.all(12),
        children: _cardBlock(theme, c),
      );
    }

    final authored = ref.watch(systemQuickRefProvider);
    final userCards = ref.watch(userRefCardsProvider).valueOrNull ?? const [];

    if (authored == null && userCards.isEmpty) {
      return ListView(
        key: const Key('quickref-list'),
        padding: const EdgeInsets.all(12),
        children: [
          _empty(context),
          const SizedBox(height: 12),
          _addButton(context, ref),
        ],
      );
    }

    return ListView(
      key: const Key('quickref-list'),
      padding: const EdgeInsets.all(12),
      children: [
        if (authored != null) ..._cardBlock(theme, authored),
        for (final u in userCards) ...[
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(u.title, style: theme.textTheme.titleLarge),
              ),
              IconButton(
                key: Key('quickref-edit-${u.id}'),
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit card',
                onPressed: () => showRefCardEditor(context, ref, existing: u),
              ),
              IconButton(
                key: Key('quickref-delete-${u.id}'),
                icon: const Icon(Icons.delete_outline, size: 20),
                tooltip: 'Delete card',
                onPressed: () =>
                    ref.read(userRefCardsProvider.notifier).remove(u.id),
              ),
            ],
          ),
          ..._sections(theme, u.sections),
        ],
        const SizedBox(height: 12),
        _addButton(context, ref),
      ],
    );
  }

  Widget _addButton(BuildContext context, WidgetRef ref) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          key: const Key('quickref-add'),
          icon: const Icon(Icons.add),
          label: const Text('Add card'),
          onPressed: () => showRefCardEditor(context, ref),
        ),
      );

  Widget _empty(BuildContext context) => Center(
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

  List<Widget> _cardBlock(ThemeData theme, QuickRefCard c) => [
        Text(c.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        ..._sections(theme, c.sections),
      ];

  List<Widget> _sections(ThemeData theme, List<QuickRefSection> sections) => [
        for (final s in sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(s.title, style: theme.textTheme.titleSmall),
          ),
          for (final line in s.lines)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: theme.textTheme.bodyMedium),
                  Expanded(child: Text(line, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ];
}

/// Opens the active system's QuickRef (+ user cards) in a modal bottom sheet.
Future<void> showQuickRef(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.85,
        child: QuickRefView(useProvider: true),
      ),
    );

/// Body seed: render a card's sections back into the '#'-heading editor format.
String _bodyFromSections(List<QuickRefSection> sections) => sections
    .map((s) => '# ${s.title}\n${s.lines.join('\n')}')
    .join('\n')
    .trim();

/// Add/edit a user ref card. Parses the body via [parseRefSections]; saves only
/// when the title and parsed sections are non-empty.
Future<void> showRefCardEditor(BuildContext context, WidgetRef ref,
    {UserRefCard? existing}) async {
  final titleCtrl = TextEditingController(text: existing?.title ?? '');
  final bodyCtrl = TextEditingController(
      text: existing == null ? '' : _bodyFromSections(existing.sections));
  final saved = await showDialog<bool>(
    context: context,
    builder: (dctx) => AlertDialog(
      title: Text(existing == null ? 'New card' : 'Edit card'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('refcard-title'),
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('refcard-body'),
              controller: bodyCtrl,
              minLines: 5,
              maxLines: 12,
              decoration: const InputDecoration(
                labelText: 'Body',
                hintText: '# Section heading\nbullet line\nbullet line',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (existing != null)
          TextButton(
            key: const Key('refcard-delete'),
            onPressed: () {
              ref.read(userRefCardsProvider.notifier).remove(existing.id);
              Navigator.pop(dctx, false);
            },
            child: const Text('Delete'),
          ),
        TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Cancel')),
        FilledButton(
          key: const Key('refcard-save'),
          onPressed: () => Navigator.pop(dctx, true),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (saved != true) return;
  final title = titleCtrl.text.trim();
  final sections = parseRefSections(bodyCtrl.text);
  if (title.isEmpty || sections.isEmpty) return;
  final notifier = ref.read(userRefCardsProvider.notifier);
  if (existing == null) {
    notifier.add(UserRefCard(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
        sections: sections));
  } else {
    notifier.replace(
        UserRefCard(id: existing.id, title: title, sections: sections));
  }
}
```

- [ ] **Step 4: Run tests + analyze**

`flutter test test/user_ref_cards_view_test.dart test/quick_ref_view_test.dart` → PASS
(the existing `quick_ref_view_test.dart` explicit-`card:` tests must still pass — the
`!useProvider` branch is unchanged behavior).
`flutter analyze lib/features/quick_ref_view.dart test/user_ref_cards_view_test.dart`

- [ ] **Step 5: Commit**

```bash
git add lib/features/quick_ref_view.dart test/user_ref_cards_view_test.dart
git commit -m "feat(user-ref-cards): composite QuickRefView + showRefCardEditor"
```

---

## Task 4: Full verification + bookkeeping + PR

- [ ] **Step 1: Full analyze + test**

`flutter analyze` → no new errors.
`flutter test` → all pass (suite was 1707; +~6 here).

- [ ] **Step 2: Update CLAUDE.md** — extend the Rules QuickRef bullet: user-authored cards
(`UserRefCard` + `parseRefSections` in `quick_ref.dart`; app-global `userRefCardsProvider`,
`juice.userrefcards.v1`, NOT exported) render under the authored card in
`QuickRefView(useProvider)` via `showRefCardEditor` (`#`-heading body), so they appear on all
four surfaces; reference the spec.

- [ ] **Step 3: Commit + push + PR**

```bash
git add CLAUDE.md
git commit -m "docs: note user-authored ref cards"
git push -u origin feat/user-ref-cards
gh pr create --title "feat(quickref): user-authored ref cards" \
  --body "Implements docs/superpowers/specs/2026-06-29-user-ref-cards-design.md"
```

---

## Self-Review notes

- **Spec coverage:** UserRefCard + parseRefSections (T1) ✓; app-global provider (T2) ✓;
  composite view + editor + Add/edit/delete + empty-state Add (T3) ✓; surfaces unchanged
  (they embed the provider view) ✓; tests pure + widget (T1, T3) ✓.
- **Watch-out:** the `!useProvider` (explicit `card:`) path must stay behavior-identical so
  `quick_ref_view_test.dart` keeps passing — Task 3 keeps it as a separate branch.
- **Type consistency:** `UserRefCard{id,title,sections}`, `parseRefSections`,
  `userRefCardsProvider`, keys `quickref-add`/`quickref-edit-<id>`/`quickref-delete-<id>`/
  `refcard-title`/`refcard-body`/`refcard-save`/`refcard-delete` — consistent across tasks.
