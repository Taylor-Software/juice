import 'package:flutter/material.dart';

import '../engine/models.dart';

/// Renders a composite [GenResult] with an optional "Log" action.
class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.result, this.onLog});

  final GenResult result;
  final VoidCallback? onLog;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(result.title, style: theme.textTheme.titleMedium),
                ),
                if (onLog != null)
                  IconButton(
                    tooltip: 'Log this result',
                    icon: const Icon(Icons.bookmark_add_outlined),
                    onPressed: onLog,
                  ),
              ],
            ),
            if (result.summary != null) ...[
              const SizedBox(height: 4),
              Text(
                result.summary!,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            if (result.rolls.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...result.rolls.map((r) => RollRow(roll: r)),
            ],
          ],
        ),
      ),
    );
  }
}

class RollRow extends StatelessWidget {
  const RollRow({super.key, required this.roll});
  final Roll roll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              roll.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(roll.display, style: theme.textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}
