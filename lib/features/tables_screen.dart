import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../state/providers.dart';

/// Turn a snake_case table key into a readable title.
String _titleize(String key) => key
    .split('_')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

class TablesScreen extends ConsumerStatefulWidget {
  const TablesScreen({super.key, required this.oracle});
  final Oracle oracle;

  @override
  ConsumerState<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends ConsumerState<TablesScreen> {
  int _skew = 0; // -1 disadvantage, 0 normal, +1 advantage
  final Map<String, Roll> _last = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keys = widget.oracle.data.allTableKeys;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Tables', style: theme.textTheme.headlineSmall),
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: -1, label: Text('Dis')),
                  ButtonSegment(value: 0, label: Text('—')),
                  ButtonSegment(value: 1, label: Text('Adv')),
                ],
                selected: {_skew},
                onSelectionChanged: (s) => setState(() => _skew = s.first),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: keys.length,
            itemBuilder: (context, i) {
              final key = keys[i];
              final title = _titleize(key);
              final rolled = _last[key];
              return Card(
                child: ListTile(
                  title: Text(title),
                  subtitle: rolled == null
                      ? null
                      : Text('${rolled.value}  ·  ${rolled.detail}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (rolled != null)
                        IconButton(
                          tooltip: 'Add to journal',
                          icon: const Icon(Icons.bookmark_add_outlined),
                          onPressed: () {
                            ref
                                .read(journalProvider.notifier)
                                .add(title, rolled.value);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Added to journal')),
                            );
                          },
                        ),
                      IconButton(
                        tooltip: 'Roll',
                        icon: const Icon(Icons.casino_outlined),
                        onPressed: () => setState(() {
                          _last[key] =
                              widget.oracle.rollTable(key, title, skew: _skew);
                        }),
                      ),
                    ],
                  ),
                  onTap: () => setState(() {
                    _last[key] =
                        widget.oracle.rollTable(key, title, skew: _skew);
                  }),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
