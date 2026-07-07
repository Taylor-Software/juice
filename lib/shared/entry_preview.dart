import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import 'destination.dart';
import 'shell_route.dart';

/// Read-only preview of a journal entry, opened from the map/sketch backlink
/// sheets' "what happened here" rows. "Open journal" jumps to the Journal
/// verb (no scroll-to — the entry list is lazy with variable heights, and
/// precise scrolling would need a new dependency). Returns true when the
/// user chose Open journal, so the caller can pop its own sheet too.
Future<bool> showEntryPreview(
    BuildContext context, WidgetRef ref, JournalEntry e) async {
  final navigated = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        key: Key('entry-preview-${e.id}'),
        title: Text(e.title.isEmpty ? 'Journal entry' : e.title),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.timestamp.toLocal().toString().split('.').first,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Text(e.body.trim().isEmpty ? '(no text)' : e.body),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: Key('entry-preview-open-${e.id}'),
            onPressed: () {
              ref.read(shellRouteProvider.notifier).goTo(Destination.journal);
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Open journal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
  return navigated ?? false;
}
