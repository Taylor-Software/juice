import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/sheet_rolls.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

class DccSheetView extends ConsumerWidget {
  const DccSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  DccSheet get _s => character.dcc!;

  void _save(WidgetRef ref, DccSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(dcc: next));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = _s;
    return _buildLeveled(context, ref, s);
  }

  String _sign(int n) => n >= 0 ? '+$n' : '$n';

  // ===================== LEVELED =====================

  Future<int?> _askDc(BuildContext context) {
    // A self-managing TextFormField (initialValue + onChanged into a closure)
    // avoids owning a TextEditingController — no leak, and nothing to dispose
    // mid-route-pop. Mirrors the closure-state pattern in other dialogs.
    var dc = 10;
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Target DC'),
        content: TextFormField(
          key: const Key('dcc-dc-field'),
          initialValue: '10',
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'DC'),
          onChanged: (v) => dc = int.tryParse(v) ?? dc,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              key: const Key('dcc-dc-confirm'),
              onPressed: () => Navigator.pop(ctx, dc),
              child: const Text('Roll')),
        ],
      ),
    );
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));

  Future<void> _rollSave(
      BuildContext context, WidgetRef ref, DccSheet s, String key) async {
    final dc = await _askDc(context);
    if (dc == null || !context.mounted) return;
    final r = dccSave(ref.read(diceProvider).dN(20), s.saves[key] ?? 0, dc);
    _snack(
        context, '${kDccSaveLabels[key]}: ${r.total} vs DC $dc — ${r.outcome}');
  }

  Widget _buildLeveled(BuildContext context, WidgetRef ref, DccSheet s) {
    void save(DccSheet next) => _save(ref, next);
    return ListView(
      key: const Key('dcc-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'dcc-name'),
        Row(children: [
          Chip(label: Text(s.className)),
          const SizedBox(width: 8),
          sheetStepper('dcc-level', 'Level', s.level,
              min: 1, max: 10, onSet: (v) => save(s.copyWith(level: v))),
          const SizedBox(width: 8),
          DropdownButton<String>(
            key: const Key('dcc-alignment'),
            value: kDccAlignments.contains(s.alignment) ? s.alignment : null,
            items: kDccAlignments
                .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                .toList(),
            onChanged: (v) {
              if (v != null) save(s.copyWith(alignment: v));
            },
          ),
        ]),
        const SizedBox(height: 12),
        sheetSection(context, 'Ability Scores'),
        Wrap(spacing: 12, runSpacing: 8, children: [
          for (final k in kDccStats) _statCell(context, ref, s, k),
        ]),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('dcc-lucky-sign'),
          initialValue: s.luckySign,
          label: 'Lucky Sign / Birth Augur',
          onSave: (v) => save(s.copyWith(luckySign: v)),
        ),
        const SizedBox(height: 12),
        sheetSection(context, 'Combat'),
        Wrap(spacing: 16, runSpacing: 8, children: [
          sheetStepper('dcc-hp', 'HP', s.currentHp,
              max: s.maxHp, onSet: (v) => save(s.copyWith(currentHp: v))),
          sheetStepper('dcc-maxhp', 'Max', s.maxHp,
              onSet: (v) => save(s.copyWith(maxHp: v))),
          sheetStepper('dcc-ac', 'AC', s.ac,
              min: 0, max: 30, onSet: (v) => save(s.copyWith(ac: v))),
          sheetStepper('dcc-atk', 'Atk', s.attackBonus,
              min: -5, max: 20, onSet: (v) => save(s.copyWith(attackBonus: v))),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Action die '),
            DropdownButton<String>(
              key: const Key('dcc-action-die'),
              value: s.actionDie,
              items: kDccActionDice
                  .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                  .toList(),
              onChanged: (v) {
                if (v != null) save(s.copyWith(actionDie: v));
              },
            ),
          ]),
        ]),
        const SizedBox(height: 12),
        sheetSection(context, 'Saving Throws'),
        for (final k in kDccSaveKeys)
          Row(children: [
            Expanded(child: Text(kDccSaveLabels[k]!)),
            sheetStepper('dcc-save-$k', '', s.saves[k] ?? 0,
                min: -5,
                max: 20,
                onSet: (v) => save(s.copyWith(saves: {...s.saves, k: v}))),
            IconButton(
              key: Key('dcc-$k-roll'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.casino_outlined, size: 18),
              tooltip: 'Roll vs DC',
              onPressed: () => _rollSave(context, ref, s, k),
            ),
          ]),
        const SizedBox(height: 12),
        if (s.hasDeedDie) _deedSection(context, ref, s),
        if (s.isCaster) _spellburnSection(context, ref, s),
        if (s.isCleric) _disapprovalSection(context, ref, s),
        sheetSection(context, 'Occupation'),
        DebouncedTextField(
          key: const Key('dcc-occupation'),
          initialValue: s.occupation,
          label: 'Occupation',
          onSave: (v) => save(s.copyWith(occupation: v)),
        ),
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'dcc'),
        magicSection(context, ref, character),
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('dcc-notes'),
          initialValue: s.notes,
          maxLines: 4,
          label: 'Notes / Equipment',
          onSave: (v) => save(s.copyWith(notes: v)),
        ),
      ],
    );
  }

  Widget _statCell(BuildContext context, WidgetRef ref, DccSheet s, String k) {
    void save(DccSheet next) => _save(ref, next);
    final isLck = k == 'lck';
    return Column(
        key: Key('dcc-stat-$k'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${kDccStatLabels[k]} (${_sign(s.mod(k))})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          sheetStepper('dcc-stat-$k', '', s.stats[k] ?? 10,
              min: 3,
              max: 18,
              onSet: (v) => save(s.copyWith(stats: {...s.stats, k: v}))),
          if (isLck)
            luckTokensSection(
              keyPrefix: 'dcc-luck',
              label: 'Luck',
              current: s.stats['lck'] ?? 10,
              max: s.lckMax,
              onSet: (v) => save(s.copyWith(stats: {...s.stats, 'lck': v})),
              onReset: () =>
                  save(s.copyWith(stats: {...s.stats, 'lck': s.lckMax})),
            ),
          if (isLck && s.luckyRecoveryClass)
            const Text('Recovers 1 / level on rest',
                style: TextStyle(fontSize: 11)),
        ]);
  }

  Widget _deedSection(BuildContext context, WidgetRef ref, DccSheet s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, 'Mighty Deeds'),
      Wrap(spacing: 8, runSpacing: 4, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('Deed die '),
          DropdownButton<String>(
            key: const Key('dcc-deed-die-picker'),
            value: s.deedDie,
            items: kDccDeedDice
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) {
              if (v != null) _save(ref, s.copyWith(deedDie: v));
            },
          ),
        ]),
        FilledButton.icon(
          key: const Key('dcc-deed-roll'),
          // Natural width inside the section Wrap (see loop_bar note).
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          icon: const Icon(Icons.casino_outlined, size: 18),
          label: const Text('Attack + Deed'),
          onPressed: () {
            final dice = ref.read(diceProvider);
            final r = dccDeed(
              dice.dN(20),
              s.attackBonus,
              dice.dN(int.parse(s.deedDie.substring(1))),
              kDccDeedSuccessMin,
            );
            _snack(context,
                'Attack: ${r.attack}, Deed: ${r.deed} — ${r.deedSucceeds ? "Deed succeeds!" : "no deed"}');
          },
        ),
      ]),
      const SizedBox(height: 12),
    ]);
  }

  Widget _spellburnSection(BuildContext context, WidgetRef ref, DccSheet s) {
    final castStat = s.castingStat ?? 'int';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, 'Spellburn'),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final k in s.burnableStats)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${kDccStatLabels[k]}  ${s.effectiveScore(k)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            sheetStepper('dcc-burn-$k', 'burn', s.burned(k),
                min: 0,
                max: 18,
                onSet: (v) =>
                    _save(ref, s.copyWith(burns: {...s.burns, k: v}))),
          ]),
      ]),
      Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Spellburn: +${s.totalSpellburn}'),
            TextButton(
              key: const Key('dcc-spellburn-reset'),
              onPressed: () => _save(ref,
                  s.copyWith(burns: {for (final k in s.burnableStats) k: 0})),
              child: const Text('Reset'),
            ),
            FilledButton.icon(
              key: const Key('dcc-spell-check-roll'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Spell check'),
              onPressed: () async {
                final dc = await _askDc(context);
                if (dc == null || !context.mounted) return;
                final r = dccSpellCheck(
                  actionDie: ref
                      .read(diceProvider)
                      .dN(int.parse(s.actionDie.substring(1))),
                  level: s.level,
                  abilityMod: dccAbilityMod(s.stats[castStat] ?? 10),
                  spellburn: s.totalSpellburn,
                  dc: dc,
                );
                _snack(context,
                    'Spell check: ${r.total} (base ${r.base} + ${s.totalSpellburn} spellburn) vs DC $dc — ${r.success ? "Success" : "Fail"}');
              },
            ),
          ]),
      const SizedBox(height: 12),
    ]);
  }

  Widget _disapprovalSection(BuildContext context, WidgetRef ref, DccSheet s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, 'Disapproval'),
      Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Range 1–${s.disapprovalRange}'),
            IconButton(
              key: const Key('dcc-disapproval-inc'),
              icon: const Icon(Icons.add),
              tooltip: '+1 after failed casting',
              onPressed: () => _save(
                  ref, s.copyWith(disapprovalRange: s.disapprovalRange + 1)),
            ),
            TextButton(
              key: const Key('dcc-disapproval-reset'),
              onPressed: () => _save(ref, s.copyWith(disapprovalRange: 1)),
              child: const Text('Reset'),
            ),
            FilledButton.icon(
              key: const Key('dcc-disapproval-roll'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.casino_outlined, size: 18),
              label: const Text('Check'),
              onPressed: () {
                final r = dccDisapproval(
                    ref.read(diceProvider).dN(20), s.disapprovalRange);
                _snack(context,
                    'Disapproval check: ${r.roll} vs 1–${s.disapprovalRange} — ${r.disapproves ? "Disapproval!" : "Safe"}');
              },
            ),
          ]),
      const SizedBox(height: 12),
    ]);
  }
}
