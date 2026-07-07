import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';

String _dispositionLabel(NpcDisposition d) => switch (d) {
      NpcDisposition.friendly => 'Friendly',
      NpcDisposition.neutral => 'Neutral',
      NpcDisposition.hostile => 'Hostile',
      NpcDisposition.unknown => 'Unknown',
    };

Color _dispositionColor(NpcDisposition d, ColorScheme s) => switch (d) {
      NpcDisposition.friendly => Colors.green,
      NpcDisposition.neutral => s.onSurfaceVariant,
      NpcDisposition.hostile => s.error,
      NpcDisposition.unknown => Colors.orange,
    };

/// Tracking → People: world NPCs the party has met (distinct from the roster's
/// PCs + hirelings). Cards show role, disposition, note, and a linked place; a
/// met NPC can be promoted into a companion Character when it joins the party.
class PeoplePane extends ConsumerWidget {
  const PeoplePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final npcs = ref.watch(npcsProvider).valueOrNull ?? const <Npc>[];
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('People', style: theme.textTheme.titleMedium),
              ),
              Flexible(
                child:
                    Wrap(spacing: 8, alignment: WrapAlignment.end, children: [
                  OutlinedButton.icon(
                    key: const Key('people-generate'),
                    icon: const Icon(Icons.casino_outlined, size: 18),
                    label: const Text('Generate'),
                    onPressed: () => _generate(context, ref),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('people-add'),
                    icon: const Icon(Icons.add),
                    label: const Text('New'),
                    onPressed: () => _edit(context, ref, null),
                  ),
                ]),
              ),
            ],
          ),
        ),
        Expanded(
          child: npcs.isEmpty
              ? const Center(child: Text('No people met yet.'))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [for (final n in npcs) _NpcCard(npc: n)],
                ),
        ),
      ],
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final name = oracle.generateName().summary ?? '';
    await _edit(context, ref, null,
        seedName: name, seedNote: oracle.npc().asText);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Npc? existing,
      {String seedName = '', String seedNote = ''}) async {
    final places = ref.read(placesProvider).valueOrNull ?? const <Place>[];
    final saved = await showDialog<Npc>(
      context: context,
      builder: (_) => _NpcDialog(
          existing: existing,
          seedName: seedName,
          seedNote: seedNote,
          places: places),
    );
    if (saved == null || saved.name.trim().isEmpty) return;
    await ref.read(npcsProvider.notifier).upsert(saved);
  }
}

class _NpcCard extends ConsumerWidget {
  const _NpcCard({required this.npc});
  final Npc npc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final places = ref.watch(placesProvider).valueOrNull ?? const <Place>[];
    final place = npc.placeId == null
        ? null
        : places.where((p) => p.id == npc.placeId).firstOrNull;
    final subtitleParts = [
      if (npc.role.isNotEmpty) npc.role,
      _dispositionLabel(npc.disposition),
    ];
    return Card(
      child: ListTile(
        key: Key('npc-${npc.id}'),
        leading: Icon(Icons.person_outline,
            color: _dispositionColor(npc.disposition, theme.colorScheme)),
        title: Text(npc.name.isEmpty ? '(unnamed NPC)' : npc.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitleParts.join(' · '),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (npc.note.isNotEmpty)
              Text(npc.note, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (place != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.place_outlined, size: 14),
                  const SizedBox(width: 2),
                  Text(place.name.isEmpty ? '(place)' : place.name,
                      style: theme.textTheme.labelSmall),
                ]),
              ),
          ],
        ),
        isThreeLine: npc.note.isNotEmpty,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('npc-party-${npc.id}'),
              tooltip: 'Add to party as companion',
              icon: const Icon(Icons.group_add_outlined),
              onPressed: () async {
                await ref
                    .read(charactersProvider.notifier)
                    .addCompanion(npc.name, note: npc.note);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${npc.name} joined the party')));
                }
              },
            ),
            IconButton(
              key: Key('npc-edit-${npc.id}'),
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editExisting(context, ref),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => ref.read(npcsProvider.notifier).remove(npc.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editExisting(BuildContext context, WidgetRef ref) async {
    final places = ref.read(placesProvider).valueOrNull ?? const <Place>[];
    final saved = await showDialog<Npc>(
      context: context,
      builder: (_) => _NpcDialog(existing: npc, places: places),
    );
    if (saved != null) await ref.read(npcsProvider.notifier).upsert(saved);
  }
}

class _NpcDialog extends StatefulWidget {
  const _NpcDialog({
    this.existing,
    this.seedName = '',
    this.seedNote = '',
    required this.places,
  });
  final Npc? existing;
  final String seedName;
  final String seedNote;
  final List<Place> places;

  @override
  State<_NpcDialog> createState() => _NpcDialogState();
}

class _NpcDialogState extends State<_NpcDialog> {
  late final _nameCtl =
      TextEditingController(text: widget.existing?.name ?? widget.seedName);
  late final _roleCtl =
      TextEditingController(text: widget.existing?.role ?? '');
  late final _noteCtl =
      TextEditingController(text: widget.existing?.note ?? widget.seedNote);
  late NpcDisposition _disposition =
      widget.existing?.disposition ?? NpcDisposition.neutral;
  late String? _placeId = widget.existing?.placeId;

  @override
  void dispose() {
    _nameCtl.dispose();
    _roleCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Guard against a stale placeId (linked place deleted).
    final placeIds = widget.places.map((p) => p.id).toSet();
    final placeValue = placeIds.contains(_placeId) ? _placeId : null;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New person' : 'Edit person'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              key: const Key('npc-name'),
              controller: _nameCtl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name')),
          const SizedBox(height: 8),
          TextField(
              key: const Key('npc-role'),
              controller: _roleCtl,
              decoration: const InputDecoration(
                  labelText: 'Role', hintText: 'Innkeeper, caravan master…')),
          const SizedBox(height: 8),
          DropdownButtonFormField<NpcDisposition>(
            key: const Key('npc-disposition'),
            initialValue: _disposition,
            decoration: const InputDecoration(labelText: 'Disposition'),
            items: [
              for (final d in NpcDisposition.values)
                DropdownMenuItem(value: d, child: Text(_dispositionLabel(d))),
            ],
            onChanged: (v) =>
                setState(() => _disposition = v ?? NpcDisposition.neutral),
          ),
          const SizedBox(height: 8),
          if (widget.places.isNotEmpty)
            DropdownButtonFormField<String?>(
              key: const Key('npc-place'),
              initialValue: placeValue,
              decoration: const InputDecoration(labelText: 'Met at (place)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('(none)')),
                for (final p in widget.places)
                  DropdownMenuItem(
                      value: p.id,
                      child: Text(p.name.isEmpty ? '(unnamed)' : p.name)),
              ],
              onChanged: (v) => setState(() => _placeId = v),
            ),
          const SizedBox(height: 8),
          TextField(
              key: const Key('npc-note'),
              controller: _noteCtl,
              minLines: 2,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Notes')),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          key: const Key('npc-save'),
          onPressed: () {
            final base = widget.existing ??
                Npc(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: '');
            Navigator.of(context).pop(base.copyWith(
              name: _nameCtl.text.trim(),
              role: _roleCtl.text.trim(),
              disposition: _disposition,
              note: _noteCtl.text.trim(),
              placeId: _placeId,
              clearPlace: _placeId == null,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
