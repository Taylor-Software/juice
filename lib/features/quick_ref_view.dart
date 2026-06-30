import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/quick_ref.dart';
import '../state/providers.dart';

/// Read-only render of a system's QuickRef card. Pass [card] explicitly, or
/// leave it null to read the active system's card from [systemQuickRefProvider].
class QuickRefView extends ConsumerWidget {
  const QuickRefView({super.key, this.card, this.useProvider = false});
  final QuickRefCard? card;
  final bool useProvider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = useProvider ? ref.watch(systemQuickRefProvider) : card;
    if (resolved == null) {
      return Center(
        key: const Key('quickref-empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No quick reference for this system yet.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final theme = Theme.of(context);
    return ListView(
      key: const Key('quickref-list'),
      padding: const EdgeInsets.all(12),
      children: [
        Text(resolved.title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        for (final s in resolved.sections) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 2),
            child: Text(s.title, style: theme.textTheme.titleSmall),
          ),
          for (final line in s.lines)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: theme.textTheme.bodyMedium),
                  Expanded(
                      child: Text(line, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Opens the active system's QuickRef in a modal bottom sheet.
Future<void> showQuickRef(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.85,
        child: QuickRefView(useProvider: true),
      ),
    );
