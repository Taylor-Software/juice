import 'package:flutter/material.dart';

import '../engine/models.dart';
import '../engine/tarot_meanings.dart';

/// Browsable reference for the 78 tarot cards, grouped into Major Arcana + the
/// four suits, with a name filter. Each row shows the authored upright and
/// reversed meaning (no AI). Mirrors the sections+search pattern in
/// tables_screen.dart.
class TarotReference extends StatefulWidget {
  const TarotReference({super.key});

  @override
  State<TarotReference> createState() => _TarotReferenceState();
}

class _TarotReferenceState extends State<TarotReference> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<({String label, List<String> cards})> get _groups => [
        (label: 'Major Arcana', cards: kTarotMajor),
        for (final suit in const ['Wands', 'Cups', 'Swords', 'Pentacles'])
          (
            label: suit,
            cards: [
              for (final c in kTarotDeck)
                if (c.endsWith(' of $suit')) c
            ],
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _q.trim().toLowerCase();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            key: const Key('tarot-ref-search'),
            controller: _search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search cards…',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _search.clear();
                        _q = '';
                      }),
                    ),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              for (final g in _groups)
                if (g.cards.where((c) => c.toLowerCase().contains(q)).toList()
                    case final cards when cards.isNotEmpty)
                  ExpansionTile(
                    key: q.isEmpty
                        ? PageStorageKey('tarot-ref-${g.label}')
                        : ValueKey('tarot-ref-search-${g.label}'),
                    initiallyExpanded: true,
                    title: Text(g.label, style: theme.textTheme.titleMedium),
                    children: [for (final c in cards) _row(theme, c)],
                  ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(ThemeData theme, String card) {
    final m = kTarotMeanings[card];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(card, style: theme.textTheme.titleSmall),
            if (m != null) ...[
              const SizedBox(height: 4),
              Text('Upright — ${m.upright}', style: theme.textTheme.bodySmall),
              Text('Reversed — ${m.reversed}',
                  style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
