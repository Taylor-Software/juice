import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../shared/destination.dart';
import '../shared/entry_preview.dart';
import '../shared/shell_route.dart';
import '../state/play_context.dart';
import '../state/providers.dart';

String _placeKindLabel(PlaceKind k) => switch (k) {
      PlaceKind.settlement => 'Settlement',
      PlaceKind.dungeon => 'Dungeon',
      PlaceKind.wilderness => 'Wilderness',
      PlaceKind.landmark => 'Landmark',
      PlaceKind.other => 'Place',
    };

IconData _placeKindIcon(PlaceKind k) => switch (k) {
      PlaceKind.settlement => Icons.location_city_outlined,
      PlaceKind.dungeon => Icons.fort_outlined,
      PlaceKind.wilderness => Icons.forest_outlined,
      PlaceKind.landmark => Icons.flag_outlined,
      PlaceKind.other => Icons.place_outlined,
    };

/// Tracking → Places: a browseable list of named world locations (distinct from
/// the map's coordinate cells; a place may pin to one). Cards show kind + note,
/// an optional map link, and a "what happened here" journal backlink.
class PlacesPane extends ConsumerWidget {
  const PlacesPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(placesProvider).valueOrNull ?? const <Place>[];
    final theme = Theme.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Places', style: theme.textTheme.titleMedium),
              ),
              // Flexible bounds the buttons under the loose host width (freeze
              // rule): a bare button beside an Expanded is measured infinite.
              Flexible(
                child:
                    Wrap(spacing: 8, alignment: WrapAlignment.end, children: [
                  OutlinedButton.icon(
                    key: const Key('places-generate'),
                    icon: const Icon(Icons.casino_outlined, size: 18),
                    label: const Text('Generate'),
                    onPressed: () => _generate(context, ref),
                  ),
                  FilledButton.tonalIcon(
                    key: const Key('places-add'),
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
          child: places.isEmpty
              ? const Center(child: Text('No places yet.'))
              : ListView(
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final p in places) _PlaceCard(place: p),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _generate(BuildContext context, WidgetRef ref) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final r = oracle.settlement();
    // Seed the note from the settlement oracle; name is left for the user.
    await _edit(context, ref, null,
        seedNote: r.asText, seedKind: PlaceKind.settlement);
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Place? existing,
      {String seedNote = '', PlaceKind? seedKind}) async {
    final saved = await showDialog<Place>(
      context: context,
      builder: (_) => _PlaceDialog(
        existing: existing,
        seedNote: seedNote,
        seedKind: seedKind,
        activeLocation:
            ref.read(playContextProvider).valueOrNull?.activeLocation,
        oracle: ref.read(oracleProvider).valueOrNull,
      ),
    );
    if (saved == null || saved.name.trim().isEmpty) return;
    await ref.read(placesProvider.notifier).upsert(saved);
  }
}

/// One place card: kind badge, name, note, map link + journal backlink.
class _PlaceCard extends ConsumerWidget {
  const _PlaceCard({required this.place});
  final Place place;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final entries = ref.watch(journalProvider).valueOrNull ?? const [];
    final here = place.location == null
        ? const []
        : entriesAtLocation(entries, place.location!);
    // Place → People: NPCs the party met here.
    final people = (ref.watch(npcsProvider).valueOrNull ?? const <Npc>[])
        .where((n) => n.placeId == place.id)
        .toList();
    return Card(
      child: ListTile(
        key: Key('place-${place.id}'),
        leading: Icon(_placeKindIcon(place.kind)),
        title: Text(place.name.isEmpty ? '(unnamed place)' : place.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_placeKindLabel(place.kind),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            if (place.note.isNotEmpty)
              Text(place.note, maxLines: 2, overflow: TextOverflow.ellipsis),
            if (place.location != null || here.isNotEmpty || people.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(spacing: 8, children: [
                  if (people.isNotEmpty)
                    ActionChip(
                      key: Key('place-people-${place.id}'),
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.groups_outlined, size: 16),
                      label: Text(
                          '${people.length} ${people.length == 1 ? 'person' : 'people'}'),
                      onPressed: () => ref
                          .read(shellRouteProvider.notifier)
                          .goTo(Destination.track, subtab: 'people'),
                    ),
                  if (place.location != null)
                    ActionChip(
                      key: Key('place-map-${place.id}'),
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.map_outlined, size: 16),
                      label: const Text('On map'),
                      onPressed: () {
                        ref
                            .read(playContextProvider.notifier)
                            .setActiveLocation(place.location);
                        ref.read(shellRouteProvider.notifier).goTo(
                            Destination.map,
                            subtab: place.location!.roomId != null
                                ? 'dungeon'
                                : 'world');
                      },
                    ),
                  if (here.isNotEmpty)
                    ActionChip(
                      key: Key('place-entries-${place.id}'),
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.link, size: 16),
                      label: Text(
                          '${here.length} entr${here.length == 1 ? 'y' : 'ies'}'),
                      onPressed: () => _showEntries(context, ref, here.cast()),
                    ),
                ]),
              ),
          ],
        ),
        isThreeLine: place.note.isNotEmpty,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('place-edit-${place.id}'),
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editExisting(context, ref),
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  ref.read(placesProvider.notifier).remove(place.id),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editExisting(BuildContext context, WidgetRef ref) async {
    final saved = await showDialog<Place>(
      context: context,
      builder: (_) => _PlaceDialog(
        existing: place,
        activeLocation:
            ref.read(playContextProvider).valueOrNull?.activeLocation,
        oracle: ref.read(oracleProvider).valueOrNull,
      ),
    );
    if (saved != null) await ref.read(placesProvider.notifier).upsert(saved);
  }

  void _showEntries(
      BuildContext context, WidgetRef ref, List<JournalEntry> here) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final e in here)
              ListTile(
                key: Key('place-entry-row-${e.id}'),
                dense: true,
                title:
                    Text(e.title.isEmpty ? e.body.split('\n').first : e.title),
                subtitle:
                    Text(e.timestamp.toLocal().toString().split('.').first),
                onTap: () async {
                  final navigated =
                      await showEntryPreview(sheetContext, ref, e);
                  if (navigated && sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Add/edit dialog. Returns a [Place] (with the existing id, or a fresh id for
/// a new one) on save, null on cancel.
class _PlaceDialog extends StatefulWidget {
  const _PlaceDialog({
    this.existing,
    this.seedNote = '',
    this.seedKind,
    this.activeLocation,
    this.oracle,
  });
  final Place? existing;
  final String seedNote;
  final PlaceKind? seedKind;
  final LocationRef? activeLocation;

  /// When available, name/notes get a dice icon that rerolls the field.
  final Oracle? oracle;

  @override
  State<_PlaceDialog> createState() => _PlaceDialogState();
}

class _PlaceDialogState extends State<_PlaceDialog> {
  late final _nameCtl =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _noteCtl =
      TextEditingController(text: widget.existing?.note ?? widget.seedNote);
  late PlaceKind _kind =
      widget.existing?.kind ?? widget.seedKind ?? PlaceKind.other;
  late LocationRef? _location = widget.existing?.location;

  @override
  void dispose() {
    _nameCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  Widget? _rollIcon(String key, String tooltip, String Function(Oracle) roll,
      TextEditingController ctl) {
    final oracle = widget.oracle;
    if (oracle == null) return null;
    return IconButton(
      key: Key(key),
      icon: const Icon(Icons.casino_outlined),
      tooltip: tooltip,
      onPressed: () => ctl.text = roll(oracle),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPin = widget.activeLocation != null && _location == null;
    return AlertDialog(
      title: Text(widget.existing == null ? 'New place' : 'Edit place'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              key: const Key('place-name'),
              controller: _nameCtl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name',
                suffixIcon: _rollIcon(
                    'place-name-roll',
                    'Roll a name',
                    (o) => o.settlement().rolls.first.value,
                    _nameCtl),
              )),
          const SizedBox(height: 8),
          DropdownButtonFormField<PlaceKind>(
            key: const Key('place-kind'),
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Kind'),
            items: [
              for (final k in PlaceKind.values)
                DropdownMenuItem(value: k, child: Text(_placeKindLabel(k))),
            ],
            onChanged: (v) => setState(() => _kind = v ?? PlaceKind.other),
          ),
          const SizedBox(height: 8),
          TextField(
              key: const Key('place-note'),
              controller: _noteCtl,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Notes',
                suffixIcon: _rollIcon('place-note-roll', 'Reroll details',
                    (o) => o.settlement().asText, _noteCtl),
              )),
          const SizedBox(height: 8),
          if (_location != null)
            Row(children: [
              const Icon(Icons.map_outlined, size: 18),
              const SizedBox(width: 8),
              const Expanded(child: Text('Pinned to a map location')),
              TextButton(
                key: const Key('place-unpin'),
                onPressed: () => setState(() => _location = null),
                child: const Text('Unpin'),
              ),
            ])
          else if (canPin)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('place-pin'),
                icon: const Icon(Icons.push_pin_outlined, size: 18),
                label: const Text('Pin to current map location'),
                onPressed: () =>
                    setState(() => _location = widget.activeLocation),
              ),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
          key: const Key('place-save'),
          onPressed: () {
            final base = widget.existing ??
                Place(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    name: '');
            Navigator.of(context).pop(base.copyWith(
              name: _nameCtl.text.trim(),
              kind: _kind,
              note: _noteCtl.text.trim(),
              location: _location,
              clearLocation: _location == null,
            ));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
