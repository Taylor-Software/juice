import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/models.dart';
import '../shared/ai_badge.dart';
import '../shared/undo_snackbar.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'flesh_out_review.dart';

/// Tracking → Rumors: a per-campaign list of leads/rumors to resolve.
class RumorsPane extends ConsumerWidget {
  const RumorsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rumors = ref.watch(rumorsProvider).valueOrNull ?? const <Rumor>[];
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Rumors', style: theme.textTheme.titleMedium),
              ),
              // Flexible bounds the button under the loose host width
              // constraints (freeze rule).
              Flexible(
                child: FilledButton.tonalIcon(
                  key: const Key('rumors-add'),
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                  onPressed: () => _add(context, ref),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: rumors.isEmpty
              ? const Center(child: Text('No rumors yet.'))
              : ListView(
                  children: [
                    for (final r in rumors)
                      CheckboxListTile(
                        key: Key('rumor-${r.id}'),
                        value: r.resolved,
                        onChanged: (_) => ref
                            .read(rumorsProvider.notifier)
                            .toggleResolved(r.id),
                        title: Text(
                          r.text,
                          style: r.resolved
                              ? TextStyle(
                                  decoration: TextDecoration.lineThrough,
                                  color: theme.colorScheme.onSurfaceVariant)
                              : null,
                        ),
                        subtitle: r.note.isEmpty ? null : Text(r.note),
                        secondary: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (ref.watch(aiReadyProvider))
                              IconButton(
                                key: Key('flesh-out-rumor-${r.id}'),
                                visualDensity: VisualDensity.compact,
                                icon: const AiBadge(),
                                tooltip: 'Flesh out (AI)',
                                onPressed: () => _fleshOut(context, ref, r),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Delete',
                              onPressed: () {
                                final list =
                                    ref.read(rumorsProvider).valueOrNull ??
                                        const <Rumor>[];
                                final idx =
                                    list.indexWhere((x) => x.id == r.id);
                                ref.read(rumorsProvider.notifier).remove(r.id);
                                showUndoSnackbar(
                                    context,
                                    'Rumor deleted',
                                    () => ref
                                        .read(rumorsProvider.notifier)
                                        .restoreAt(idx < 0 ? 0 : idx, r));
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  /// AI flesh-out: generate → Append/Cancel review → append to the rumor's
  /// note (same arc as the world trackers' flesh-outs).
  Future<void> _fleshOut(BuildContext context, WidgetRef ref, Rumor r) async {
    final seed = buildFleshOutSeed(ref,
        entityKind: 'rumor', name: r.text, existingDetail: r.note);
    final String detail;
    try {
      detail = await ref.read(interpreterServiceProvider).fleshOut(seed);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Flesh out failed: $e')));
      }
      return;
    }
    if (!context.mounted) return;
    if (!await showFleshOutReview(context, detail)) return;
    final note =
        [r.note, detail].where((s) => s.trim().isNotEmpty).join('\n\n');
    await ref.read(rumorsProvider.notifier).replace(r.copyWith(note: note));
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add rumor'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Rumor'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Add')),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    if (text == null || text.trim().isEmpty) return;
    await ref.read(rumorsProvider.notifier).add(text.trim());
  }
}
