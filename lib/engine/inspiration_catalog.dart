/// One inspiration catalog over three sources: the flavor generators, the
/// bundled read-only starter tables, and the user's My Tables. Both rolling
/// surfaces (Ask → Tables, GenerateSheet) render this list, so a table or
/// generator added in one place appears in both. Pure — no Flutter.
library;

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
