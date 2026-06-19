import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/oracle.dart';
import '../state/providers.dart';
import 'shell_route.dart';
import 'tool_registry.dart';
import 'dice_sheet.dart';
import 'help_nav.dart';

/// Opens the tool-search sheet. [tools] is the filtered registry for the
/// current session; [oracle] is required for the dice-sheet fallback.
Future<void> showToolSearchSheet(
  BuildContext context,
  List<ToolDef> tools, {
  Oracle? oracle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ToolSearchSheet(tools: tools, oracle: oracle),
  );
}

class _ToolSearchSheet extends ConsumerStatefulWidget {
  const _ToolSearchSheet({required this.tools, this.oracle});
  final List<ToolDef> tools;
  final Oracle? oracle;

  @override
  ConsumerState<_ToolSearchSheet> createState() => _ToolSearchSheetState();
}

class _ToolSearchSheetState extends ConsumerState<_ToolSearchSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(ToolDef t) {
    ref.read(toolMruProvider.notifier).record(t.id);
    if (t.id == 'dice') {
      Navigator.of(context).pop();
      final o = widget.oracle;
      if (o != null) showDiceSheet(context, o.dice);
      return;
    }
    if (t.id == 'help') {
      Navigator.of(context).pop();
      openHelp(context, ref);
      return;
    }
    ref
        .read(shellRouteProvider.notifier)
        .openTool(t.id, mode: ref.read(modeProvider));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    bool matches(ToolDef t) =>
        q.isEmpty ||
        t.label.toLowerCase().contains(q) ||
        t.group.toLowerCase().contains(q);

    final ids = widget.tools.map((t) => t.id).toSet();
    final recent = (ref.watch(toolMruProvider).valueOrNull ?? const [])
        .where(ids.contains)
        .toList();

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                key: const Key('tool-search'),
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search tools',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView(
                key: const Key('launcher-list'),
                children: [
                  if (q.isEmpty && recent.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        'Recent',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          for (final tool in [
                            for (final id in recent)
                              widget.tools.firstWhere((t) => t.id == id)
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                key: Key('mru-${tool.id}'),
                                avatar: Icon(tool.icon, size: 18),
                                label: Text(tool.label),
                                onPressed: () => _open(tool),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  for (final group in toolGroups)
                    if (widget.tools
                        .any((t) => t.group == group && matches(t))) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          group,
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                  color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                      for (final tool in widget.tools
                          .where((t) => t.group == group && matches(t)))
                        ListTile(
                          leading: Icon(tool.icon),
                          title: Text(tool.label),
                          trailing: tool.badge == null
                              ? null
                              : Text(
                                  tool.badge!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline),
                                ),
                          onTap: () => _open(tool),
                        ),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
