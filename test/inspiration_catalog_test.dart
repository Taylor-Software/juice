import 'package:flutter_test/flutter_test.dart';
import 'package:loreseer/engine/custom_table.dart';
import 'package:loreseer/engine/generator_registry.dart';
import 'package:loreseer/engine/inspiration_catalog.dart';

CustomTable t(String id, String name,
        {String cat = '', String genre = '', String src = ''}) =>
    CustomTable(
        id: id,
        name: name,
        rows: const [],
        category: cat,
        genre: genre,
        source: src);

void main() {
  test('buildCatalog merges three sources with right kinds/flags', () {
    final cat = buildCatalog(
      generators: flavorGenerators,
      starters: [
        t('starter-0', 'Rumors', cat: 'Hooks', src: kStarterTableSource)
      ],
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
      userTables: [
        t('u1', 'Wild beasts', cat: 'Foes', genre: 'fantasy', src: 'homebrew')
      ],
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
      userTables: [
        t('a', 'A', cat: 'Zed'),
        t('b', 'B', cat: 'Alpha'),
        t('c', 'C', cat: 'Zed')
      ],
    ));
    expect(groups.map((g) => g.$1).toList(), ['Alpha', 'Zed']);
    expect(groups.last.$2.map((e) => e.name).toList(), ['A', 'C']);
  });
}
