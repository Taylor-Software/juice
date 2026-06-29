import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/content_registry.dart';
import '../engine/models.dart';
import '../shared/help_nav.dart';
import '../state/interpreter.dart';
import '../state/providers.dart';

/// App-wide settings. P1 holds a single "AI assistant" section that owns the
/// on-device model download + the global enable toggle. AI affordances stay
/// hidden across the app until the model is downloaded AND enabled here.
Future<void> showBestiarySheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BestiaryManageSheet(),
    );

Future<void> showSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SettingsSheet(),
    );

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final supported = ref.watch(aiSupportedProvider);
    final enabled = ref.watch(aiEnabledProvider).valueOrNull ?? false;
    final status = ref.watch(interpreterStatusProvider).valueOrNull;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('AI assistant', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (!supported)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("On-device AI isn't available on this platform."),
              )
            else ...[
              SwitchListTile(
                key: const Key('settings-ai-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable AI assistant'),
                subtitle: const Text(
                    'Interpret rolls, voice lines, recaps — all on-device.'),
                value: enabled,
                onChanged: (v) =>
                    ref.read(aiEnabledProvider.notifier).setEnabled(v),
              ),
              if (enabled) _statusBlock(context, ref, status),
            ],
            const SizedBox(height: 16),
            Text('Third-party content', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            const Text(
              'All oracle, map and character-sheet content credits and licenses '
              'are listed in one place under Help.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('open-credits'),
              icon: const Icon(Icons.description_outlined),
              label: const Text('View credits & licenses'),
              onPressed: () {
                Navigator.of(context).pop();
                openHelp(context, ref, topic: 'credits');
              },
            ),
            const SizedBox(height: 16),
            Text('Bestiary', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            const Text(
              'Saved creatures are app-global and reusable across all campaigns.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('bestiary-manage-open'),
              icon: const Icon(Icons.pets_outlined),
              label: const Text('Manage bestiary'),
              onPressed: () => showBestiarySheet(context),
            ),
            const SizedBox(height: 16),
            Text('Content', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            ListTile(
              key: const Key('settings-sources'),
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Sources & licenses'),
              subtitle: const Text('Attribution for bundled game content'),
              contentPadding: EdgeInsets.zero,
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Sources & licenses'),
                  content: SingleChildScrollView(
                    child: Text(kContentAttributions.values.join('\n\n')),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBlock(
      BuildContext context, WidgetRef ref, InterpreterStatus? status) {
    final service = ref.read(interpreterServiceProvider);
    final phase = status?.phase ?? InterpreterPhase.loading;
    switch (phase) {
      case InterpreterPhase.needsDownload:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Runs on-device. Download the model (${service.downloadLabel}) '
                'over Wi-Fi. One time only.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('settings-ai-download'),
              icon: const Icon(Icons.download),
              label: const Text('Download model'),
              onPressed: service.warmUp,
            ),
          ],
        );
      case InterpreterPhase.installing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Downloading… ${status?.progress ?? 0}%'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (status?.progress ?? 0) / 100),
          ],
        );
      case InterpreterPhase.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Loading model…'),
          ]),
        );
      case InterpreterPhase.ready:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(Icons.check_circle, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Text('Ready'),
          ]),
        );
      case InterpreterPhase.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status?.message ?? 'Something went wrong.'),
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('settings-ai-retry'),
              onPressed: service.warmUp,
              child: const Text('Retry'),
            ),
          ],
        );
      case InterpreterPhase.unsupported:
        return const SizedBox.shrink();
    }
  }
}

class _BestiaryManageSheet extends ConsumerWidget {
  const _BestiaryManageSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creatures =
        ref.watch(bestiaryProvider).valueOrNull ?? const <Creature>[];
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Bestiary',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: Navigator.of(context).pop,
                ),
              ],
            ),
          ),
          const Divider(),
          if (creatures.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Text(
                'No saved creatures. Save one from the Encounter stat block dialog.',
                style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.55,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: creatures.length,
                itemBuilder: (_, i) {
                  final cr = creatures[i];
                  return ListTile(
                    title: Text(cr.name),
                    subtitle:
                        cr.maxHp > 0 ? Text('HP ${cr.maxHp}') : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          key: Key('bestiary-edit-${cr.id}'),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit',
                          onPressed: () => _editCreature(context, ref, cr),
                        ),
                        IconButton(
                          key: Key('bestiary-del-${cr.id}'),
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete',
                          onPressed: () => ref
                              .read(bestiaryProvider.notifier)
                              .remove(cr.id),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editCreature(
      BuildContext context, WidgetRef ref, Creature cr) async {
    final updated = await showDialog<Creature>(
      context: context,
      builder: (_) => _CreatureEditDialog(creature: cr),
    );
    if (updated != null) {
      await ref.read(bestiaryProvider.notifier).replace(updated);
    }
  }
}

class _CreatureEditDialog extends StatefulWidget {
  const _CreatureEditDialog({required this.creature});
  final Creature creature;

  @override
  State<_CreatureEditDialog> createState() => _CreatureEditDialogState();
}

class _CreatureEditDialogState extends State<_CreatureEditDialog> {
  late final TextEditingController _name;
  late int _maxHp;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.creature.name);
    _maxHp = widget.creature.maxHp;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit creature'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('bestiary-edit-name'),
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 16),
          Text('Max HP', style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              IconButton(
                key: const Key('bestiary-edit-hp-dec'),
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: _maxHp > 0
                    ? () => setState(() => _maxHp--)
                    : null,
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$_maxHp',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                key: const Key('bestiary-edit-hp-inc'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => setState(() => _maxHp++),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop(
              widget.creature.copyWith(name: name, maxHp: _maxHp),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
