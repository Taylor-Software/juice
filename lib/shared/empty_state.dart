import 'package:flutter/material.dart';
import 'design_tokens.dart';

/// Directive empty state: one emotive line, a short body, a prominent primary
/// action, and an optional secondary. Reused across empty roster/journal/etc.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.icon,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final IconData? icon;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 40, color: tk.inkFaint),
              const SizedBox(height: 14),
            ],
            Text(title,
                textAlign: TextAlign.center,
                style: tt.titleLarge?.copyWith(
                    fontFamily: 'Newsreader',
                    fontStyle: FontStyle.italic,
                    color: tk.ink)),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: tt.bodyMedium?.copyWith(
                    fontFamily: 'HankenGrotesk', color: tk.inkMuted)),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('empty-state-primary'),
              onPressed: onPrimary,
              child: Text(primaryLabel),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(
                key: const Key('empty-state-secondary'),
                onPressed: onSecondary,
                child: Text(secondaryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
