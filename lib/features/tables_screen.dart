import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/custom_table.dart';
import '../engine/dice.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/table_groups.dart';
import '../state/providers.dart';
import 'custom_table_editor.dart';

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
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = groupTableKeys(widget.oracle.data.allTableKeys);
    final q = _query.trim().toLowerCase();
    final customTables =
        ref.watch(customTablesProvider).valueOrNull ?? const <CustomTable>[];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('Tables', style: theme.textTheme.headlineSmall),
              ),
              // Flexible bounds the button: a bare SegmentedButton as a
              // non-flex Row child next to the Expanded above is measured at
              // maxWidth:Infinity and throws under the loose tool host.
              Flexible(
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: -1, label: Text('Dis')),
                    ButtonSegment(value: 0, label: Text('—')),
                    ButtonSegment(value: 1, label: Text('Adv')),
                  ],
                  selected: {_skew},
                  onSelectionChanged: (s) => setState(() => _skew = s.first),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            key: const Key('tables-search'),
            controller: _search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search tables…',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              // User-authored tables sit above the built-in groups. Hidden while
              // searching so they don't clutter built-in-table results.
              if (q.isEmpty) _myTablesSection(customTables),
              for (final group in groups)
                if (_matching(group, q) case final matches
                    when matches.isNotEmpty)
                  ExpansionTile(
                    // While searching, a non-storage key mounts the tile fresh
                    // so matches always show expanded regardless of a prior
                    // collapse; with no query, PageStorageKey remembers toggles.
                    key: q.isEmpty
                        ? PageStorageKey('tables-group-${group.label}')
                        : ValueKey('tables-group-search-${group.label}'),
                    initiallyExpanded: true,
                    title:
                        Text(group.label, style: theme.textTheme.titleMedium),
                    childrenPadding: const EdgeInsets.only(bottom: 4),
                    children: [for (final key in matches) _tableTile(key)],
                  ),
            ],
          ),
        ),
      ],
    );
  }

  /// Roll [t] and log the result to the journal as a `custom-table` entry.
  void _rollCustomTable(CustomTable t) {
    final r = rollCustomTable(t, Dice());
    ref.read(journalProvider.notifier).addResult(r.title, r.asText,
        sourceTool: 'custom-table', payload: r.toPayload());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Added to journal')),
    );
  }

  /// The "My Tables" section: a roll/edit row per user-authored table plus a
  /// "New table" affordance. Shown only when not searching.
  Widget _myTablesSection(List<CustomTable> tables) {
    final theme = Theme.of(context);
    return ExpansionTile(
      key: const Key('tables-my-tables'),
      initiallyExpanded: true,
      title: Text('My Tables', style: theme.textTheme.titleMedium),
      childrenPadding: const EdgeInsets.only(bottom: 4),
      children: [
        for (final t in tables)
          Card(
            child: ListTile(
              key: Key('my-table-${t.id}'),
              title: Text(t.name.isEmpty ? '(untitled)' : t.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('my-table-edit-${t.id}'),
                    tooltip: 'Edit table',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => showCustomTableDialog(context, ref, t),
                  ),
                  IconButton(
                    tooltip: 'Roll',
                    icon: const Icon(Icons.casino_outlined),
                    onPressed: () => _rollCustomTable(t),
                  ),
                ],
              ),
              onTap: () => _rollCustomTable(t),
            ),
          ),
        Card(
          child: ListTile(
            key: const Key('tables-my-new'),
            leading: const Icon(Icons.add),
            title: const Text('New table'),
            onTap: () => showCustomTableDialog(context, ref, null),
          ),
        ),
      ],
    );
  }

  /// Keys in [group] whose display title matches the lowercased query [q]
  /// (all of them when [q] is empty).
  List<String> _matching(TableGroup group, String q) => q.isEmpty
      ? group.keys
      : group.keys
          .where((k) => _titleize(k).toLowerCase().contains(q))
          .toList();

  Widget _tableTile(String key) {
    final theme = Theme.of(context);
    final title = _titleize(key);
    final rolled = _last[key];
    return Card(
      child: ListTile(
        title: Text(title),
        subtitle: rolled == null
            ? null
            : Text('${rolled.value}  ·  ${rolled.detail}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.primary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (rolled != null)
              IconButton(
                tooltip: 'Add to journal',
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: () {
                  ref.read(journalProvider.notifier).add(title, rolled.value);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Added to journal')),
                  );
                },
              ),
            IconButton(
              tooltip: 'Roll',
              icon: const Icon(Icons.casino_outlined),
              onPressed: () => setState(() {
                _last[key] = widget.oracle.rollTable(key, title, skew: _skew);
              }),
            ),
          ],
        ),
        onTap: () => setState(() {
          _last[key] = widget.oracle.rollTable(key, title, skew: _skew);
        }),
      ),
    );
  }
}
