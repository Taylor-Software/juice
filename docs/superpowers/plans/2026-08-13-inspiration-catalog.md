# Unified Inspiration Catalog (PR 3 of streamline epic) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One browsable inspiration catalog: the 24 flavor generators, the bundled starter tables, and My Tables all appear — searchable and category-grouped — on Ask → Tables and in the GenerateSheet, with the starter-pack import step gone.

**Architecture:** A pure `buildCatalog` merges three sources into `CatalogEntry` rows (generators read-only, starters read-only shipped as data via a new `starterTablesProvider`, user tables editable). The two surfaces render the same catalog with their existing visual idioms (expansion tiles / chips). All rolls keep the existing `addResult` pipeline and provenance tags. The oracle-data built-in table groups on the Tables tab already render grouped + searchable and are untouched.

**Tech Stack:** Flutter + flutter_riverpod. Package name `loreseer`.

**Spec:** `docs/superpowers/specs/2026-08-12-streamline-library-exclusive-capabilities-design.md` (Part 3)

## Global Constraints

- Provenance unchanged: generator rolls log `sourceTool: sourceToolFor(section)` (`gen-*`), table rolls (starter or user) log `sourceTool: 'custom-table'`. `PayloadCard` rendering and Inspire must keep working (`showLoggedSnackBar` after instant logs — only from hosts that stay mounted).
- Starters are read-only entries with STABLE ids (`starter-<n>` by file order) — no editor, no delete. The one-tap "Add starter tables" import tile dies. Legacy users who already imported the pack must NOT see duplicates: a bundled starter is hidden when a user table with the same name AND `source == kStarterTableSource` exists.
- Bundled-asset load stays STRICT (repo doctrine): `starterTablesProvider` may throw on a malformed asset; only USER-persisted reads are tolerant.
- Widget tests: never hit rootBundle — override `starterTablesProvider` with a fixture list; pump `TablesScreen`/`GenerateSheet` the way their existing tests do (copy that scaffolding).
- Format only files you edit.

---

### Task 1: Engine catalog + starter provider

**Files:**
- Create: `lib/engine/inspiration_catalog.dart`
- Modify: `lib/state/providers.dart` (add `starterTablesProvider` near the other asset FutureProviders, e.g. after `dungeonDataProvider` ~line 79)
- Test: `test/inspiration_catalog_test.dart`

**Interfaces:**
- Consumes: `GeneratorDef`/`GenSection`/`flavorGenerators` (`lib/engine/generator_registry.dart`), `CustomTable`/`decodeTablePack`/`kStarterTableSource`/`matchesTableQuery`/`kUncategorized` (`lib/engine/custom_table.dart`).
- Produces (used by Tasks 2–3):
  - `enum CatalogKind { generator, table }`
  - `class CatalogEntry { String id; String name; CatalogKind kind; String category; String genre; String source; bool editable; GeneratorDef? gen; CustomTable? table; }`
  - `List<CatalogEntry> buildCatalog({required List<GeneratorDef> generators, required List<CustomTable> starters, required List<CustomTable> userTables})`
  - `bool matchesCatalogQuery(CatalogEntry e, String q)` (lowercased q; name/genre/category/source)
  - `List<(String, List<CatalogEntry>)> groupCatalogByCategory(List<CatalogEntry> entries)` (category-sorted, insertion order within)
  - `final starterTablesProvider = FutureProvider<List<CustomTable>>(...)` — loads `assets/starter_tables.json` via `decodeTablePack`, re-ids rows to stable `starter-<n>`.

- [ ] **Step 1: Write the failing test**

```dart
// test/inspiration_catalog_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/custom_table.dart';
import 'package:loreseer/engine/generator_registry.dart';
import 'package:loreseer/engine/inspiration_catalog.dart';

CustomTable t(String id, String name,
        {String cat = '', String genre = '', String src = ''}) =>
    CustomTable(
        id: id, name: name, rows: const [], category: cat, genre: genre,
        source: src);

void main() {
  test('buildCatalog merges three sources with right kinds/flags', () {
    final cat = buildCatalog(
      generators: flavorGenerators,
      starters: [t('starter-0', 'Rumors', cat: 'Hooks',
          src: kStarterTableSource)],
      userTables: [t('u1', 'My monsters', cat: 'Foes')],
    );
    expect(cat.where((e) => e.kind == CatalogKind.generator).length,
        flavorGenerators.length);
    final starter = cat.singleWhere((e) => e.id == 'starter-0');
    expect(starter.editable, isFalse);
    expect(starter.kind, CatalogKind.table);
    final mine = cat.singleWhere((e) => e.id == 'u1');
    expect(mine.editable, isTrue);
    // Generators carry their section label as category.
    expect(cat.firstWhere((e) => e.name == 'Word Oracle').category,
        GenSection.story.label);
  });

  test('a bundled starter hides when the user already imported it', () {
    final cat = buildCatalog(
      generators: const [],
      starters: [t('starter-0', 'Rumors', src: kStarterTableSource)],
      userTables: [t('u9', 'Rumors', src: kStarterTableSource)],
    );
    expect(cat.where((e) => e.name == 'Rumors').length, 1);
    expect(cat.single.id, 'u9');
  });

  test('matchesCatalogQuery spans name/genre/category/source', () {
    final e = buildCatalog(
      generators: const [],
      starters: const [],
      userTables: [t('u1', 'Wild beasts', cat: 'Foes', genre: 'fantasy',
          src: 'homebrew')],
    ).single;
    for (final q in ['beast', 'foes', 'fantasy', 'homebrew']) {
      expect(matchesCatalogQuery(e, q), isTrue, reason: q);
    }
    expect(matchesCatalogQuery(e, 'sci-fi'), isFalse);
  });

  test('groupCatalogByCategory sorts categories, keeps insertion order', () {
    final groups = groupCatalogByCategory(buildCatalog(
      generators: const [],
      starters: const [],
      userTables: [t('a', 'A', cat: 'Zed'), t('b', 'B', cat: 'Alpha'),
          t('c', 'C', cat: 'Zed')],
    ));
    expect(groups.map((g) => g.$1).toList(), ['Alpha', 'Zed']);
    expect(groups.last.$2.map((e) => e.name).toList(), ['A', 'C']);
  });
}
```

Note: verify `CustomTable`'s actual constructor (named params, `category`/`genre`/`source` field names) in `lib/engine/custom_table.dart` before running; adjust the `t` helper to match reality. If category default is `kUncategorized`, adjust the empty-category expectations accordingly.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/inspiration_catalog_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
// lib/engine/inspiration_catalog.dart
//
// One inspiration catalog over three sources: the flavor generators, the
// bundled read-only starter tables, and the user's My Tables. Both rolling
// surfaces (Ask → Tables, GenerateSheet) render this list, so a table or
// generator added in one place appears in both. Pure — no Flutter.
import 'custom_table.dart';
import 'generator_registry.dart';

enum CatalogKind { generator, table }

class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.name,
    required this.kind,
    required this.category,
    this.genre = '',
    this.source = '',
    this.editable = false,
    this.gen,
    this.table,
  });
  final String id;
  final String name;
  final CatalogKind kind;
  final String category;
  final String genre;
  final String source;

  /// True only for the user's own tables — the editor opens on these.
  final bool editable;
  final GeneratorDef? gen; // set when kind == generator
  final CustomTable? table; // set when kind == table
}

/// Merges the three sources. A bundled starter is dropped when the user
/// library already holds a table with the same name and starter source —
/// legacy libraries imported the pack via the old one-tap button, and the
/// user's (possibly edited) copy wins.
List<CatalogEntry> buildCatalog({
  required List<GeneratorDef> generators,
  required List<CustomTable> starters,
  required List<CustomTable> userTables,
}) {
  final imported = {
    for (final t in userTables)
      if (t.source == kStarterTableSource) t.name,
  };
  return [
    for (final g in generators)
      CatalogEntry(
        id: 'gen-${g.label.toLowerCase().replaceAll(' ', '-')}',
        name: g.label,
        kind: CatalogKind.generator,
        category: g.section.label,
        source: 'Built-in',
        gen: g,
      ),
    for (final t in starters)
      if (!imported.contains(t.name))
        CatalogEntry(
          id: t.id,
          name: t.name,
          kind: CatalogKind.table,
          category: t.category,
          genre: t.genre,
          source: t.source,
          table: t,
        ),
    for (final t in userTables)
      CatalogEntry(
        id: t.id,
        name: t.name,
        kind: CatalogKind.table,
        category: t.category,
        genre: t.genre,
        source: t.source,
        editable: true,
        table: t,
      ),
  ];
}

/// Library search across the whole catalog (name/genre/category/source),
/// mirroring [matchesTableQuery]'s fields. [q] arrives lowercased.
bool matchesCatalogQuery(CatalogEntry e, String q) => [
      e.name,
      e.genre,
      e.category,
      e.source,
    ].any((f) => f.toLowerCase().contains(q));

/// Category-sorted grouping; entries keep their catalog order inside each
/// group (generators first, then starters, then user tables).
List<(String, List<CatalogEntry>)> groupCatalogByCategory(
    List<CatalogEntry> entries) {
  final byCat = <String, List<CatalogEntry>>{};
  for (final e in entries) {
    byCat.putIfAbsent(e.category, () => []).add(e);
  }
  final cats = byCat.keys.toList()..sort();
  return [for (final c in cats) (c, byCat[c]!)];
}
```

`lib/state/providers.dart` — near the other asset loaders (after `dungeonDataProvider`):

```dart
/// Loads the bundled starter tables as read-only catalog entries. STRICT on
/// purpose (bundled asset, build-verified); rows get stable `starter-<n>`
/// ids so widget keys and dedup survive reloads. Replaces the old one-tap
/// import — starters now appear in the catalog directly.
final starterTablesProvider = FutureProvider<List<CustomTable>>((ref) async {
  final raw = await rootBundle.loadString('assets/starter_tables.json');
  final tables = decodeTablePack(raw);
  return [
    for (final (i, t) in tables.indexed) t.copyWith(id: 'starter-$i'),
  ];
});
```

Note: check `CustomTable.copyWith` exists and accepts `id`; if it doesn't take `id`, rebuild via `CustomTable.fromJson({...t.toJson(), 'id': 'starter-$i'})` or the constructor — match whatever the class offers. Add the import of `inspiration_catalog.dart` only where used (Tasks 2–3); providers.dart needs only `custom_table.dart` (already imported).

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/inspiration_catalog_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/engine/inspiration_catalog.dart lib/state/providers.dart test/inspiration_catalog_test.dart
git commit -m "feat(catalog): unified inspiration catalog engine + bundled starters provider"
```

---

### Task 2: Tables tab renders the catalog

**Files:**
- Modify: `lib/features/tables_screen.dart`
- Test: `test/tables_catalog_test.dart` (new) + update the existing starter-pack test (find: `grep -rln "tables-starter-pack" test/`)

**Interfaces:**
- Consumes: Task 1 symbols; existing `_rollCustomTable` (extend for read-only starters), `journalProvider.addResult`, `showLoggedSnackBar`, `sourceToolFor`, `widget.oracle`.
- Produces: keys `tables-generators` (ExpansionTile), `gen-roll-<entry.id>` rows, `tables-starters` (ExpansionTile), `starter-roll-<id>` rows. The `tables-starter-pack` import tile and `_importStarterPack` are REMOVED.

- [ ] **Step 1: Write the failing test**

Copy the pump scaffolding from the existing Tables-tab test (find: `grep -rln "tables-my-tables\|tables-search" test/ | head`; it overrides the oracle-data provider with a fixture). Override `starterTablesProvider` with `[CustomTable(id: 'starter-0', name: 'Rumors', ...one row...)]`. Scenarios (write real tests):

```dart
// 1. A 'Generators' section lists flavor generators; tapping the
//    'Word Oracle' row (key gen-roll-gen-word-oracle) logs a journal entry
//    with sourceTool 'gen-story' (assert via journalProvider state).
// 2. A 'Starter tables' section lists the fixture starter; tapping
//    starter-roll-starter-0 logs a 'custom-table' entry. No edit affordance
//    on the row (no my-table-edit-* key).
// 3. Searching 'rumor' keeps the starter row and drops non-matching
//    generators; searching 'word' keeps the Word Oracle generator row.
// 4. tables-starter-pack is GONE even with an empty user library.
// 5. With a user table named 'Rumors' sourced kStarterTableSource, the
//    starter section hides its bundled duplicate.
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/tables_catalog_test.dart`
Expected: FAIL.

- [ ] **Step 3: Implement**

In `_TablesScreenState.build`, watch the catalog inputs and build entries once:

```dart
    final starters =
        ref.watch(starterTablesProvider).valueOrNull ?? const <CustomTable>[];
    final catalog = buildCatalog(
        generators: flavorGenerators,
        starters: starters,
        userTables: customTables);
    final gens = [
      for (final e in catalog)
        if (e.kind == CatalogKind.generator &&
            (q.isEmpty || matchesCatalogQuery(e, q)))
          e,
    ];
    final starterEntries = [
      for (final e in catalog)
        if (e.kind == CatalogKind.table && !e.editable &&
            (q.isEmpty || matchesCatalogQuery(e, q)))
          e,
    ];
```

Render, between the My Tables section and the built-in oracle groups:

```dart
              if (starterEntries.isNotEmpty)
                ExpansionTile(
                  key: q.isEmpty
                      ? const PageStorageKey('tables-starters')
                      : const ValueKey('tables-starters-search'),
                  initiallyExpanded: q.isNotEmpty,
                  title: Text('Starter tables',
                      style: theme.textTheme.titleMedium),
                  subtitle: const Text(
                      'A general-play core set: NPCs, places, hooks, rumors…'),
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  children: [
                    for (final e in starterEntries)
                      Card(
                        child: ListTile(
                          key: Key('starter-roll-${e.id}'),
                          title: Text(e.name),
                          subtitle: switch ([
                            if (e.genre.trim().isNotEmpty) e.genre.trim(),
                            if (e.category.trim().isNotEmpty)
                              e.category.trim(),
                          ].join(' · ')) {
                            '' => null,
                            final meta => Text(meta),
                          },
                          trailing: const Icon(Icons.casino_outlined),
                          onTap: () => _rollCustomTable(e.table!),
                        ),
                      ),
                  ],
                ),
              if (gens.isNotEmpty)
                ExpansionTile(
                  key: q.isEmpty
                      ? const PageStorageKey('tables-generators')
                      : const ValueKey('tables-generators-search'),
                  initiallyExpanded: q.isNotEmpty,
                  title:
                      Text('Generators', style: theme.textTheme.titleMedium),
                  subtitle:
                      const Text('One-tap story, NPC, and detail rolls'),
                  childrenPadding: const EdgeInsets.only(bottom: 4),
                  children: [
                    for (final e in gens)
                      Card(
                        child: ListTile(
                          key: Key('gen-roll-${e.id}'),
                          title: Text(e.name),
                          subtitle: Text(e.category),
                          trailing: const Icon(Icons.casino_outlined),
                          onTap: () => _rollGenerator(e),
                        ),
                      ),
                  ],
                ),
```

Add the handler beside `_rollCustomTable` (same log-then-snackbar shape):

```dart
  /// Roll a catalog generator and log it under its section's gen-* tag —
  /// identical provenance to the same generator rolled from the composer's
  /// GenerateSheet.
  Future<void> _rollGenerator(CatalogEntry e) async {
    final g = e.gen!;
    final r = g.run(widget.oracle);
    final id = await ref.read(journalProvider.notifier).addResult(
        r.title, r.asText,
        sourceTool: sourceToolFor(g.section), payload: r.toPayload());
    if (!mounted) return;
    showLoggedSnackBar(context, ref, id);
  }
```

Delete the `tables-starter-pack` tile and `_importStarterPack` (its `rootBundle` import too, if now unused). Update `_myTablesSection`'s caller comment if it referenced the import. Fix/remove the existing starter-pack import test (it now asserts the tile is gone — fold into scenario 4 or keep in place, whichever file fits).

Imports to add: `../engine/generator_registry.dart`, `../engine/inspiration_catalog.dart`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/tables_catalog_test.dart $(grep -rln "tables-my-tables\|tables-starter-pack\|tables-search" test/ | tr '\n' ' ')`
Expected: PASS.

- [ ] **Step 5: Format + commit**

```bash
dart format lib/features/tables_screen.dart
git add lib/features/tables_screen.dart test/
git commit -m "feat(catalog): Tables tab lists generators + bundled starters; import tile retired"
```

---

### Task 3: GenerateSheet renders the starters

**Files:**
- Modify: `lib/features/generate_sheet.dart` (a "Starter Tables" section beside the existing "My Tables" section ~line 216)
- Test: extend `test/generate_sheet_test.dart`

**Interfaces:**
- Consumes: `starterTablesProvider`, `buildCatalog`/`CatalogKind` (or just the starters list + the same name-dedup rule — use `buildCatalog` so the dedup logic isn't duplicated), existing `table-roll` handler shape (`rollCustomTable` + `addResult` sourceTool `'custom-table'`).
- Produces: `starter-chip-<id>` ActionChips.

- [ ] **Step 1: Write the failing test**

In `test/generate_sheet_test.dart` (existing scaffolding), override `starterTablesProvider` with one fixture table. Scenarios:

```dart
// 1. A 'Starter Tables' section shows starter-chip-starter-0; tapping it
//    logs a 'custom-table' journal entry (sheet stays open or closes —
//    match the existing My-Tables chip behavior exactly).
// 2. With a user table named identically (source kStarterTableSource), the
//    starter chip is hidden (dedup via buildCatalog).
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/generate_sheet_test.dart`
Expected: new cases FAIL.

- [ ] **Step 3: Implement**

Mirror the existing "My Tables" section block (~line 216): watch `starterTablesProvider` + `customTablesProvider`, compute

```dart
    final starterEntries = buildCatalog(
      generators: const [],
      starters: starters,
      userTables: customTables,
    ).where((e) => e.kind == CatalogKind.table && !e.editable).toList();
```

and render a `'Starter Tables'` label + Wrap of ActionChips keyed `starter-chip-<id>`, whose onPressed does exactly what the `table-roll-<id>` chip does (roll via `rollCustomTable(e.table!, ...)`, log `sourceTool: 'custom-table'`, same open/close behavior). Imports: `../engine/inspiration_catalog.dart`.

- [ ] **Step 4: Run tests**

Run: `flutter test test/generate_sheet_test.dart`
Expected: PASS.

- [ ] **Step 5: Format + commit**

```bash
dart format lib/features/generate_sheet.dart
git add lib/features/generate_sheet.dart test/generate_sheet_test.dart
git commit -m "feat(catalog): GenerateSheet offers the bundled starter tables"
```

---

### Task 4: Full verify + docs

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Analyze + full suite**

Run: `flutter analyze && flutter test`
Expected: clean + green. Attribute failures ONLY from the final "Failing tests:" block.

- [ ] **Step 2: CLAUDE.md note**

```markdown
- **Unified inspiration catalog (2026-08-13, PR 3 of the streamline epic)** —
  one browsable catalog over three sources: flavor generators + bundled
  starter tables + My Tables. Pure `lib/engine/inspiration_catalog.dart`
  (`CatalogEntry`/`CatalogKind`, `buildCatalog` — dedups a bundled starter
  when the user library holds a same-name `kStarterTableSource` copy,
  `matchesCatalogQuery`, `groupCatalogByCategory`) +
  `starterTablesProvider` (STRICT asset load, stable `starter-<n>` ids).
  Ask → Tables gained 'Starter tables' (`starter-roll-<id>`) + 'Generators'
  (`gen-roll-<id>`) sections with unified search; the one-tap
  `tables-starter-pack` import tile is RETIRED (starters render directly).
  GenerateSheet gained `starter-chip-<id>` chips. Provenance unchanged:
  generators log `gen-*`, tables log `'custom-table'`. See
  `docs/superpowers/specs/2026-08-12-streamline-library-exclusive-capabilities-design.md`.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: unified inspiration catalog project note"
```
