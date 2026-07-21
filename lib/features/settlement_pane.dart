import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../state/providers.dart';

/// Maps → Town: settlement (city/town/village) map sites. A settlement holds a
/// flat list of buildings and can be anchored to a world hex. P1 of the map
/// hierarchy epic — cross-nesting (building → dungeon) is deferred.
class SettlementPane extends ConsumerWidget {
  const SettlementPane({super.key, required this.oracle});
  final Oracle oracle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final map = ref.watch(mapProvider).valueOrNull ?? const MapState();
    final settlements = map.settlements;
    final active = map.activeSettlement;
    final notifier = ref.read(mapProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Settlements', style: theme.textTheme.titleMedium),
              ),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  key: const Key('settlement-generate'),
                  icon: const Icon(Icons.casino_outlined, size: 18),
                  label: const Text('Generate town'),
                  onPressed: () => notifier.generateSettlement(oracle),
                ),
                FilledButton.tonalIcon(
                  key: const Key('settlement-new'),
                  icon: const Icon(Icons.add),
                  label: const Text('New'),
                  onPressed: () => notifier.addSettlement(),
                ),
              ]),
            ],
          ),
        ),
        if (settlements.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButton<String>(
              key: const Key('settlement-switch'),
              isExpanded: true,
              value: active?.id,
              items: [
                for (final s in settlements)
                  DropdownMenuItem(
                      value: s.id,
                      child: Text(s.name.isEmpty ? '(unnamed)' : s.name)),
              ],
              onChanged: (v) {
                if (v != null) notifier.switchSettlement(v);
              },
            ),
          ),
        Expanded(
          child: active == null
              ? const Center(
                  child: Text('No settlements yet. Generate a town.'))
              : _SettlementBody(oracle: oracle, site: active, map: map),
        ),
      ],
    );
  }
}

class _SettlementBody extends ConsumerWidget {
  const _SettlementBody(
      {required this.oracle, required this.site, required this.map});
  final Oracle oracle;
  final SettlementSite site;
  final MapState map;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final n = ref.read(mapProvider.notifier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(site.name.isEmpty ? '(unnamed)' : site.name,
                  style: theme.textTheme.titleLarge),
            ),
            IconButton(
              key: const Key('settlement-rename'),
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Rename / kind',
              onPressed: () => _editSettlement(context, ref),
            ),
            IconButton(
              key: const Key('settlement-delete'),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete settlement',
              onPressed: () => n.removeSettlement(site.id),
            ),
          ],
        ),
        if (site.kind.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(site.kind, style: theme.textTheme.labelLarge),
          ),
        const SizedBox(height: 8),
        // Anchor status / actions.
        Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (site.hasAnchor)
                Chip(
                  key: const Key('settlement-anchored'),
                  avatar: const Icon(Icons.push_pin, size: 16),
                  label: Text('Hex ${site.anchorHexCol},${site.anchorHexRow}'),
                )
              else if (map.currentHexCol != null && map.currentHexRow != null)
                ActionChip(
                  key: const Key('settlement-anchor'),
                  avatar: const Icon(Icons.add_location_alt_outlined, size: 16),
                  label: Text(
                      'Anchor to hex ${map.currentHexCol},${map.currentHexRow}'),
                  onPressed: () => n.anchorSettlementHere(
                      oracle, map.currentHexCol!, map.currentHexRow!),
                ),
              if (site.hasAnchor)
                ActionChip(
                  key: const Key('settlement-unanchor'),
                  avatar: const Icon(Icons.link_off, size: 16),
                  label: const Text('Unlink'),
                  onPressed: () => n.unanchorSettlement(site.id),
                ),
            ]),
        if (site.note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(site.note),
        ],
        const Padding(
          padding: EdgeInsets.only(top: 16, bottom: 4),
          child:
              Text('Buildings', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        if (site.buildings.isEmpty)
          Text('No buildings yet.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        for (final b in site.buildings)
          Card(
            key: Key('building-${b.id}'),
            child: ListTile(
              title: Text(b.name.isEmpty ? '(unnamed building)' : b.name),
              subtitle: [b.type, b.note].where((s) => s.isNotEmpty).isEmpty
                  ? null
                  : Text(
                      [b.type, b.note].where((s) => s.isNotEmpty).join(' — ')),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('building-edit-${b.id}'),
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit',
                    onPressed: () => _editBuilding(context, ref, b),
                  ),
                  IconButton(
                    key: Key('building-del-${b.id}'),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: () => n.removeBuilding(site.id, b.id),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('settlement-add-building'),
          icon: const Icon(Icons.add),
          label: const Text('Add building'),
          onPressed: () async {
            final id = await n.addBuilding(site.id);
            if (context.mounted) {
              // Open the editor on the fresh building.
              await _editBuilding(context, ref, Building(id: id));
            }
          },
        ),
      ],
    );
  }

  Future<void> _editSettlement(BuildContext context, WidgetRef ref) async {
    final nameCtl = TextEditingController(text: site.name);
    final kindCtl = TextEditingController(text: site.kind);
    final noteCtl = TextEditingController(text: site.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Settlement'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                key: const Key('settlement-name-field'),
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('settlement-kind-field'),
                controller: kindCtl,
                decoration: const InputDecoration(
                    labelText: 'Kind', hintText: 'Village / Town / City')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('settlement-note-field'),
                controller: noteCtl,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Notes')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('settlement-save'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    final n = ref.read(mapProvider.notifier);
    if (ok == true) {
      await n.renameSettlement(site.id, nameCtl.text.trim());
      await n.setSettlementKind(site.id, kindCtl.text.trim());
      await n.setSettlementNote(site.id, noteCtl.text.trim());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameCtl.dispose();
      kindCtl.dispose();
      noteCtl.dispose();
    });
  }

  Future<void> _editBuilding(
      BuildContext context, WidgetRef ref, Building b) async {
    final nameCtl = TextEditingController(text: b.name);
    final typeCtl = TextEditingController(text: b.type);
    final noteCtl = TextEditingController(text: b.note);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Building'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                key: const Key('building-name-field'),
                controller: nameCtl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('building-type-field'),
                controller: typeCtl,
                decoration: const InputDecoration(
                    labelText: 'Type', hintText: 'Tavern, temple, shop…')),
            const SizedBox(height: 8),
            TextField(
                key: const Key('building-note-field'),
                controller: noteCtl,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Notes')),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              key: const Key('building-save'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(mapProvider.notifier).updateBuilding(
          site.id,
          Building(
              id: b.id,
              name: nameCtl.text.trim(),
              type: typeCtl.text.trim(),
              note: noteCtl.text.trim()));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      nameCtl.dispose();
      typeCtl.dispose();
      noteCtl.dispose();
    });
  }
}
