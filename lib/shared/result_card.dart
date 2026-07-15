import 'package:flutter/material.dart';

import '../engine/models.dart';

/// A contextual quick-action shown as a chip beneath a [ResultCard]'s rolls —
/// e.g. "Random Event", "Roll consequences", "Apply damage". Lets a roll be
/// acted on in place instead of navigating away to a tool.
class ResultAction {
  const ResultAction({
    required this.label,
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  final String label;
  final IconData icon;

  /// Null disables the chip.
  final VoidCallback? onPressed;
  final String? tooltip;
}

/// Renders a composite [GenResult] with an optional "Add to journal" action and
/// an optional row of contextual quick-[actions].
class ResultCard extends StatelessWidget {
  const ResultCard({
    super.key,
    required this.result,
    this.onLog,
    this.onInspire,
    this.actions,
  });

  final GenResult result;
  final VoidCallback? onLog;

  /// Read this result with the LLM and log the reading with it (see
  /// `inspire.dart`). Null hides the button — pass it only when interpret is
  /// ready (`interpretReadyProvider`).
  final VoidCallback? onInspire;

  /// Contextual quick-actions rendered as chips below the rolls. Empty/null
  /// hides the row.
  final List<ResultAction>? actions;

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
                if (onInspire != null)
                  IconButton(
                    key: const Key('result-inspire'),
                    tooltip: 'Inspire — read this result for my story',
                    icon: const Icon(Icons.auto_awesome_outlined),
                    onPressed: onInspire,
                  ),
                if (onLog != null)
                  IconButton(
                    tooltip: 'Add to journal',
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
              ...result.rolls.map((r) => _RollRow(roll: r)),
            ],
            if (actions != null && actions!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final a in actions!)
                    ActionChip(
                      key: Key('result-action-${a.label}'),
                      avatar: Icon(a.icon, size: 16),
                      label: Text(a.label),
                      tooltip: a.tooltip,
                      onPressed: a.onPressed,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RollRow extends StatelessWidget {
  const _RollRow({required this.roll});
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
