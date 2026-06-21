import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'dnd_sheet.dart';
import 'ironsworn_sheet.dart';
import 'shadowdark_sheet.dart';
import 'starforged_sheet.dart';

// -- Threads --------------------------------------------------------------
class ThreadsPane extends ConsumerWidget {
  const ThreadsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(threadsProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (threads) {
          if (threads.isEmpty) {
            return const _Empty(
                'No threads yet. Track quests, vows, mysteries.');
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: threads.length,
            itemBuilder: (context, i) {
              final t = threads[i];
              return Card(
                child: ListTile(
                  leading: Checkbox(
                    value: !t.open,
                    onChanged: (_) =>
                        ref.read(threadsProvider.notifier).toggleOpen(t.id),
                  ),
                  title: Text(
                    t.title,
                    style: t.open
                        ? null
                        : TextStyle(
                            decoration: TextDecoration.lineThrough,
                            color: theme.colorScheme.onSurfaceVariant),
                  ),
                  subtitle: t.note.isEmpty ? null : Text(t.note),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: Key('pin-thread-${t.id}'),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(t.pinned
                            ? Icons.push_pin
                            : Icons.push_pin_outlined),
                        tooltip: t.pinned ? 'Unpin' : 'Pin',
                        onPressed: () => ref
                            .read(threadsProvider.notifier)
                            .togglePinned(t.id),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            ref.read(threadsProvider.notifier).remove(t.id),
                      ),
                    ],
                  ),
                  onTap: () => _editThread(context, ref, t),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editThread(context, ref, null),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _editThread(
      BuildContext context, WidgetRef ref, Thread? existing) async {
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: existing == null ? 'New Thread' : 'Edit Thread',
        labelA: 'Title',
        labelB: 'Note (optional)',
        initialA: existing?.title ?? '',
        initialB: existing?.note ?? '',
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    final notifier = ref.read(threadsProvider.notifier);
    if (existing == null) {
      await notifier.add(result.title.trim());
      // apply note if provided
      if (result.note.trim().isNotEmpty) {
        final added = ref.read(threadsProvider).valueOrNull?.first;
        if (added != null) {
          await notifier.replace(added.copyWith(note: result.note.trim()));
        }
      }
    } else {
      await notifier.replace(existing.copyWith(
          title: result.title.trim(), note: result.note.trim()));
    }
  }
}

// -- Characters -----------------------------------------------------------
class CharactersPane extends ConsumerStatefulWidget {
  const CharactersPane({super.key});

  @override
  ConsumerState<CharactersPane> createState() => CharactersPaneState();
}

class CharactersPaneState extends ConsumerState<CharactersPane> {
  /// Id of the character whose sheet is open, or null for the list view.
  String? _editingId;

  /// Guards the one-time initial focus from the persisted context.
  bool _initialFocusApplied = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(
      playContextProvider.select((v) => v.valueOrNull?.activeCharacterId),
      (prev, next) {
        if (next != null && next != _editingId && mounted) {
          setState(() => _editingId = next);
        }
      },
    );
    final async = ref.watch(charactersProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (chars) {
          if (!_initialFocusApplied) {
            _initialFocusApplied = true;
            final active =
                ref.read(playContextProvider).valueOrNull?.activeCharacterId;
            if (active != null && chars.any((c) => c.id == active)) {
              _editingId = active;
            }
          }
          if (_editingId != null) {
            // Resolve fresh each build; if the id vanished (e.g. session
            // switch), fall back to the list view.
            final match = chars.where((c) => c.id == _editingId);
            if (match.isEmpty) {
              _editingId = null;
            } else {
              final c = match.first;
              if (c.starforged != null) {
                return StarforgedSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.shadowdark != null) {
                return ShadowdarkSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.dnd != null) {
                return DndSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.ironsworn != null) {
                return IronswornSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              return _buildSheet(context, c);
            }
          }
          if (chars.isEmpty) {
            return const _Empty('No characters yet. Track NPCs and PCs.');
          }
          final active =
              ref.watch(playContextProvider).valueOrNull?.activeCharacterId;
          const groups = [
            ('Party', CharacterRole.pc),
            ('Companions', CharacterRole.companion),
            ('NPCs', CharacterRole.npc),
          ];
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final (label, role) in groups)
                if (chars.any((c) => c.role == role)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                    child: Row(children: [
                      Expanded(
                        child: Text(label,
                            style: Theme.of(context).textTheme.labelMedium),
                      ),
                      // One gesture to apply damage/heal/conditions across a
                      // group (e.g. a fireball hitting the party).
                      if (chars.where((c) => c.role == role).length > 1)
                        TextButton.icon(
                          key: Key('party-effect-${role.name}'),
                          style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                          icon: const Icon(Icons.bolt_outlined, size: 16),
                          label: const Text('Effect'),
                          onPressed: () => _partyEffect(context,
                              chars.where((c) => c.role == role).toList()),
                        ),
                    ]),
                  ),
                  for (final c in chars.where((c) => c.role == role))
                    _rosterCard(context, c, isLead: c.id == active),
                ],
            ],
          );
        },
      ),
      floatingActionButton: _editingId == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  key: const Key('generate-npc'),
                  heroTag: 'generate-npc-fab',
                  tooltip: 'Generate NPC',
                  onPressed: () => _generateNpc(context),
                  child: const Icon(Icons.person_add_alt_1),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  key: const Key('add-character'),
                  heroTag: 'add-character-fab',
                  onPressed: () => _onAdd(context),
                  child: const Icon(Icons.add),
                ),
              ],
            )
          : null,
    );
  }

  Future<void> _addCharacter(BuildContext context) async {
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => const _EditDialog(
        heading: 'New Character',
        labelA: 'Name',
        labelB: 'Note (optional)',
        initialA: '',
        initialB: '',
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    final notifier = ref.read(charactersProvider.notifier);
    await notifier.add(result.title.trim());
    final added = ref.read(charactersProvider).valueOrNull?.first;
    if (added == null) return;
    if (result.note.trim().isNotEmpty) {
      await notifier.replace(added.copyWith(note: result.note.trim()));
    }
    if (mounted) setState(() => _editingId = added.id);
  }

  Future<void> _generateNpc(BuildContext context) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final npc = oracle.npc();
    final name = oracle.generateName().summary ?? '';
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: 'New NPC',
        labelA: 'Name',
        labelB: 'Note',
        initialA: name,
        initialB: npc.asText,
        onRollName: () => oracle.generateName().summary ?? '',
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    final notifier = ref.read(charactersProvider.notifier);
    await notifier.add(result.title.trim());
    if (!mounted) return;
    final added = ref.read(charactersProvider).valueOrNull?.first;
    if (added != null) {
      final note = result.note.trim();
      await notifier.replace(added.copyWith(
        role: CharacterRole.npc,
        note: note.isEmpty ? null : note,
      ));
    }
    if (mounted) setState(() => _editingId = added?.id);
  }

  Future<void> _onAdd(BuildContext context) async {
    final systems =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
            kAllSystems;
    if (!systems.contains('ironsworn') &&
        !systems.contains('dnd') &&
        !systems.contains('shadowdark')) {
      await _addCharacter(context);
      return;
    }
    // Sheet types are listed as equal-weight, scrollable rows (not action-bar
    // buttons): action bars don't scroll, so with several systems enabled the
    // later options (D&D, Shadowdark) could overflow/clip in a small window.
    final options = <({String key, String value, String label, String blurb})>[
      (
        key: 'new-generic',
        value: 'generic',
        label: 'Generic',
        blurb: 'Freeform stats and tracks.'
      ),
      if (systems.contains('ironsworn')) ...[
        (
          key: 'new-ironsworn',
          value: 'ironsworn',
          label: 'Ironsworn',
          blurb: 'Classic Ironsworn character sheet.'
        ),
        (
          key: 'new-starforged',
          value: 'starforged',
          label: 'Starforged',
          blurb: 'Starforged character sheet.'
        ),
        (
          key: 'new-sundered',
          value: 'sundered',
          label: 'Sundered Isles',
          blurb: 'Sundered Isles character sheet.'
        ),
      ],
      if (systems.contains('dnd'))
        (
          key: 'new-dnd',
          value: 'dnd',
          label: 'D&D 5e',
          blurb: 'Ability scores, saves, skills, HP.'
        ),
      if (systems.contains('shadowdark'))
        (
          key: 'new-shadowdark',
          value: 'shadowdark',
          label: 'Shadowdark',
          blurb: 'Stats, HP, AC, gear, luck.'
        ),
    ];
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New character'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('Choose a sheet type.'),
                ),
                const SizedBox(height: 4),
                for (final o in options)
                  ListTile(
                    key: Key(o.key),
                    title: Text(o.label),
                    subtitle: Text(o.blurb),
                    onTap: () => Navigator.pop(context, o.value),
                  ),
                if (!systems.contains('dnd') || !systems.contains('shadowdark'))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Text(
                      'Enable D&D 5e or Shadowdark in Campaigns → Edit '
                      'systems to add those sheets.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('new-cancel'),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (!context.mounted) return;
    if (choice == 'generic') {
      await _addCharacter(context);
    } else if (choice == 'ironsworn') {
      await _newIronsworn();
    } else if (choice == 'starforged') {
      await _newStarforged();
    } else if (choice == 'sundered') {
      await _newSundered();
    } else if (choice == 'dnd') {
      await _newDnd();
    } else if (choice == 'shadowdark') {
      await _newShadowdark();
    }
  }

  Future<void> _newIronsworn() async {
    // Ensure a base Ironsworn ruleset is active so the asset picker has data.
    final rs = ref.read(rulesetsProvider).valueOrNull ?? const <String>{};
    if (!rs.contains('classic') && !rs.contains('starforged')) {
      await ref.read(rulesetsProvider.notifier).setRuleset('classic', true);
    }
    final id = await ref.read(charactersProvider.notifier).addIronsworn();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newStarforged() async {
    // Enable the Starforged ruleset for Moves-tool parity (asset picker reads
    // the bundled JSON regardless). This drops the classic toggle; existing
    // Classic sheets are unaffected (each sheet pins its own asset ruleset).
    final rs = ref.read(rulesetsProvider).valueOrNull ?? const <String>{};
    if (!rs.contains('starforged')) {
      await ref.read(rulesetsProvider.notifier).setRuleset('starforged', true);
    }
    final id = await ref.read(charactersProvider.notifier).addStarforged();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newDnd() async {
    final id = await ref.read(charactersProvider.notifier).addDnd();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newShadowdark() async {
    final id = await ref.read(charactersProvider.notifier).addShadowdark();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newSundered() async {
    // Enabling sundered_isles pulls in base starforged per the family rules.
    final rs = ref.read(rulesetsProvider).valueOrNull ?? const <String>{};
    if (!rs.contains('sundered_isles')) {
      await ref
          .read(rulesetsProvider.notifier)
          .setRuleset('sundered_isles', true);
    }
    final id = await ref
        .read(charactersProvider.notifier)
        .addStarforged(assetRuleset: 'sundered_isles');
    if (mounted) setState(() => _editingId = id);
  }

  Widget _rosterCard(BuildContext context, Character c, {bool isLead = false}) {
    final t = c.tracks.isEmpty ? null : c.tracks.first;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Row(
              children: [
                Expanded(child: Text(c.name)),
                if (isLead)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Chip(
                      label: const Text('lead'),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor:
                          Theme.of(context).colorScheme.primaryContainer,
                      labelStyle: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                          fontSize: 11),
                    ),
                  ),
              ],
            ),
            subtitle: t != null
                ? Text('${t.label} ${t.current}/${t.max}')
                : (c.note.isEmpty ? null : Text(c.note)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<CharacterRole>(
                  key: Key('role-${c.id}'),
                  initialValue: c.role,
                  tooltip: 'Role',
                  onSelected: (r) =>
                      ref.read(charactersProvider.notifier).setRole(c.id, r),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: CharacterRole.pc, child: Text('PC')),
                    PopupMenuItem(
                        value: CharacterRole.companion,
                        child: Text('Companion')),
                    PopupMenuItem(value: CharacterRole.npc, child: Text('NPC')),
                  ],
                ),
                IconButton(
                  key: Key('star-char-${c.id}'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(c.starred ? Icons.star : Icons.star_border),
                  tooltip: c.starred ? 'Unstar' : 'Star',
                  onPressed: () =>
                      ref.read(charactersProvider.notifier).toggleStarred(c.id),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      ref.read(charactersProvider.notifier).remove(c.id),
                ),
              ],
            ),
            onTap: () {
              ref.read(playContextProvider.notifier).setActiveCharacter(c.id);
              setState(() => _editingId = c.id);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final cond in c.conditions)
                  Chip(
                    label: Text(cond),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ActionChip(
                  key: Key('conditions-${c.id}'),
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text('condition'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _editConditions(context, c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _partyEffect(
      BuildContext context, List<Character> members) async {
    final selectedIds = {for (final m in members) m.id};
    final conds = <String>{};
    var hpDelta = 0;
    final apply = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Party effect'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Apply to'),
                for (final m in members)
                  CheckboxListTile(
                    key: Key('party-effect-target-${m.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: selectedIds.contains(m.id),
                    title: Text(m.name),
                    onChanged: (on) => setLocal(() => (on ?? false)
                        ? selectedIds.add(m.id)
                        : selectedIds.remove(m.id)),
                  ),
                const Divider(),
                Row(children: [
                  const Text('HP'),
                  IconButton(
                    key: const Key('party-effect-hp-minus'),
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setLocal(() => hpDelta -= 1),
                  ),
                  Text(hpDelta > 0 ? '+$hpDelta' : '$hpDelta'),
                  IconButton(
                    key: const Key('party-effect-hp-plus'),
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () => setLocal(() => hpDelta += 1),
                  ),
                  const Spacer(),
                  Text(hpDelta < 0
                      ? 'damage'
                      : hpDelta > 0
                          ? 'heal'
                          : ''),
                ]),
                const SizedBox(height: 8),
                const Text('Add conditions'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final cond in kConditions)
                      FilterChip(
                        label: Text(cond),
                        selected: conds.contains(cond),
                        onSelected: (on) => setLocal(
                            () => on ? conds.add(cond) : conds.remove(cond)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
              key: const Key('party-effect-apply'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (apply != true || selectedIds.isEmpty) return;
    if (hpDelta == 0 && conds.isEmpty) return;
    await ref.read(charactersProvider.notifier).applyPartyEffect(selectedIds,
        hpDelta: hpDelta, addConditions: conds.toList());
  }

  Future<void> _editConditions(BuildContext context, Character c) async {
    final selected = {...c.conditions};
    final customCtrl = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text('${c.name} — conditions'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final cond in {...kConditions, ...c.conditions})
                        FilterChip(
                          label: Text(cond),
                          selected: selected.contains(cond),
                          onSelected: (on) => setLocal(() =>
                              on ? selected.add(cond) : selected.remove(cond)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: customCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Add custom condition'),
                    onSubmitted: (v) {
                      final t = v.trim();
                      if (t.isNotEmpty) setLocal(() => selected.add(t));
                      customCtrl.clear();
                    },
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      );
    } finally {
      customCtrl.dispose();
    }
    await ref
        .read(charactersProvider.notifier)
        .setConditions(c.id, selected.toList());
  }

  Future<void> _editNameNote(BuildContext context, Character c) async {
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: 'Edit Character',
        labelA: 'Name',
        labelB: 'Note (optional)',
        initialA: c.name,
        initialB: c.note,
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    await ref.read(charactersProvider.notifier).replace(
        c.copyWith(name: result.title.trim(), note: result.note.trim()));
  }

  Future<void> _replace(Character updated) =>
      ref.read(charactersProvider.notifier).replace(updated);

  Widget _buildSheet(BuildContext context, Character c) {
    final theme = Theme.of(context);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Text(title, style: theme.textTheme.titleMedium),
        );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            IconButton(
              key: const Key('sheet-back'),
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                ref.read(playContextProvider.notifier).setActiveCharacter(null);
                setState(() => _editingId = null);
              },
            ),
            Expanded(
              child: Text(c.name,
                  style: theme.textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit name & notes',
              onPressed: () => _editNameNote(context, c),
            ),
          ],
        ),
        section('Stats'),
        for (var i = 0; i < c.stats.length; i++)
          Row(
            children: [
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                      text: c.stats[i].label,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: '  ${c.stats[i].value}'),
                ])),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    _replace(c.copyWith(stats: [...c.stats]..removeAt(i))),
              ),
            ],
          ),
        OutlinedButton.icon(
          key: const Key('add-stat'),
          icon: const Icon(Icons.add),
          label: const Text('Add stat'),
          onPressed: () => _addStat(context, c),
        ),
        section('Tracks'),
        for (var i = 0; i < c.tracks.length; i++)
          Row(
            children: [
              Expanded(child: Text(c.tracks[i].label)),
              IconButton(
                key: Key('track-minus-$i'),
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () => _replace(c.copyWith(
                    tracks: [...c.tracks]..[i] = c.tracks[i].adjusted(-1))),
              ),
              Text('${c.tracks[i].current}/${c.tracks[i].max}'),
              IconButton(
                key: Key('track-plus-$i'),
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () => _replace(c.copyWith(
                    tracks: [...c.tracks]..[i] = c.tracks[i].adjusted(1))),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    _replace(c.copyWith(tracks: [...c.tracks]..removeAt(i))),
              ),
            ],
          ),
        OutlinedButton.icon(
          key: const Key('add-track'),
          icon: const Icon(Icons.add),
          label: const Text('Add track'),
          onPressed: () => _addTrack(context, c),
        ),
        section('Tags'),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tag in c.tags)
              InputChip(
                label: Text(tag),
                onDeleted: () => _replace(
                    c.copyWith(tags: c.tags.where((t) => t != tag).toList())),
              ),
          ],
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          key: const Key('add-tag'),
          icon: const Icon(Icons.add),
          label: const Text('Add tag'),
          onPressed: () => _addTag(context, c),
        ),
        // Read-only summary; the Party Emulator tool owns the editing.
        if (c.emulation != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Emulation: ${c.emulation!.prominentTags.length} prominent '
              'traits · ${c.emulation!.tokens} tokens',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        section('Notes'),
        Text(c.note.isEmpty ? '—' : c.note),
      ],
    );
  }

  Future<void> _addStat(BuildContext context, Character c) async {
    final label = TextEditingController();
    final value = TextEditingController();
    final result = await showDialog<({String label, String value})>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add stat'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('stat-label'),
                controller: label,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('stat-value'),
                controller: value,
                decoration: const InputDecoration(labelText: 'Value'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                  context, (label: label.text, value: value.text)),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      label.dispose();
      value.dispose();
    });
    if (result == null || result.label.trim().isEmpty) return;
    await _replace(c.copyWith(stats: [
      ...c.stats,
      CharStat(label: result.label.trim(), value: result.value.trim()),
    ]));
  }

  Future<void> _addTrack(BuildContext context, Character c) async {
    final labelCtrl = TextEditingController();
    final maxCtrl = TextEditingController();
    final result = await showDialog<({String label, String max})>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add track'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                key: const Key('track-label'),
                controller: labelCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Label'),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('track-max'),
                controller: maxCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Max'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                  context, (label: labelCtrl.text, max: maxCtrl.text)),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      labelCtrl.dispose();
      maxCtrl.dispose();
    });
    if (result == null || result.label.trim().isEmpty) return;
    var max = int.tryParse(result.max.trim()) ?? 1;
    if (max < 1) max = 1;
    await _replace(c.copyWith(tracks: [
      ...c.tracks,
      CharTrack(label: result.label.trim(), current: max, max: max),
    ]));
  }

  Future<void> _addTag(BuildContext context, Character c) async {
    final tagCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add tag'),
          content: TextField(
            key: const Key('tag-input'),
            controller: tagCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tag'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, tagCtrl.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => tagCtrl.dispose());
    final tag = result?.trim() ?? '';
    if (tag.isEmpty || c.tags.contains(tag)) return;
    await _replace(c.copyWith(tags: [...c.tags, tag]));
  }
}

// -- Shared dialog + empty state -----------------------------------------
class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.heading,
    required this.labelA,
    required this.labelB,
    required this.initialA,
    required this.initialB,
    this.onRollName,
  });
  final String heading;
  final String labelA;
  final String labelB;
  final String initialA;
  final String initialB;

  /// If non-null, a dice icon is shown on the name field; tapping it calls
  /// this to generate a new name and fills the field.
  final String Function()? onRollName;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _a =
      TextEditingController(text: widget.initialA);
  late final TextEditingController _b =
      TextEditingController(text: widget.initialB);

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.heading),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _a,
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.labelA,
              suffixIcon: widget.onRollName == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.casino_outlined),
                      tooltip: 'Roll a name',
                      onPressed: () =>
                          setState(() => _a.text = widget.onRollName!()),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _b,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(labelText: widget.labelB),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (title: _a.text, note: _b.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
