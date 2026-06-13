/// Heuristic "track this?" suggestions over journal prose + result payloads.
/// Conservative by design (spec cycle4 §7 C3): never auto-creates; the UI
/// turns an accepted suggestion into a tracked entity.
library;

import 'mention_parser.dart';
import 'models.dart';

enum SuggestionKind { character, thread }

class EntitySuggestion {
  const EntitySuggestion(this.name, this.kind);
  final String name;
  final SuggestionKind kind;
}

/// Stable dedupe/dismiss key: 'character:mara' / 'thread:the vow'.
String suggestionKey(SuggestionKind kind, String name) =>
    '${kind == SuggestionKind.character ? 'character' : 'thread'}:'
    '${name.toLowerCase()}';

// Words that start sentences but aren't names. Small, high-frequency set.
const _stop = {
  'the',
  'a',
  'an',
  'we',
  'i',
  'he',
  'she',
  'they',
  'it',
  'you',
  'this',
  'that',
  'there',
  'then',
  'but',
  'and',
  'so',
  'as',
  'at',
  'in',
  'on',
  'of',
  'to',
  'my',
  'our',
  'his',
  'her',
  'their',
  'no',
  'yes',
  'if',
  'when',
  'after',
  'before',
  'meanwhile',
  'later',
  'now',
  'name',
  'role',
  'area',
};

final _word = RegExp(r'\b([A-Z][a-z]{2,})\b');

/// Suggestions worth offering, most-frequent first. [existingCharNames] and
/// [existingThreadTitles] are lowercased; [dismissed] holds suggestionKey()s.
List<EntitySuggestion> suggestEntities(
  List<JournalEntry> entries, {
  required Set<String> existingCharNames,
  required Set<String> existingThreadTitles,
  required Set<String> dismissed,
}) {
  final out = <EntitySuggestion>[];
  final seen = <String>{};

  void add(String name, SuggestionKind kind) {
    final key = suggestionKey(kind, name);
    final lower = name.toLowerCase();
    if (seen.contains(key) || dismissed.contains(key)) return;
    if (kind == SuggestionKind.character && existingCharNames.contains(lower)) {
      return;
    }
    if (kind == SuggestionKind.thread && existingThreadTitles.contains(lower)) {
      return;
    }
    seen.add(key);
    out.add(EntitySuggestion(name, kind));
  }

  // (a) NPC result payloads → character by summary name.
  for (final e in entries) {
    if (e.kind == JournalKind.result && e.sourceTool == 'gen-npcs') {
      final name = e.payload?['summary'] as String?;
      if (name != null && name.trim().isNotEmpty) {
        add(name.trim(), SuggestionKind.character);
      }
    }
  }

  // (b) Proper nouns recurring >= 2 times across prose (ignoring text already
  // inside mentions, and the small stop set).
  final counts = <String, int>{};
  final display = <String, String>{};
  for (final e in entries) {
    final plain = mentionsToPlain(e.body);
    for (final m in _word.allMatches(plain)) {
      final w = m.group(1)!;
      if (_stop.contains(w.toLowerCase())) continue;
      final lower = w.toLowerCase();
      counts[lower] = (counts[lower] ?? 0) + 1;
      display[lower] ??= w;
    }
  }
  final repeated = counts.entries.where((e) => e.value >= 2).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final e in repeated) {
    add(display[e.key]!, SuggestionKind.character);
  }
  return out;
}
