import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/mention_parser.dart';
import '../engine/models.dart';
import '../engine/tally.dart';
import '../shared/ai_badge.dart';
import '../shared/design_tokens.dart';
import '../shared/destination.dart';
import '../shared/empty_state.dart';
import '../shared/shell_route.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'dnd_sheet.dart';
import 'ironsworn_sheet.dart';
import 'argosa_sheet.dart';
import 'cairn_sheet.dart';
import 'knave_sheet.dart';
import '../engine/funnel.dart';
import 'dcc_sheet.dart';
import 'funnel_sheet.dart';
import 'kal_arath_sheet.dart';
import 'ose_sheet.dart';
import 'draw_steel_sheet.dart';
import 'custom_sheet.dart';
import '../engine/custom_templates.dart';
import 'nimble_sheet.dart';
import 'shadowdark_sheet.dart';
import 'sheet_widgets.dart';
import 'starforged_sheet.dart';

// -- Threads --------------------------------------------------------------
/// Shows a bottom sheet listing the journal entries linked to a thread.
Future<void> _showThreadEntries(
    BuildContext context, Thread t, List<JournalEntry> entries) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            title: Text('${t.title} — ${entries.length} journal entr${entries.length == 1 ? 'y' : 'ies'}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final e in entries)
            ListTile(
              dense: true,
              leading: const Icon(Icons.notes_outlined),
              title: Text(
                e.title.isEmpty ? mentionsToPlain(e.body) : e.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: e.title.isEmpty
                  ? null
                  : Text(mentionsToPlain(e.body),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    ),
  );
}

class ThreadsPane extends ConsumerWidget {
  const ThreadsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final journal =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
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
              final tk = context.juice;
              return Card(
                child: ListTile(
                  isThreeLine: true,
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
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (t.note.isNotEmpty) Text(t.note),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          IconButton(
                            key: Key('thread-prog-dec-${t.id}'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.remove, size: 18),
                            tooltip: 'Less progress',
                            onPressed: () => ref
                                .read(threadsProvider.notifier)
                                .setProgress(t.id, t.progress - 1),
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(3),
                              child: LinearProgressIndicator(
                                value: t.progressMax <= 0
                                    ? 0.0
                                    : (t.progress / t.progressMax)
                                        .clamp(0.0, 1.0),
                                minHeight: 5,
                                backgroundColor: tk.hairline,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    tk.terracotta),
                              ),
                            ),
                          ),
                          IconButton(
                            key: Key('thread-prog-inc-${t.id}'),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                            icon: const Icon(Icons.add, size: 18),
                            tooltip: 'More progress',
                            onPressed: () => ref
                                .read(threadsProvider.notifier)
                                .setProgress(t.id, t.progress + 1),
                          ),
                          const SizedBox(width: 4),
                          Text('${t.progress}/${t.progressMax}',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: tk.inkMuted)),
                        ],
                      ),
                      _ThreadTallyRow(t),
                      Builder(builder: (ctx) {
                        final linked = journal
                            .where((e) => e.threadId == t.id)
                            .toList();
                        if (linked.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: ActionChip(
                            key: Key('thread-entries-${t.id}'),
                            avatar: const Icon(Icons.link, size: 14),
                            label: Text(
                                '${linked.length} entr${linked.length == 1 ? 'y' : 'ies'}'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () =>
                                _showThreadEntries(ctx, t, linked),
                          ),
                        );
                      }),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (ref.watch(aiReadyProvider))
                        IconButton(
                          key: Key('flesh-out-thread-${t.id}'),
                          visualDensity: VisualDensity.compact,
                          icon: const AiBadge(),
                          tooltip: 'Flesh out (AI)',
                          onPressed: () => _fleshOutThread(context, ref, t),
                        ),
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

  Future<void> _fleshOutThread(
      BuildContext context, WidgetRef ref, Thread t) async {
    final seed = buildFleshOutSeed(ref,
        entityKind: 'story thread', name: t.title, existingDetail: t.note);
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
    final note =
        [t.note, detail].where((s) => s.trim().isNotEmpty).join('\n\n');
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: 'Flesh out — ${t.title}',
        labelA: 'Title',
        labelB: 'Note',
        initialA: t.title,
        initialB: note,
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    await ref.read(threadsProvider.notifier).replace(
        t.copyWith(title: result.title.trim(), note: result.note.trim()));
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

  @override
  Widget build(BuildContext context) {
    // The active PC surfaces as a rich lead card in the roster *list* (vitals +
    // quick actions read without opening the sheet); tapping any card opens the
    // full sheet. So setting the active character no longer auto-opens the
    // editor — `_editingId` is driven solely by an explicit card tap.
    final async = ref.watch(charactersProvider);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (chars) {
          if (_editingId != null) {
            // Resolve fresh each build; if the id vanished (e.g. session
            // switch), fall back to the list view.
            final match = chars.where((c) => c.id == _editingId);
            if (match.isEmpty) {
              _editingId = null;
            } else {
              final c = match.first;
              if (c.custom != null) {
                return CustomSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
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
              if (c.kalArath != null) {
                return KalArathSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.ose != null) {
                return OseSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.dcc != null) {
                return DccSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.funnel != null) {
                return FunnelSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.knave != null) {
                return KnaveSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.cairn != null) {
                return CairnSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.argosa != null) {
                return ArgosaSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.drawSteel != null) {
                return DrawSteelSheetView(
                  character: c,
                  onBack: () {
                    ref
                        .read(playContextProvider.notifier)
                        .setActiveCharacter(null);
                    setState(() => _editingId = null);
                  },
                );
              }
              if (c.nimble != null) {
                return NimbleSheetView(
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
            return EmptyState(
              title: 'Every story needs a hero.',
              body: 'Create your first character.',
              primaryLabel: 'Create character',
              onPrimary: () => _onAdd(context),
            );
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
        !systems.contains('shadowdark') &&
        !systems.contains('nimble') &&
        !systems.contains('draw-steel') &&
        !systems.contains('argosa') &&
        !systems.contains('cairn') &&
        !systems.contains('knave') &&
        !systems.contains('ose') &&
        !systems.contains('kal-arath') &&
        !systems.contains('custom') &&
        !systems.contains('dcc') &&
        !systems.contains('funnel')) {
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
      if (systems.contains('nimble'))
        (
          key: 'new-nimble',
          value: 'nimble',
          label: 'Nimble',
          blurb: 'Stats, wounds, slots, talents.'
        ),
      if (systems.contains('draw-steel'))
        (
          key: 'new-draw-steel',
          value: 'draw-steel',
          label: 'Draw Steel',
          blurb: 'Characteristics, stamina, heroic resource, power rolls.'
        ),
      if (systems.contains('argosa'))
        (
          key: 'new-argosa',
          value: 'argosa',
          label: 'Tales of Argosa',
          blurb: 'Stats, Luck, roll-under checks, Stagger.'
        ),
      if (systems.contains('ose'))
        (
          key: 'new-ose',
          value: 'ose',
          label: 'OSE / B/X',
          blurb: 'Stats, 5 saves (descending targets), descending AC, THAC0.'
        ),
      if (systems.contains('knave'))
        (
          key: 'new-knave',
          value: 'knave',
          label: 'Knave',
          blurb: 'Abilities, inventory slots, wounds, d20+score saves.'
        ),
      if (systems.contains('cairn'))
        (
          key: 'new-cairn',
          value: 'cairn',
          label: 'Cairn',
          blurb: 'Stats, saves, hit protection, Deprived, Fatigue.'
        ),
      if (systems.contains('kal-arath'))
        (
          key: 'new-kal-arath',
          value: 'kal-arath',
          label: 'Kal-Arath',
          blurb: '5 stats, 2d6+stat rolls, demonic pacts, Fate Points.'
        ),
      if (systems.contains('custom'))
        (
          key: 'new-custom',
          value: 'custom',
          label: 'Custom / Homebrew',
          blurb: 'Build your own sheet from blocks.'
        ),
      if (systems.contains('dcc'))
        (
          key: 'new-dcc',
          value: 'dcc',
          label: 'Dungeon Crawl Classics',
          blurb: '0-level funnel, dice chain, deeds, spellburn.'
        ),
      if (systems.contains('funnel'))
        (
          key: 'new-funnel',
          value: 'funnel',
          label: '0-Level Funnel',
          blurb: 'Doomed peasants → graduate survivors into any system.'
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
                if (!systems.contains('dnd') ||
                    !systems.contains('shadowdark') ||
                    !systems.contains('nimble') ||
                    !systems.contains('draw-steel') ||
                    !systems.contains('argosa') ||
                    !systems.contains('cairn') ||
                    !systems.contains('knave') ||
                    !systems.contains('ose') ||
                    !systems.contains('kal-arath') ||
                    !systems.contains('custom'))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                    child: Text(
                      'Enable D&D 5e, Shadowdark, Nimble, Draw Steel, Tales of Argosa, Cairn, Knave, OSE, Kal-Arath, or Custom in '
                      'Campaigns → Edit systems to add those sheets.',
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
    } else if (choice == 'nimble') {
      await _newNimble();
    } else if (choice == 'draw-steel') {
      await _newDrawSteel();
    } else if (choice == 'argosa') {
      await _newArgosa();
    } else if (choice == 'knave') {
      await _newKnave();
    } else if (choice == 'cairn') {
      await _newCairn();
    } else if (choice == 'ose') {
      await _newOse();
    } else if (choice == 'kal-arath') {
      await _newKalArath();
    } else if (choice == 'custom') {
      await _newCustom();
    } else if (choice == 'dcc') {
      await _newDcc();
    } else if (choice == 'funnel') {
      await _newFunnel(context);
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

  Future<void> _newNimble() async {
    final id = await ref.read(charactersProvider.notifier).addNimble();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newDrawSteel() async {
    final id = await ref.read(charactersProvider.notifier).addDrawSteel();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newArgosa() async {
    final id = await ref.read(charactersProvider.notifier).addArgosa();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newCairn() async {
    final id = await ref.read(charactersProvider.notifier).addCairn();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newKnave() async {
    final id = await ref.read(charactersProvider.notifier).addKnave();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newOse() async {
    final id = await ref.read(charactersProvider.notifier).addOse();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newKalArath() async {
    final id = await ref.read(charactersProvider.notifier).addKalArath();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newCustom() async {
    final template = await showDialog<CustomTemplate>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Start from…'),
        children: [
          for (final t in kCustomTemplates)
            SimpleDialogOption(
              key: Key('custom-template-${t.id}'),
              child: Text(t.label),
              onPressed: () => Navigator.pop(context, t),
            ),
        ],
      ),
    );
    if (template == null) return;
    final id =
        await ref.read(charactersProvider.notifier).addCustom(template.blocks);
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newDcc() async {
    final id = await ref.read(charactersProvider.notifier).addDcc();
    if (mounted) setState(() => _editingId = id);
  }

  Future<void> _newFunnel(BuildContext context) async {
    final enabled = ref
            .read(sessionsProvider)
            .valueOrNull
            ?.activeMeta
            .enabledSystems ??
        const <String>{};
    final seeds =
        kFunnelProfiles.keys.where((s) => enabled.contains(s)).toList();
    if (seeds.isEmpty) {
      final id = await ref.read(charactersProvider.notifier).addFunnel('dcc');
      if (mounted) setState(() => _editingId = id);
      return;
    }
    final seed = seeds.length == 1
        ? seeds.first
        : await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Funnel for which system?'),
              children: [
                for (final s in seeds)
                  SimpleDialogOption(
                    key: Key('funnel-seed-$s'),
                    onPressed: () => Navigator.pop(ctx, s),
                    child: Text(s),
                  ),
              ],
            ),
          );
    if (seed == null || !context.mounted) return;
    var seedVariant = '';
    if (seed == 'custom') {
      seedVariant = await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Custom funnel template'),
              children: [
                for (final t in kCustomTemplates)
                  SimpleDialogOption(
                    key: Key('funnel-template-${t.id}'),
                    onPressed: () => Navigator.pop(ctx, t.id),
                    child: Text(t.label),
                  ),
              ],
            ),
          ) ??
          '';
      if (!mounted) return;
      if (seedVariant.isEmpty) return; // cancelled the template pick
    }
    final id = await ref
        .read(charactersProvider.notifier)
        .addFunnel(seed, seedVariant: seedVariant);
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

  Widget _rosterCard(BuildContext context, Character c,
          {bool isLead = false}) =>
      isLead ? _leadCard(context, c) : _compactCard(context, c);

  /// Journal entries that @-mention [c] — shared by both card variants for the
  /// mentions backlink chip.
  List<JournalEntry> _mentionsFor(Character c) {
    final journal =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final charMentions = ref.watch(mentionedCharIdsProvider);
    return journal
        .where((e) => charMentions[e.id]?.contains(c.id) ?? false)
        .toList();
  }

  /// The condition chips + add-condition + mentions-backlink row, shared by
  /// both card variants. Keys `conditions-`/`mentions-` must stay findable.
  Widget _conditionsWrap(
      BuildContext context, Character c, List<JournalEntry> mentions,
      {Color? chipColor}) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final cond in c.conditions)
          Chip(
            label: Text(cond),
            backgroundColor: chipColor,
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
        // Backlink: where this character is @-mentioned in the journal.
        if (mentions.isNotEmpty)
          ActionChip(
            key: Key('mentions-${c.id}'),
            avatar: const Icon(Icons.link, size: 16),
            label: Text('Mentions ${mentions.length}'),
            visualDensity: VisualDensity.compact,
            onPressed: () => _showMentions(context, c, mentions),
          ),
      ],
    );
  }

  /// The role re-tag menu, shared by both variants. Key `role-` must stay
  /// findable.
  Widget _roleMenu(Character c) => PopupMenuButton<CharacterRole>(
        key: Key('role-${c.id}'),
        initialValue: c.role,
        tooltip: 'Role',
        onSelected: (r) =>
            ref.read(charactersProvider.notifier).setRole(c.id, r),
        itemBuilder: (_) => const [
          PopupMenuItem(value: CharacterRole.pc, child: Text('PC')),
          PopupMenuItem(
              value: CharacterRole.companion, child: Text('Companion')),
          PopupMenuItem(value: CharacterRole.npc, child: Text('NPC')),
        ],
      );

  Widget _starButton(Character c) => IconButton(
        key: Key('star-char-${c.id}'),
        visualDensity: VisualDensity.compact,
        icon: Icon(c.starred ? Icons.star : Icons.star_border),
        tooltip: c.starred ? 'Unstar' : 'Star',
        onPressed: () =>
            ref.read(charactersProvider.notifier).toggleStarred(c.id),
      );

  /// Resolve the lead card's vitals: system-aware HP/meter bars (label, cur,
  /// max) plus an optional secondary value (AC / torch / momentum). Falls back
  /// to the first generic track for any sheet without a bespoke HP pool.
  ({List<(String, int, int)> bars, String? extra}) _leadVitals(Character c) {
    if (c.dnd != null) {
      final d = c.dnd!;
      return (bars: [('HP', d.currentHp, d.maxHp)], extra: 'AC ${d.ac}');
    }
    if (c.shadowdark != null) {
      final s = c.shadowdark!;
      return (bars: [('HP', s.currentHp, s.maxHp)], extra: 'Torch ${s.torch}');
    }
    if (c.ironsworn != null) {
      final i = c.ironsworn!;
      final m = i.momentum >= 0 ? '+${i.momentum}' : '${i.momentum}';
      return (
        bars: [
          ('Health', i.health, 5),
          ('Spirit', i.spirit, 5),
          ('Supply', i.supply, 5),
        ],
        extra: 'Momentum $m',
      );
    }
    if (c.starforged != null) {
      final s = c.starforged!;
      final m = s.momentum >= 0 ? '+${s.momentum}' : '${s.momentum}';
      return (
        bars: [
          ('Health', s.health, 5),
          ('Spirit', s.spirit, 5),
          ('Supply', s.supply, 5),
        ],
        extra: 'Momentum $m',
      );
    }
    // Generic / any other sheet: the first track is the primary meter (the same
    // pool withHpDelta touches when there's no bespoke HP).
    if (c.tracks.isNotEmpty) {
      final t = c.tracks.first;
      return (bars: [(t.label, t.current, t.max)], extra: null);
    }
    return (bars: const <(String, int, int)>[], extra: null);
  }

  /// A single labeled vitals bar: label · cur/max value (terracotta) over a
  /// thin LinearProgressIndicator.
  Widget _vitalsBar(BuildContext context, String label, int cur, int max) {
    final tk = context.juice;
    final frac = max <= 0 ? 0.0 : (cur / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tk.inkBody)),
              ),
              Text('$cur/$max',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: tk.terracotta)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac,
              minHeight: 5,
              backgroundColor: tk.hairline,
              valueColor: AlwaysStoppedAnimation<Color>(tk.terracotta),
            ),
          ),
        ],
      ),
    );
  }

  /// Rich lead-PC card: vitals bars + quick actions. Renders only for the
  /// active PC (isLead).
  Widget _leadCard(BuildContext context, Character c) {
    final tk = context.juice;
    final mentions = _mentionsFor(c);
    final vitals = _leadVitals(c);
    final roleLabel =
        c.role == CharacterRole.pc ? 'PC' : c.role.name.toUpperCase();
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFF0CDB8)),
      ),
      child: Container(
        // Fill the roster row width (a Card in a ListView otherwise shrink-wraps
        // to its content).
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [tk.raised, tk.card],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: (star · name · role badge → tap opens sheet) · role menu.
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        ref
                            .read(playContextProvider.notifier)
                            .setActiveCharacter(c.id);
                        setState(() => _editingId = c.id);
                      },
                      child: Row(
                        children: [
                          Icon(Icons.star, color: tk.gold, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(c.name,
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: tk.ink)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: tk.selected,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(roleLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: tk.terracotta)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Role re-tag (keeps `role-<id>` findable on the lead card).
                  _roleMenu(c),
                ],
              ),
            ),
            // Vitals.
            for (final (label, cur, max) in vitals.bars)
              _vitalsBar(context, label, cur, max),
            if (vitals.extra != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(vitals.extra!,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tk.inkMuted)),
              ),
            const SizedBox(height: 4),
            _conditionsWrap(context, c, mentions, chipColor: tk.selected),
            const SizedBox(height: 10),
            Divider(height: 1, color: tk.hairline),
            const SizedBox(height: 10),
            // Quick-action row: roll a move · - hp · + hp · more.
            Row(
              children: [
                FilledButton.icon(
                  key: const Key('lead-roll-move'),
                  // Override the app-wide full-width minimum (Size.fromHeight in
                  // the FilledButton theme) so the button sizes to its content
                  // inside this Row (a full-width minimum + Spacer collide).
                  style: FilledButton.styleFrom(
                    backgroundColor: tk.terracotta,
                    visualDensity: VisualDensity.compact,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  icon: const Icon(Icons.casino_outlined, size: 18),
                  label: const Text('Roll a move'),
                  onPressed: () => ref
                      .read(shellRouteProvider.notifier)
                      .goTo(Destination.sheet, subtab: 'moves'),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('lead-hp-dec'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Damage',
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => ref
                      .read(charactersProvider.notifier)
                      .replace(c.withHpDelta(-1)),
                ),
                IconButton(
                  key: const Key('lead-hp-inc'),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Heal',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => ref
                      .read(charactersProvider.notifier)
                      .replace(c.withHpDelta(1)),
                ),
                // Secondary actions: star/unstar + delete. Role re-tag lives in
                // the header (the `role-<id>` PopupMenuButton) so its key stays
                // findable without nesting a menu inside this one.
                PopupMenuButton<String>(
                  key: const Key('lead-more'),
                  tooltip: 'More',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (v) {
                    switch (v) {
                      case 'star':
                        ref
                            .read(charactersProvider.notifier)
                            .toggleStarred(c.id);
                      case 'delete':
                        ref.read(charactersProvider.notifier).remove(c.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      value: 'star',
                      child: Text(c.starred ? 'Unstar' : 'Star'),
                    ),
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Compact roster row for companions / NPCs (and any non-active PC). Keeps
  /// the original look; lightly token-styled.
  Widget _compactCard(BuildContext context, Character c) {
    final tk = context.juice;
    final t = c.tracks.isEmpty ? null : c.tracks.first;
    final mentions = _mentionsFor(c);
    return Card(
      color: tk.raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(c.name),
            subtitle: t != null
                ? Text('${t.label} ${t.current}/${t.max}')
                : (c.note.isEmpty ? null : Text(c.note)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _roleMenu(c),
                _starButton(c),
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
            child: _conditionsWrap(context, c, mentions),
          ),
        ],
      ),
    );
  }

  /// A transient list of journal entries that @-mention [c] — the reverse of
  /// the journal's mention links, so you can jump from a character to where
  /// they appear.
  Future<void> _showMentions(
      BuildContext context, Character c, List<JournalEntry> entries) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            ListTile(
              title: Text('${c.name} — mentioned in ${entries.length}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final e in entries)
              ListTile(
                dense: true,
                leading: const Icon(Icons.notes_outlined),
                title: Text(
                  e.title.isEmpty ? mentionsToPlain(e.body) : e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: e.title.isEmpty
                    ? null
                    : Text(mentionsToPlain(e.body),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
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

  Future<void> _editConditions(BuildContext context, Character c) =>
      showConditionsEditor(context, ref, c);

  Future<void> _fleshOutCharacter(BuildContext context, Character c) async {
    final seed = buildFleshOutSeed(ref,
        entityKind: c.role == CharacterRole.npc ? 'NPC' : 'character',
        name: c.name,
        existingDetail: c.note);
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
    final note =
        [c.note, detail].where((s) => s.trim().isNotEmpty).join('\n\n');
    final result = await showDialog<({String title, String note})>(
      context: context,
      builder: (_) => _EditDialog(
        heading: 'Flesh out — ${c.name}',
        labelA: 'Name',
        labelB: 'Note',
        initialA: c.name,
        initialB: note,
      ),
    );
    if (result == null || result.title.trim().isEmpty) return;
    await ref.read(charactersProvider.notifier).replace(
        c.copyWith(name: result.title.trim(), note: result.note.trim()));
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
            if (ref.watch(aiReadyProvider))
              IconButton(
                key: const Key('flesh-out-character'),
                icon: const AiBadge(),
                tooltip: 'Flesh out (AI)',
                onPressed: () => _fleshOutCharacter(context, c),
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

// -- Thread tally row -----------------------------------------------------
class _ThreadTallyRow extends ConsumerWidget {
  const _ThreadTallyRow(this.thread);
  final Thread thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(threadsProvider.notifier);
    final tally = thread.tally;
    if (tally == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: Key('thread-tally-add-${thread.id}'),
          icon: const Icon(Icons.flag_outlined, size: 18),
          label: const Text('Add success tally'),
          onPressed: () => _pickPreset(context, ref),
        ),
      );
    }
    final status = tally.won
        ? 'Success'
        : tally.failed
            ? 'Failed'
            : tally.label;
    final color = tally.won
        ? Colors.green
        : tally.failed
            ? Colors.red
            : Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Chip(
          label: Text(status),
          labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
        IconButton(
          key: Key('thread-tally-dec-${thread.id}'),
          icon: const Icon(Icons.remove),
          tooltip: 'Setback (-1)',
          onPressed: () => notifier.adjustTally(thread.id, -1),
        ),
        IconButton(
          key: Key('thread-tally-inc-${thread.id}'),
          icon: const Icon(Icons.add),
          tooltip: 'Progress (+1)',
          onPressed: () => notifier.adjustTally(thread.id, 1),
        ),
        IconButton(
          key: Key('thread-tally-roll-${thread.id}'),
          icon: const Icon(Icons.casino_outlined),
          tooltip: 'Roll vs tally',
          onPressed: () {
            final outcome = rollVsTally(tally, Dice());
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(outcome == TallyRollOutcome.clean
                  ? 'Roll vs ${tally.label}: clean'
                  : 'Roll vs ${tally.label}: complication'),
            ));
          },
        ),
        IconButton(
          key: Key('thread-tally-remove-${thread.id}'),
          icon: const Icon(Icons.close),
          tooltip: 'Remove tally',
          onPressed: () => notifier.clearTally(thread.id),
        ),
      ],
    );
  }

  Future<void> _pickPreset(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<(String, int, int)>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in kTallyPresets)
              ListTile(
                key: Key('tally-preset-${p.$1}'),
                title: Text(p.$1),
                trailing: Text('${p.$2}(${p.$3})'),
                onTap: () => Navigator.pop(context, p),
              ),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await ref.read(threadsProvider.notifier).setTally(
          thread.id,
          Tally(start: choice.$2, current: choice.$2, target: choice.$3),
        );
  }
}
