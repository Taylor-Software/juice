/// Pure journal retrieval: free-text search and tag enumeration.
/// No Flutter — item D's interpreter retrieval reuses [searchEntries].
library;

import 'models.dart';

/// Case-insensitive multi-term search. Every whitespace-separated term in
/// [query] must match somewhere in the entry (title, body, or a tag) —
/// AND semantics. Blank query returns [entries] unchanged. Preserves
/// input order. A leading '#' on a term is stripped (the UI displays tags
/// as '#tag', so typed-back queries must still match the raw tag).
List<JournalEntry> searchEntries(List<JournalEntry> entries, String query) {
  final terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((t) => t.startsWith('#') ? t.substring(1) : t)
      .where((t) => t.isNotEmpty)
      .toList();
  if (terms.isEmpty) return entries;
  return entries.where((e) {
    final haystack =
        '${e.title}\n${e.body}\n${e.tags.join('\n')}'.toLowerCase();
    return terms.every(haystack.contains);
  }).toList();
}

/// Distinct tags across [entries], first-seen order.
List<String> allTags(List<JournalEntry> entries) {
  final seen = <String>{};
  return [
    for (final e in entries)
      for (final tag in e.tags)
        if (seen.add(tag)) tag,
  ];
}
