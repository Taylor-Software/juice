/// Pure campaign-wide search across all entity types.
/// No Flutter imports — unit-tested without a widget harness.
library;

import 'models.dart';

/// Destination verb for a search result. Mirrors [Destination] in models.dart
/// but kept here so the pure engine has no dependency on the UI layer.
enum SearchDestination { journal, track, sheet }

/// Which entity type produced a hit.
enum SearchResultKind { journalEntry, thread, rumor, track, character }

/// A single search hit with the display text, a snippet, and where to navigate.
class CampaignSearchResult {
  const CampaignSearchResult({
    required this.kind,
    required this.id,
    required this.title,
    required this.snippet,
    required this.destination,
    this.subtab = '',
  });

  final SearchResultKind kind;
  final String id;

  /// Primary display label (entry title, thread title, rumor text, etc.).
  final String title;

  /// Short supporting text shown under the title (body excerpt, note).
  final String snippet;

  /// Which shell verb to navigate to on tap.
  final SearchDestination destination;

  /// Subtab key within [destination] (empty = default tab).
  final String subtab;
}

/// Case-insensitive, multi-term AND search over all provided entity lists.
/// Blank [query] returns every entity. Order: journal entries first, then
/// threads, rumors, tracks, characters — preserves input order within each kind.
List<CampaignSearchResult> searchCampaign(
  String query, {
  List<JournalEntry> entries = const [],
  List<Thread> threads = const [],
  List<Rumor> rumors = const [],
  List<Track> tracks = const [],
  List<Character> characters = const [],
}) {
  final terms = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((t) => t.startsWith('#') ? t.substring(1) : t)
      .where((t) => t.isNotEmpty)
      .toList();

  bool matches(String haystack) =>
      terms.isEmpty || terms.every(haystack.toLowerCase().contains);

  final results = <CampaignSearchResult>[];

  for (final e in entries) {
    final hay = '${e.title}\n${e.body}\n${e.tags.join('\n')}';
    if (matches(hay)) {
      results.add(CampaignSearchResult(
        kind: SearchResultKind.journalEntry,
        id: e.id,
        title: e.title.isEmpty ? '(untitled)' : e.title,
        snippet: e.body.length > 80 ? '${e.body.substring(0, 80)}…' : e.body,
        destination: SearchDestination.journal,
      ));
    }
  }

  for (final t in threads) {
    if (matches('${t.title}\n${t.note}')) {
      results.add(CampaignSearchResult(
        kind: SearchResultKind.thread,
        id: t.id,
        title: t.title,
        snippet: t.note.length > 80 ? '${t.note.substring(0, 80)}…' : t.note,
        destination: SearchDestination.track,
        subtab: 'threads',
      ));
    }
  }

  for (final r in rumors) {
    if (matches('${r.text}\n${r.note}')) {
      results.add(CampaignSearchResult(
        kind: SearchResultKind.rumor,
        id: r.id,
        title: r.text.length > 60 ? '${r.text.substring(0, 60)}…' : r.text,
        snippet: r.note,
        destination: SearchDestination.track,
        subtab: 'rumors',
      ));
    }
  }

  for (final t in tracks) {
    if (matches('${t.name}\n${t.note}')) {
      results.add(CampaignSearchResult(
        kind: SearchResultKind.track,
        id: t.id,
        title: t.name,
        snippet: t.note.length > 80 ? '${t.note.substring(0, 80)}…' : t.note,
        destination: SearchDestination.track,
        subtab: 'tracks',
      ));
    }
  }

  for (final c in characters) {
    if (matches('${c.name}\n${c.note}')) {
      results.add(CampaignSearchResult(
        kind: SearchResultKind.character,
        id: c.id,
        title: c.name,
        snippet: c.note.length > 80 ? '${c.note.substring(0, 80)}…' : c.note,
        destination: SearchDestination.sheet,
        subtab: 'characters',
      ));
    }
  }

  return results;
}
