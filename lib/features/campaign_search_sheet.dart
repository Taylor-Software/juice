import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/campaign_search.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/providers.dart';

/// Opens the campaign-wide search sheet as a modal bottom sheet.
Future<void> showCampaignSearchSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CampaignSearchSheet(),
    );

/// Modal search sheet that queries journal entries, threads, rumors, tracks,
/// and characters in one pass. Results group by entity type; tapping navigates
/// via [shellRouteProvider].
class CampaignSearchSheet extends ConsumerStatefulWidget {
  const CampaignSearchSheet({super.key});

  @override
  ConsumerState<CampaignSearchSheet> createState() =>
      _CampaignSearchSheetState();
}

class _CampaignSearchSheetState extends ConsumerState<CampaignSearchSheet> {
  final _ctl = TextEditingController();
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _navigate(CampaignSearchResult result) {
    Navigator.of(context).pop();
    final dest = switch (result.destination) {
      SearchDestination.journal => Destination.journal,
      SearchDestination.track => Destination.track,
      SearchDestination.sheet => Destination.sheet,
    };
    ref.read(shellRouteProvider.notifier).goTo(dest, subtab: result.subtab);
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(journalProvider).valueOrNull ?? const [];
    final threads = ref.watch(threadsProvider).valueOrNull ?? const [];
    final rumors = ref.watch(rumorsProvider).valueOrNull ?? const [];
    final tracks = ref.watch(tracksProvider).valueOrNull ?? const [];
    final characters = ref.watch(charactersProvider).valueOrNull ?? const [];

    final results = searchCampaign(
      _query,
      entries: entries,
      threads: threads,
      rumors: rumors,
      tracks: tracks,
      characters: characters,
    );

    final theme = Theme.of(context);
    final grouped = <SearchResultKind, List<CampaignSearchResult>>{};
    for (final r in results) {
      grouped.putIfAbsent(r.kind, () => []).add(r);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtl) => SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const Key('campaign-search-field'),
              controller: _ctl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search journal, threads, characters…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _ctl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                // Debounced: searchCampaign re-scans all five entity lists
                // in build(), so don't rebuild on every keystroke.
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 250), () {
                  if (mounted) setState(() => _query = v);
                });
              },
            ),
          ),
          if (_query.isNotEmpty && results.isEmpty)
            Expanded(
              child: Center(
                child: Text('No results for "$_query"',
                    style: theme.textTheme.bodyMedium),
              ),
            )
          else
            Expanded(
              child: ListView(
                key: const Key('campaign-search-results'),
                controller: scrollCtl,
                children: [
                  for (final kind in SearchResultKind.values)
                    if (grouped[kind] != null) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Text(_kindLabel(kind),
                            style: theme.textTheme.labelMedium),
                      ),
                      for (final r in grouped[kind]!)
                        ListTile(
                          key: Key('search-result-${r.kind.name}-${r.id}'),
                          dense: true,
                          title: Text(r.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: r.snippet.isNotEmpty
                              ? Text(r.snippet,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall)
                              : null,
                          leading: Icon(_kindIcon(kind), size: 18),
                          onTap: () => _navigate(r),
                        ),
                    ],
                ],
              ),
            ),
        ]),
      ),
    );
  }
}

String _kindLabel(SearchResultKind kind) => switch (kind) {
      SearchResultKind.journalEntry => 'Journal',
      SearchResultKind.thread => 'Threads',
      SearchResultKind.rumor => 'Rumors',
      SearchResultKind.track => 'Progress Tracks',
      SearchResultKind.character => 'Characters',
    };

IconData _kindIcon(SearchResultKind kind) => switch (kind) {
      SearchResultKind.journalEntry => Icons.book_outlined,
      SearchResultKind.thread => Icons.label_outline,
      SearchResultKind.rumor => Icons.chat_bubble_outline,
      SearchResultKind.track => Icons.track_changes,
      SearchResultKind.character => Icons.person_outline,
    };
