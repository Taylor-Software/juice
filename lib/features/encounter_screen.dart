import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/lonelog_combat.dart';
import '../engine/models.dart';
import '../state/providers.dart';

/// Initiative tracker: combatants from character sheets (live first-track
/// link) or ad-hoc, turn pointer + round counter, statuses/defeated, and an
/// end-of-encounter summary into the journal.
class EncounterScreen extends ConsumerWidget {
  const EncounterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(encounterProvider);
    final chars =
        ref.watch(charactersProvider).valueOrNull ?? const <Character>[];
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (s) => Column(
        children: [
          _header(context, ref, s),
          Expanded(
            child: s.combatants.isEmpty
                ? _empty(context)
                : _list(context, ref, s, chars),
          ),
          _addButtons(context, ref),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, WidgetRef ref, EncounterState s) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          Text('Round ${s.round}', style: theme.textTheme.titleMedium),
          const Spacer(),
          // Flexible bounds the button's width. As a bare non-flex Row child
          // alongside a Spacer (flex), RenderFlex measures the FilledButton at
          // maxWidth:Infinity and a Material button throws "BoxConstraints
          // forces an infinite width" under the tool host's loose constraints
          // — freezing the app (release web) / blanking the tool (debug).
          // Same root cause and fix as the Maps tool's _controls.
          Flexible(
            child: FilledButton.tonal(
              key: const Key('next-turn'),
              onPressed: () => ref.read(encounterProvider.notifier).nextTurn(),
              child: const Text('Next turn'),
            ),
          ),
          IconButton(
            key: const Key('end-encounter'),
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'End encounter',
            onPressed: () => _endEncounter(context, ref),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No combatants. Add from your characters or ad-hoc.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, EncounterState s,
      List<Character> chars) {
    return ReorderableListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      // onReorderItem pre-adjusts newIndex for the removed item, but the
      // notifier's reorder expects raw ReorderableListView indices (it
      // applies the classic fixup itself) — so undo the adjustment here.
      onReorderItem: (oldIndex, newIndex) => ref
          .read(encounterProvider.notifier)
          .reorder(oldIndex, newIndex > oldIndex ? newIndex + 1 : newIndex),
      children: [
        for (var i = 0; i < s.combatants.length; i++)
          _row(context, ref, s, chars, i),
      ],
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, EncounterState s,
      List<Character> chars, int i) {
    final theme = Theme.of(context);
    final c = s.combatants[i];
    final isTurn = i == s.turnIndex;

    // Resolve HP live: a linked combatant reads its character's HP pool — the
    // D&D/Shadowdark sheet's currentHp or the first track (mirrors
    // Character.withHpDelta) — and an ad-hoc one carries its own track.
    Character? char;
    var name = c.name;
    int? curHp;
    int? maxHp;
    VoidCallback? minus;
    VoidCallback? plus;
    if (c.characterId != null) {
      final match = chars.where((ch) => ch.id == c.characterId);
      char = match.isEmpty ? null : match.first;
      if (char == null) {
        name = '${c.name} (missing)';
      } else {
        final linked = char;
        if (linked.dnd != null) {
          curHp = linked.dnd!.currentHp;
          maxHp = linked.dnd!.maxHp;
        } else if (linked.shadowdark != null) {
          curHp = linked.shadowdark!.currentHp;
          maxHp = linked.shadowdark!.maxHp;
        } else if (linked.nimble != null) {
          curHp = linked.nimble!.currentHp;
          maxHp = linked.nimble!.maxHp;
        } else if (linked.tracks.isNotEmpty) {
          curHp = linked.tracks.first.current;
          maxHp = linked.tracks.first.max;
        }
        if (curHp != null) {
          minus = () => ref
              .read(charactersProvider.notifier)
              .replace(linked.withHpDelta(-1));
          plus = () => ref
              .read(charactersProvider.notifier)
              .replace(linked.withHpDelta(1));
        }
      }
    } else if (c.track != null) {
      curHp = c.track!.current;
      maxHp = c.track!.max;
      void step(int delta) => ref
          .read(encounterProvider.notifier)
          .updateCombatant(c.copyWith(track: c.track!.adjusted(delta)));
      minus = () => step(-1);
      plus = () => step(1);
    }

    return Card(
      key: ValueKey(c.id),
      child: ListTile(
        selected: isTurn,
        leading: CircleAvatar(
          backgroundColor: c.defeated
              ? theme.colorScheme.surfaceContainerHighest
              : (isTurn ? theme.colorScheme.primaryContainer : null),
          foregroundColor: c.defeated
              ? theme.colorScheme.onSurfaceVariant
              : (isTurn ? theme.colorScheme.onPrimaryContainer : null),
          child: Text('${c.initiative}'),
        ),
        title: Text(
          name,
          style: c.defeated
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant)
              : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (curHp != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('enc-minus-$i'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: minus,
                  ),
                  Text('$curHp/$maxHp', key: Key('enc-track-$i')),
                  IconButton(
                    key: Key('enc-plus-$i'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: plus,
                  ),
                ],
              ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Linked character's conditions, read through live (like HP) so
                // a poisoned PC shows it in the turn order; edit on the sheet.
                if (char != null)
                  for (final cond in char.conditions)
                    Chip(
                      key: Key('enc-cond-$i-$cond'),
                      label: Text(cond),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: theme.colorScheme.errorContainer,
                    ),
                for (final tag in c.tags)
                  InputChip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => ref
                        .read(encounterProvider.notifier)
                        .updateCombatant(c.copyWith(
                            tags: c.tags.where((t) => t != tag).toList())),
                  ),
                ActionChip(
                  key: Key('enc-tag-add-$i'),
                  label: const Text('+'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _addTag(context, ref, c),
                ),
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('enc-defeat-$i'),
              icon: Icon(c.defeated
                  ? Icons.favorite_outline
                  : Icons.heart_broken_outlined),
              tooltip: c.defeated ? 'Revive' : 'Mark defeated',
              onPressed: () => ref
                  .read(encounterProvider.notifier)
                  .updateCombatant(c.copyWith(defeated: !c.defeated)),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  ref.read(encounterProvider.notifier).removeCombatant(c.id),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addButtons(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('add-character'),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('From characters'),
              onPressed: () => _addFromCharacters(context, ref),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('add-adhoc'),
              icon: const Icon(Icons.add),
              label: const Text('Ad-hoc'),
              onPressed: () => _addAdHoc(context, ref),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const Key('generate-monster'),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate'),
              onPressed: () => _generateMonster(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _endEncounter(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({String note})>(
      context: context,
      builder: (context) => const _EndEncounterDialog(),
    );
    if (result == null) return;
    final s = ref.read(encounterProvider).valueOrNull ?? const EncounterState();
    final lonelog =
        (ref.read(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
                kAllSystems)
            .contains('lonelog');
    final String body;
    if (lonelog) {
      // Lonelog Combat addon: emit a [COMBAT] block the journal highlights.
      body = encounterToLonelog(s);
    } else {
      final defeated = [
        for (final c in s.combatants)
          if (c.defeated) c.name,
      ];
      body = 'Round ${s.round} — ${defeated.isEmpty //
          ? 'no combatants defeated' : 'defeated: ${defeated.join(', ')}'}';
    }
    // Fold the GM's optional outcome note into the summary.
    final note = result.note.trim();
    final fullBody = note.isEmpty ? body : '$body\n$note';
    await ref.read(journalProvider.notifier).add('Encounter ended', fullBody);
    await ref.read(encounterProvider.notifier).reset();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to journal')),
      );
    }
  }

  Future<void> _addTag(BuildContext context, WidgetRef ref, Combatant c) async {
    final tagCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add status'),
          content: TextField(
            key: const Key('enc-tag-input'),
            controller: tagCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Status'),
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
    await ref
        .read(encounterProvider.notifier)
        .updateCombatant(c.copyWith(tags: [...c.tags, tag]));
  }

  Future<void> _addFromCharacters(BuildContext context, WidgetRef ref) async {
    final chars =
        ref.read(charactersProvider).valueOrNull ?? const <Character>[];
    final s = ref.read(encounterProvider).valueOrNull ?? const EncounterState();
    final linked =
        s.combatants.map((c) => c.characterId).whereType<String>().toSet();
    final available = chars.where((c) => !linked.contains(c.id)).toList();
    final init = TextEditingController(text: '10');
    final picked = await showDialog<Character>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add from characters'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('init-input'),
                controller: init,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Initiative'),
              ),
              const SizedBox(height: 12),
              if (available.isEmpty)
                const Text('All characters are already in the encounter.')
              else
                for (final c in available)
                  ListTile(
                    title: Text(c.name),
                    onTap: () => Navigator.pop(context, c),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    final initText = init.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => init.dispose());
    if (picked == null) return;
    await ref.read(encounterProvider.notifier).addCombatant(Combatant(
          id: _newId(),
          name: picked.name,
          characterId: picked.id,
          initiative: int.tryParse(initText) ?? 10,
        ));
  }

  Future<void> _generateMonster(BuildContext context, WidgetRef ref) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final g = oracle.monsterEncounter();
    final monster = g.rolls
        .firstWhere(
          (r) => r.label == 'Monster',
          orElse: () => g.rolls.isNotEmpty
              ? g.rolls.first
              : const Roll(label: '', value: ''),
        )
        .value;
    await _addAdHoc(context, ref,
        initialName: monster.isNotEmpty ? monster : g.title);
  }

  Future<void> _addAdHoc(BuildContext context, WidgetRef ref,
      {String initialName = ''}) async {
    final name = TextEditingController(text: initialName);
    final hp = TextEditingController();
    final init = TextEditingController(text: '10');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add combatant'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('adhoc-name'),
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('adhoc-hp'),
              controller: hp,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'HP max'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('adhoc-init'),
              controller: init,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Initiative'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final nameText = name.text.trim();
    final hpText = hp.text.trim();
    final initText = init.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      name.dispose();
      hp.dispose();
      init.dispose();
    });
    if (ok != true || nameText.isEmpty) return;
    var max = int.tryParse(hpText) ?? 1;
    if (max < 1) max = 1;
    await ref.read(encounterProvider.notifier).addCombatant(Combatant(
          id: _newId(),
          name: nameText,
          initiative: int.tryParse(initText) ?? 10,
          track: CharTrack(label: 'HP', current: max, max: max),
        ));
  }
}

/// End-encounter confirmation that also captures an optional outcome note
/// (folded into the journal summary). Owns its controller so it disposes after
/// the dialog is fully gone. Pops `({note})` on End, null on Cancel.
class _EndEncounterDialog extends StatefulWidget {
  const _EndEncounterDialog();

  @override
  State<_EndEncounterDialog> createState() => _EndEncounterDialogState();
}

class _EndEncounterDialogState extends State<_EndEncounterDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('End encounter?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              'A summary is added to the journal and the tracker resets.'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('end-encounter-note'),
            controller: _ctrl,
            decoration: const InputDecoration(labelText: 'Outcome (optional)'),
            onSubmitted: (_) => Navigator.pop(context, (note: _ctrl.text)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('end-encounter-confirm'),
          onPressed: () => Navigator.pop(context, (note: _ctrl.text)),
          child: const Text('End'),
        ),
      ],
    );
  }
}
