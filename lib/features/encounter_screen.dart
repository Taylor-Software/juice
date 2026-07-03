import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/combat.dart';
import '../engine/dice_notation.dart';
import '../engine/lonelog_combat.dart';
import '../engine/models.dart';
import '../state/providers.dart';
import 'quick_ref_view.dart';

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
            key: const Key('enc-rules'),
            icon: const Icon(Icons.menu_book_outlined),
            tooltip: 'Rules quick reference',
            onPressed: () => showQuickRef(context),
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
        } else if (linked.kalArath != null) {
          curHp = linked.kalArath!.currentHp;
          maxHp = linked.kalArath!.maxHp;
        } else if (linked.ose != null) {
          curHp = linked.ose!.currentHp;
          maxHp = linked.ose!.maxHp;
        } else if (linked.knave != null) {
          curHp = linked.knave!.currentHp;
          maxHp = linked.knave!.maxHp;
        } else if (linked.cairn != null) {
          curHp = linked.cairn!.currentHp;
          maxHp = linked.cairn!.maxHp;
        } else if (linked.argosa != null) {
          curHp = linked.argosa!.currentHp;
          maxHp = linked.argosa!.maxHp;
        } else if (linked.drawSteel != null) {
          curHp = linked.drawSteel!.currentStamina;
          maxHp = linked.drawSteel!.maxStamina;
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
        leading: InkWell(
          key: Key('enc-init-${c.id}'),
          onTap: () => _editInit(context, ref, c),
          child: CircleAvatar(
            backgroundColor: c.defeated
                ? theme.colorScheme.surfaceContainerHighest
                : (isTurn ? theme.colorScheme.primaryContainer : null),
            foregroundColor: c.defeated
                ? theme.colorScheme.onSurfaceVariant
                : (isTurn ? theme.colorScheme.onPrimaryContainer : null),
            child: Text('${c.initiative}'),
          ),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: c.defeated
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant)
              : null,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (c.initMod != 0)
              Text('init ${c.initMod >= 0 ? '+' : ''}${c.initMod}',
                  key: Key('enc-initmod-${c.id}'),
                  style: theme.textTheme.bodySmall),
            // HP steppers on their own line. The FittedBox scales this
            // fixed-size Row down to fit a narrow subtitle instead of
            // overflowing.
            if (curHp != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
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
              ),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                // Attack: pick a target, roll, resolve. Lives in the wrapping
                // subtitle (not the fixed trailing slot) so it never overflows
                // a narrow row. Hidden for a defeated attacker / no live target.
                if (!c.defeated && _liveTargets(s, c).isNotEmpty)
                  ActionChip(
                    key: Key('enc-attack-${c.id}'),
                    avatar: const Icon(Icons.sports_martial_arts, size: 16),
                    label: const Text('Attack'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onPressed: () =>
                        _attack(context, ref, c, _liveTargets(s, c), chars),
                  ),
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
        // Compact so the three actions leave the wrapping subtitle enough room
        // on a narrow (phone-width) encounter pane.
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: Key('enc-statblock-${c.id}'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
              icon: Icon(
                Icons.shield_outlined,
                color: (c.statBlock != null && !c.statBlock!.isEmpty)
                    ? theme.colorScheme.primary
                    : null,
              ),
              tooltip: 'Stat block',
              onPressed: () => _editStatBlock(context, ref, c),
            ),
            IconButton(
              key: Key('enc-defeat-$i'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
              icon: Icon(c.defeated
                  ? Icons.favorite_outline
                  : Icons.heart_broken_outlined),
              tooltip: c.defeated ? 'Revive' : 'Mark defeated',
              onPressed: () => ref
                  .read(encounterProvider.notifier)
                  .updateCombatant(c.copyWith(defeated: !c.defeated)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 40),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove',
              onPressed: () =>
                  ref.read(encounterProvider.notifier).removeCombatant(c.id),
            ),
          ],
        ),
      ),
    );
  }

  /// Live (non-defeated) combatants other than [attacker] — eligible targets.
  List<Combatant> _liveTargets(EncounterState s, Combatant attacker) => s
      .combatants
      .where((x) => x.id != attacker.id && !x.defeated)
      .toList();

  void _attack(BuildContext context, WidgetRef ref, Combatant attacker,
      List<Combatant> targets, List<Character> chars) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _AttackDialog(attacker: attacker, targets: targets, chars: chars),
    );
  }

  Widget _addButtons(BuildContext context, WidgetRef ref) {
    final foes = ref.watch(foesProvider).valueOrNull ?? const <FoeCollection>[];
    final systems =
        ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
            kAllSystems;
    final cairnFoes =
        systems.contains('cairn') ? (ref.watch(systemFoesProvider('cairn')).valueOrNull ?? const <Creature>[]) : const <Creature>[];
    final oseFoes =
        systems.contains('ose') ? (ref.watch(systemFoesProvider('ose')).valueOrNull ?? const <Creature>[]) : const <Creature>[];
    final refMonsters =
        ref.watch(contentMonstersProvider).valueOrNull ?? const <Creature>[];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
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
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('generate-monster'),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Generate'),
                onPressed: () => _generateMonster(context, ref),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('add-bestiary'),
                icon: const Icon(Icons.pets_outlined),
                label: const Text('Bestiary'),
                onPressed: () => _addFromBestiary(context, ref),
              ),
            ),
          ]),
          if (foes.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('add-foes'),
                icon: const Icon(Icons.book_outlined),
                label: const Text('Ruleset foes'),
                onPressed: () => _addFromFoes(context, ref, foes),
              ),
            ),
          ],
          if (cairnFoes.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('add-cairn-foes'),
                icon: const Icon(Icons.terrain_outlined),
                label: const Text('Cairn creatures'),
                onPressed: () => _addFromSystemCreatures(
                    context, ref, cairnFoes, 'Add Cairn creature'),
              ),
            ),
          ],
          if (oseFoes.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('add-ose-foes'),
                icon: const Icon(Icons.castle_outlined),
                label: const Text('OSE monsters'),
                onPressed: () => _addFromSystemCreatures(
                    context, ref, oseFoes, 'Add OSE monster'),
              ),
            ),
          ],
          if (refMonsters.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const Key('add-from-reference'),
                icon: const Icon(Icons.menu_book_outlined),
                label: const Text('Add from reference'),
                onPressed: () => _addFromReference(context, ref, refMonsters),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addFromBestiary(BuildContext context, WidgetRef ref) async {
    final creature = await showDialog<Creature>(
      context: context,
      builder: (_) => const _BestiaryPickerDialog(),
    );
    if (creature == null) return;
    await ref.read(encounterProvider.notifier).addCombatant(Combatant(
          id: _newId(),
          name: creature.name,
          initiative: 0,
          track: creature.maxHp > 0
              ? CharTrack(
                  label: 'HP', current: creature.maxHp, max: creature.maxHp)
              : null,
          statBlock: creature.statBlock.isEmpty ? null : creature.statBlock,
        ));
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  Future<void> _endEncounter(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<_EndEncounterResult>(
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
    // Optionally advance a linked thread's progress clock in the same gesture.
    if (result.threadId != null && result.progressDelta != 0) {
      final threads =
          ref.read(threadsProvider).valueOrNull ?? const <Thread>[];
      final t = threads.where((e) => e.id == result.threadId).firstOrNull;
      if (t != null) {
        await ref
            .read(threadsProvider.notifier)
            .setProgress(t.id, t.progress + result.progressDelta);
      }
    }
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
  Future<void> _editStatBlock(
      BuildContext context, WidgetRef ref, Combatant c) async {
    final result = await showDialog<StatBlock>(
      context: context,
      builder: (_) => _StatBlockDialog(
        initial: c.statBlock,
        onSaveTobestiary: (sb) => _saveToBestiary(context, ref, c, sb),
      ),
    );
    if (result == null) return; // dialog cancelled
    final notifier = ref.read(encounterProvider.notifier);
    if (result.isEmpty) {
      await notifier.updateCombatant(c.copyWith(clearStatBlock: true));
    } else {
      await notifier.updateCombatant(c.copyWith(statBlock: result));
    }
  }

  Future<void> _saveToBestiary(
      BuildContext context, WidgetRef ref, Combatant c, StatBlock sb) async {
    await ref.read(bestiaryProvider.notifier).add(Creature(
          id: _newId(),
          name: c.name,
          statBlock: sb,
          maxHp: c.track?.max ?? 0,
        ));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved ${c.name} to bestiary')));
    }
  }

  Future<void> _editInit(
      BuildContext context, WidgetRef ref, Combatant c) async {
    final result = await showDialog<({int initiative, int mod})>(
      context: context,
      builder: (_) => _InitDialog(initiative: c.initiative, mod: c.initMod),
    );
    if (result == null) return;
    await ref.read(encounterProvider.notifier).updateCombatant(
        c.copyWith(initiative: result.initiative, initMod: result.mod));
  }

  Future<void> _addFromFoes(BuildContext context, WidgetRef ref,
      List<FoeCollection> collections) async {
    final entry = await showDialog<FoeEntry>(
      context: context,
      builder: (_) => _FoePickerDialog(collections: collections),
    );
    if (entry == null) return;
    final hp = entry.rank * 10;
    final noteParts = [
      if (entry.tactics.isNotEmpty) 'Tactics: ${entry.tactics.join(', ')}',
      if (entry.features.isNotEmpty) 'Features: ${entry.features.join(', ')}',
    ];
    await ref.read(encounterProvider.notifier).addCombatant(Combatant(
          id: _newId(),
          name: entry.name,
          initiative: 0,
          track: CharTrack(label: 'HP', current: hp, max: hp),
          statBlock: noteParts.isNotEmpty
              ? StatBlock(notes: noteParts.join('\n'))
              : null,
        ));
  }

  Future<void> _addFromSystemCreatures(BuildContext context, WidgetRef ref,
      List<Creature> creatures, String title) async {
    final creature = await showDialog<Creature>(
      context: context,
      builder: (_) =>
          _SystemCreaturePickerDialog(creatures: creatures, title: title),
    );
    if (creature == null) return;
    await ref.read(encounterProvider.notifier).addCombatant(Combatant(
          id: _newId(),
          name: creature.name,
          initiative: 0,
          track: creature.maxHp > 0
              ? CharTrack(
                  label: 'HP',
                  current: creature.maxHp,
                  max: creature.maxHp)
              : null,
          statBlock: creature.statBlock,
        ));
  }

  Future<void> _addFromReference(
      BuildContext context, WidgetRef ref, List<Creature> creatures) async {
    final creature = await showDialog<Creature>(
      context: context,
      builder: (_) => _ReferenceMonsterPicker(creatures: creatures),
    );
    if (creature == null) return;
    await ref.read(encounterProvider.notifier).addCombatant(Combatant(
          id: _newId(),
          name: creature.name,
          initiative: 0,
          track: creature.maxHp > 0
              ? CharTrack(
                  label: 'HP', current: creature.maxHp, max: creature.maxHp)
              : null,
          statBlock: creature.statBlock.isEmpty ? null : creature.statBlock,
        ));
  }
}

/// End-encounter confirmation that also captures an optional outcome note
/// (folded into the journal summary). Owns its controller so it disposes after
/// the dialog is fully gone. Pops `({note})` on End, null on Cancel.
typedef _EndEncounterResult = ({
  String note,
  String? threadId,
  int progressDelta,
});

class _EndEncounterDialog extends ConsumerStatefulWidget {
  const _EndEncounterDialog();

  @override
  ConsumerState<_EndEncounterDialog> createState() =>
      _EndEncounterDialogState();
}

class _EndEncounterDialogState extends ConsumerState<_EndEncounterDialog> {
  final _ctrl = TextEditingController();
  String? _threadId; // null = no thread
  int _delta = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  _EndEncounterResult get _result =>
      (note: _ctrl.text, threadId: _threadId, progressDelta: _delta);

  @override
  Widget build(BuildContext context) {
    final openThreads = [
      for (final t
          in ref.watch(threadsProvider).valueOrNull ?? const <Thread>[])
        if (t.open) t,
    ];
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
            onSubmitted: (_) => Navigator.pop(context, _result),
          ),
          if (openThreads.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButton<String?>(
              key: const Key('end-encounter-thread'),
              isExpanded: true,
              value: _threadId,
              hint: const Text('Advance a thread (optional)'),
              items: [
                const DropdownMenuItem(value: null, child: Text('No thread')),
                for (final t in openThreads)
                  DropdownMenuItem(value: t.id, child: Text(t.title)),
              ],
              onChanged: (v) => setState(() {
                _threadId = v;
                if (v == null) _delta = 0;
              }),
            ),
            if (_threadId != null)
              Row(
                key: const Key('end-encounter-progress'),
                children: [
                  const Text('Progress'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed:
                        _delta > 0 ? () => setState(() => _delta--) : null,
                  ),
                  Text('+$_delta'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () => setState(() => _delta++),
                  ),
                ],
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('end-encounter-confirm'),
          onPressed: () => Navigator.pop(context, _result),
          child: const Text('End'),
        ),
      ],
    );
  }
}

class _StatBlockDialog extends StatefulWidget {
  const _StatBlockDialog({this.initial, this.onSaveTobestiary});
  final StatBlock? initial;
  /// Called with the current block when the user taps "Save to bestiary".
  /// Null = no save button shown (e.g. called outside an encounter context).
  final void Function(StatBlock)? onSaveTobestiary;
  @override
  State<_StatBlockDialog> createState() => _StatBlockDialogState();
}

class _StatBlockDialogState extends State<_StatBlockDialog> {
  late final TextEditingController _ac =
      TextEditingController(text: (widget.initial?.ac ?? 0) == 0 ? '' : '${widget.initial!.ac}');
  late final TextEditingController _saves =
      TextEditingController(text: widget.initial?.saves ?? '');
  late final TextEditingController _speed =
      TextEditingController(text: widget.initial?.speed ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.initial?.notes ?? '');
  // Each attack = a (name, detail) controller pair.
  late final List<(TextEditingController, TextEditingController)> _attacks = [
    for (final a in widget.initial?.attacks ?? const <Attack>[])
      (TextEditingController(text: a.name), TextEditingController(text: a.detail)),
  ];

  @override
  void dispose() {
    _ac.dispose();
    _saves.dispose();
    _speed.dispose();
    _notes.dispose();
    for (final (n, d) in _attacks) {
      n.dispose();
      d.dispose();
    }
    super.dispose();
  }

  StatBlock _build() => StatBlock(
        ac: int.tryParse(_ac.text.trim()) ?? 0,
        attacks: [
          for (final (n, d) in _attacks)
            if (n.text.trim().isNotEmpty)
              Attack(name: n.text.trim(), detail: d.text.trim()),
        ],
        saves: _saves.text.trim(),
        speed: _speed.text.trim(),
        notes: _notes.text.trim(),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Stat block'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const Key('statblock-ac'),
            controller: _ac,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'AC'),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Attacks', style: Theme.of(context).textTheme.labelLarge),
          ),
          for (var i = 0; i < _attacks.length; i++)
            Row(children: [
              Expanded(
                child: TextField(
                  key: Key('statblock-attack-name-$i'),
                  controller: _attacks[i].$1,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: TextField(
                  key: Key('statblock-attack-detail-$i'),
                  controller: _attacks[i].$2,
                  decoration: const InputDecoration(labelText: 'Detail'),
                ),
              ),
              IconButton(
                key: Key('statblock-attack-remove-$i'),
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    final (n, d) = _attacks.removeAt(i);
                    n.dispose();
                    d.dispose();
                  });
                },
              ),
            ]),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('statblock-add-attack'),
              icon: const Icon(Icons.add),
              label: const Text('Add attack'),
              onPressed: () => setState(() => _attacks
                  .add((TextEditingController(), TextEditingController()))),
            ),
          ),
          TextField(
            key: const Key('statblock-saves'),
            controller: _saves,
            decoration: const InputDecoration(labelText: 'Saves'),
          ),
          TextField(
            key: const Key('statblock-speed'),
            controller: _speed,
            decoration: const InputDecoration(labelText: 'Speed'),
          ),
          TextField(
            key: const Key('statblock-notes'),
            controller: _notes,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
          ),
          if (widget.onSaveTobestiary != null) ...[
            const SizedBox(height: 8),
            const Divider(),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('statblock-save-bestiary'),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save to bestiary'),
                onPressed: () {
                  final sb = _build();
                  if (!sb.isEmpty) widget.onSaveTobestiary!(sb);
                },
              ),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('statblock-save'),
          onPressed: () => Navigator.pop(context, _build()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Edits a combatant's initiative value + per-combatant modifier. Pops
/// `({initiative, mod})` on Save, null on Cancel.
class _InitDialog extends StatefulWidget {
  const _InitDialog({required this.initiative, required this.mod});
  final int initiative;
  final int mod;
  @override
  State<_InitDialog> createState() => _InitDialogState();
}

class _InitDialogState extends State<_InitDialog> {
  late final TextEditingController _v =
      TextEditingController(text: '${widget.initiative}');
  late final TextEditingController _m =
      TextEditingController(text: widget.mod == 0 ? '' : '${widget.mod}');

  @override
  void dispose() {
    _v.dispose();
    _m.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Initiative'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          key: const Key('init-dialog-value'),
          controller: _v,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Initiative'),
        ),
        TextField(
          key: const Key('init-dialog-mod'),
          controller: _m,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Modifier'),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('init-dialog-save'),
          onPressed: () => Navigator.pop(context, (
            initiative: int.tryParse(_v.text.trim()) ?? widget.initiative,
            mod: int.tryParse(_m.text.trim()) ?? 0,
          )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Pops the chosen [FoeEntry], or null on cancel.
/// Groups entries by collection with section headers.
class _FoePickerDialog extends StatelessWidget {
  const _FoePickerDialog({required this.collections});
  final List<FoeCollection> collections;

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    return AlertDialog(
      title: const Text('Add foe'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 320,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final item = items[i];
            if (item is String) {
              return ListTile(
                dense: true,
                title: Text(
                  item,
                  style: Theme.of(ctx).textTheme.labelSmall!.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                ),
              );
            }
            final entry = item as FoeEntry;
            final rankLabel = kRankNames[entry.rank.clamp(1, 5)];
            return ListTile(
              key: Key('foe-pick-${entry.id}'),
              dense: true,
              title: Text(entry.name),
              subtitle: Text(entry.nature.isNotEmpty
                  ? '$rankLabel · ${entry.nature}'
                  : rankLabel),
              onTap: () => Navigator.pop(context, entry),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  List<Object> _buildItems() {
    final items = <Object>[];
    String? lastSection;
    for (final col in collections) {
      final section = col.ruleset.isNotEmpty
          ? '${col.ruleset} › ${col.name}'
          : col.name;
      if (section != lastSection) {
        items.add(section);
        lastSection = section;
      }
      items.addAll(col.entries);
    }
    return items;
  }
}

/// Pops the chosen [Creature], or null on cancel.
class _BestiaryPickerDialog extends ConsumerWidget {
  const _BestiaryPickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creatures =
        ref.watch(bestiaryProvider).valueOrNull ?? const <Creature>[];
    return AlertDialog(
      title: const Text('Add from bestiary'),
      content: SizedBox(
        width: 320,
        child: creatures.isEmpty
            ? const Text('No saved creatures yet. Save one from a combatant '
                'with a stat block.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final cr in creatures)
                    ListTile(
                      key: Key('bestiary-pick-${cr.id}'),
                      dense: true,
                      title: Text(cr.name),
                      subtitle: Text([
                        if (cr.statBlock.ac != 0) 'AC ${cr.statBlock.ac}',
                        if (cr.maxHp > 0) 'HP ${cr.maxHp}',
                      ].join(' · ')),
                      trailing: IconButton(
                        key: Key('bestiary-del-${cr.id}'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () =>
                            ref.read(bestiaryProvider.notifier).remove(cr.id),
                      ),
                      onTap: () => Navigator.pop(context, cr),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Read-only creature picker for bundled system foe lists (Cairn, OSE, etc.).
/// Pops the chosen [Creature], or null on cancel.
class _SystemCreaturePickerDialog extends StatelessWidget {
  const _SystemCreaturePickerDialog(
      {required this.creatures, required this.title});
  final List<Creature> creatures;
  final String title;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 320,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: creatures.length,
          itemBuilder: (ctx, i) {
            final cr = creatures[i];
            return ListTile(
              key: Key('sys-foe-pick-${cr.id}'),
              dense: true,
              title: Text(cr.name),
              subtitle: Text([
                if (cr.statBlock.ac != 0) 'AC/Armor ${cr.statBlock.ac}',
                if (cr.maxHp > 0) 'HP ${cr.maxHp}',
              ].join(' · ')),
              onTap: () => Navigator.pop(context, cr),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Searchable monster picker for the unified reference list (~334+ entries).
/// Pops the chosen [Creature], or null on cancel.
class _ReferenceMonsterPicker extends StatefulWidget {
  const _ReferenceMonsterPicker({required this.creatures});
  final List<Creature> creatures;

  @override
  State<_ReferenceMonsterPicker> createState() =>
      _ReferenceMonsterPickerState();
}

class _ReferenceMonsterPickerState extends State<_ReferenceMonsterPicker> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _ctrl.text.trim().toLowerCase();
    final items = q.isEmpty
        ? widget.creatures
        : widget.creatures
            .where((c) => c.name.toLowerCase().contains(q))
            .toList();
    return AlertDialog(
      title: const Text('Add from reference'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: 320,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const Key('ref-monster-search'),
                controller: _ctrl,
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Search'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final cr = items[i];
                  return ListTile(
                    key: Key('ref-monster-pick-${cr.id}'),
                    dense: true,
                    title: Text(cr.name),
                    subtitle: Text([
                      if (cr.statBlock.cr != null) 'CR ${cr.statBlock.cr}',
                      if (cr.maxHp > 0) 'HP ${cr.maxHp}',
                    ].join(' · ')),
                    onTap: () => Navigator.pop(context, cr),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Resolves one attack: pick a target, roll the attack (inline dice), auto
/// hit/miss against the target's recorded AC (manual when AC is 0), roll damage
/// on a hit and apply it to the target's HP (marking it defeated at 0), then log
/// one `combat` journal entry.
class _AttackDialog extends ConsumerStatefulWidget {
  const _AttackDialog(
      {required this.attacker, required this.targets, required this.chars});
  final Combatant attacker;
  final List<Combatant> targets;
  final List<Character> chars;

  @override
  ConsumerState<_AttackDialog> createState() => _AttackDialogState();
}

class _AttackDialogState extends ConsumerState<_AttackDialog> {
  late Combatant _target = widget.targets.first;
  final _atk = TextEditingController(text: '1d20');
  final _dmg = TextEditingController(text: '1d6');
  int? _attackTotal;
  bool? _hit; // null while undecided (AC unknown, awaiting a manual pick)

  // The app-wide FilledButton theme is full-width (Size.fromHeight => infinite
  // min-width); a bare FilledButton beside an Expanded field would throw
  // "forces an infinite width", so pin a finite min-width.
  static final _naturalWidth =
      FilledButton.styleFrom(minimumSize: const Size(0, 48));

  @override
  void dispose() {
    _atk.dispose();
    _dmg.dispose();
    super.dispose();
  }

  int _acOf(Combatant t) => t.statBlock?.ac ?? 0;

  /// Rolls a dice notation to its total, or null on empty oracle / bad notation.
  int? _roll(String notation) {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return null;
    try {
      return parseDice(notation.trim()).roll(oracle.dice).total;
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid dice notation')));
      return null;
    }
  }

  void _rollAttack() {
    final total = _roll(_atk.text);
    if (total == null) return;
    final outcome = resolveHit(total, _acOf(_target));
    setState(() {
      _attackTotal = total;
      _hit = outcome == AttackOutcome.unknown
          ? null
          : outcome == AttackOutcome.hit;
    });
  }

  /// Fills the dice fields from a stat-block attack's freeform detail and
  /// clears any prior roll so the next Roll uses the new dice. A field is only
  /// overwritten when a token was found (a damage-only attack keeps the 1d20
  /// attack default).
  void _pickAttack(Attack a) {
    final d = attackDiceFromDetail(a.detail);
    setState(() {
      if (d.attack != null) _atk.text = d.attack!;
      if (d.damage != null) _dmg.text = d.damage!;
      _attackTotal = null;
      _hit = null;
    });
  }

  /// Applies [damage] to [_target]'s HP pool — a linked character's pool via
  /// [characterHpPool]/[Character.withHpDelta], or its own [CharTrack]. Marks
  /// the target defeated at 0. Returns (before, after) HP, or null if it has no
  /// HP pool.
  (int, int)? _applyDamage(int damage) {
    final t = _target;
    if (t.characterId != null) {
      final match = widget.chars.where((ch) => ch.id == t.characterId);
      if (match.isEmpty) return null;
      final linked = match.first;
      final pool = characterHpPool(linked);
      if (pool == null) return null;
      ref
          .read(charactersProvider.notifier)
          .replace(linked.withHpDelta(-damage));
      final after = (pool.$1 - damage).clamp(0, pool.$2);
      if (after <= 0 && !t.defeated) {
        ref
            .read(encounterProvider.notifier)
            .updateCombatant(t.copyWith(defeated: true));
      }
      return (pool.$1, after);
    }
    if (t.track != null) {
      final before = t.track!.current;
      final after = (before - damage).clamp(0, t.track!.max);
      var updated = t.copyWith(track: t.track!.adjusted(-damage));
      if (after <= 0) updated = updated.copyWith(defeated: true);
      ref.read(encounterProvider.notifier).updateCombatant(updated);
      return (before, after);
    }
    return null;
  }

  void _log(
      {required int total, required bool hit, int? damage, (int, int)? hp}) {
    final line = combatLogLine(
      attacker: widget.attacker.name,
      target: _target.name,
      attackTotal: total,
      targetAc: _acOf(_target),
      hit: hit,
      damage: damage,
      hp: hp,
    );
    ref
        .read(journalProvider.notifier)
        .addResult('Combat', line, sourceTool: 'combat');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(line)));
  }

  void _apply() {
    final total = _attackTotal;
    if (total == null || _hit != true) return;
    final damage = _roll(_dmg.text);
    if (damage == null) return;
    _log(total: total, hit: true, damage: damage, hp: _applyDamage(damage));
    Navigator.of(context).pop();
  }

  void _logMiss() {
    final total = _attackTotal;
    if (total == null) return;
    _log(total: total, hit: false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final attacks = widget.attacker.statBlock?.attacks ?? const <Attack>[];
    final ac = _acOf(_target);
    final acClause = ac > 0 ? ' vs AC $ac' : '';
    return AlertDialog(
      key: const Key('attack-dialog'),
      title: Text('${widget.attacker.name} attacks'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Target'),
            DropdownButton<Combatant>(
              key: const Key('attack-target'),
              isExpanded: true,
              value: _target,
              items: [
                for (final t in widget.targets)
                  DropdownMenuItem(
                    value: t,
                    child: Text(
                        _acOf(t) > 0 ? '${t.name}  (AC ${_acOf(t)})' : t.name),
                  ),
              ],
              onChanged: (t) {
                if (t != null) {
                  setState(() {
                    _target = t;
                    _attackTotal = null;
                    _hit = null;
                  });
                }
              },
            ),
            // Tap an attack to prefill the dice fields from its freeform detail.
            if (attacks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final (i, a) in attacks.indexed)
                      ActionChip(
                        key: Key('attack-pick-$i'),
                        label: Text(a.name.isEmpty ? a.detail : a.name),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                        onPressed: () => _pickAttack(a),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('attack-roll'),
                    controller: _atk,
                    decoration:
                        const InputDecoration(labelText: 'Attack roll'),
                    onSubmitted: (_) => _rollAttack(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('attack-roll-go'),
                  style: _naturalWidth,
                  onPressed: _rollAttack,
                  child: const Text('Roll'),
                ),
              ],
            ),
            if (_attackTotal != null) ...[
              const SizedBox(height: 8),
              Text(
                _hit == null
                    ? 'Attack $_attackTotal$acClause — hit or miss?'
                    : 'Attack $_attackTotal$acClause — ${_hit! ? 'Hit' : 'Miss'}',
                key: const Key('attack-result'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_hit == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      OutlinedButton(
                        key: const Key('attack-hit'),
                        onPressed: () => setState(() => _hit = true),
                        child: const Text('Hit'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: const Key('attack-miss'),
                        onPressed: () => setState(() => _hit = false),
                        child: const Text('Miss'),
                      ),
                    ],
                  ),
                ),
              if (_hit == true) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('attack-damage'),
                        controller: _dmg,
                        decoration: const InputDecoration(labelText: 'Damage'),
                        onSubmitted: (_) => _apply(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('attack-apply'),
                      style: _naturalWidth,
                      onPressed: _apply,
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_hit == false)
          FilledButton(
            key: const Key('attack-log-miss'),
            onPressed: _logMiss,
            child: const Text('Log miss'),
          ),
      ],
    );
  }
}
