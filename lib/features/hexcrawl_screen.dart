import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/hexcrawl.dart';
import '../state/providers.dart';

/// Generic exploration-table generator (Hexcrawl toolkit H1): roll any
/// system-agnostic table and log the result to the journal. Plain scroll +
/// Wrap of buttons — no TabBarView / non-flex buttons (loose-constraint safe).
class HexcrawlScreen extends ConsumerStatefulWidget {
  const HexcrawlScreen({super.key});

  @override
  ConsumerState<HexcrawlScreen> createState() => _HexcrawlScreenState();
}

class _HexcrawlScreenState extends ConsumerState<HexcrawlScreen> {
  final _dice = Dice(Random());
  String _climate = 'temperate';
  String _resultTitle = '';
  String _resultBody = '';

  void _set(String title, String body) => setState(() {
        _resultTitle = title;
        _resultBody = body;
      });

  void _logToJournal() {
    if (_resultBody.isEmpty) return;
    ref.read(journalProvider.notifier).add(_resultTitle, _resultBody);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logged to journal')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(hexcrawlDataProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load hexcrawl data: $e')),
      data: (data) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Climate', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (final c in data.climates)
                ChoiceChip(
                  label: Text(c),
                  selected: _climate == c,
                  onSelected: (_) => setState(() => _climate = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Roll a table', style: Theme.of(context).textTheme.titleSmall),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonal(
                key: const Key('roll-terrain'),
                onPressed: () {
                  final t = rollTerrain(data, _climate, _dice);
                  if (t != null) {
                    _set('Terrain', '${t.name} — ${t.travelNote}');
                  }
                },
                child: const Text('Terrain'),
              ),
              FilledButton.tonal(
                key: const Key('roll-weather'),
                onPressed: () => _set('Weather', rollFrom(data.weather, _dice)),
                child: const Text('Weather'),
              ),
              FilledButton.tonal(
                key: const Key('roll-hazard'),
                onPressed: () => _set('Hazard', rollFrom(data.hazards, _dice)),
                child: const Text('Hazard'),
              ),
              FilledButton.tonal(
                key: const Key('roll-site'),
                onPressed: () => _set('Site', rollFrom(data.siteTypes, _dice)),
                child: const Text('Site'),
              ),
              FilledButton.tonal(
                key: const Key('roll-feature'),
                onPressed: () =>
                    _set('Feature', rollFrom(data.regionFeatures, _dice)),
                child: const Text('Feature'),
              ),
              FilledButton.tonal(
                key: const Key('roll-encounter'),
                onPressed: () => _set(
                    'Encounter', rollFrom(data.encounterCategories, _dice)),
                child: const Text('Encounter'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_resultBody.isNotEmpty)
            Card(
              key: const Key('hexcrawl-result'),
              child: ListTile(
                title: Text(_resultTitle),
                subtitle: Text(_resultBody),
                trailing: IconButton(
                  icon: const Icon(Icons.post_add_outlined),
                  tooltip: 'Log to journal',
                  onPressed: _logToJournal,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
