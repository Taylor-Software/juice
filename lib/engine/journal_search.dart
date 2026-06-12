/// Pure journal retrieval: free-text search, tag enumeration, and the
/// interpreter's recall ranking. No Flutter.
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

/// Words too common to signal relatedness. Tiny and boring on purpose.
const Set<String> _stopwords = {
  'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'at', 'is', 'was',
  'are', 'it', 'its', 'with', 'for', 'as', 'but', 'by', 'from', 'this',
  'that', 'you', 'your',
};

/// Lowercase alphanumeric words of length >= 3, minus [_stopwords].
Set<String> _terms(String text) => RegExp(r'[a-z0-9]+')
    .allMatches(text.toLowerCase())
    .map((m) => m[0]!)
    .where((w) => w.length >= 3 && !_stopwords.contains(w))
    .toSet();

/// The [limit] entries most relevant to [target], for interpreter recall.
/// Deterministic term-overlap ranking — no embeddings:
/// - Terms: lowercase alphanumeric words of length >= 3 from the target's
///   title + body + tags, minus stopwords (small built-in english list).
/// - Score: +1 per distinct shared term in an entry's title/body,
///   +3 per shared tag (tags are curated signal).
/// - Excludes [target] itself (by id) and scene entries (they're headers,
///   not content). Score 0 entries are dropped.
/// - Ties break toward the more recent timestamp.
List<JournalEntry> relatedEntries(
  List<JournalEntry> entries,
  JournalEntry target, {
  int limit = 2,
}) {
  final targetTerms =
      _terms('${target.title}\n${target.body}\n${target.tags.join('\n')}');
  final targetTags = target.tags.map((t) => t.toLowerCase()).toSet();
  final scored = <(JournalEntry, int)>[];
  for (final e in entries) {
    if (e.id == target.id || e.kind == JournalKind.scene) continue;
    final sharedTerms =
        targetTerms.intersection(_terms('${e.title}\n${e.body}')).length;
    final sharedTags =
        e.tags.map((t) => t.toLowerCase()).toSet().intersection(targetTags);
    final score = sharedTerms + 3 * sharedTags.length;
    if (score > 0) scored.add((e, score));
  }
  scored.sort((a, b) {
    final byScore = b.$2.compareTo(a.$2);
    if (byScore != 0) return byScore;
    return b.$1.timestamp.compareTo(a.$1.timestamp);
  });
  return [for (final (e, _) in scored.take(limit)) e];
}
