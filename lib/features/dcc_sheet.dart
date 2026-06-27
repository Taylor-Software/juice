import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
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
    return s.isFunnel
        ? _buildFunnel(context, ref, s)
        : _buildLeveled(context, ref, s);
  }

  // ---- shared stepper (mirrors OseSheetView._stepper) ----
  Widget _stepper(String key, String label, int value,
          {required ValueChanged<int> onSet, int min = 0, int max = 9999}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (label.isNotEmpty) Text('$label '),
        IconButton(
          key: Key('$key-minus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove),
          onPressed: value > min ? () => onSet(value - 1) : null,
        ),
        Text('$value'),
        IconButton(
          key: Key('$key-plus'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add),
          onPressed: value < max ? () => onSet(value + 1) : null,
        ),
      ]);

  String _sign(int n) => n >= 0 ? '+$n' : '$n';

  // ===================== FUNNEL =====================
  Widget _buildFunnel(BuildContext context, WidgetRef ref, DccSheet s) {
    final theme = Theme.of(context);
    final alive = s.peasants.where((p) => p.alive).length;
    return ListView(
      key: const Key('dcc-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'dcc-name'),
        Text('0-Level Funnel', style: theme.textTheme.labelSmall),
        Text('$alive / ${s.peasants.length} alive',
            style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (var i = 0; i < s.peasants.length; i++)
          _peasantCard(context, ref, s, i),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const Key('dcc-add-peasant'),
            onPressed: s.peasants.length >= kDccMaxPeasants
                ? null
                : () => _save(ref,
                    s.copyWith(peasants: [...s.peasants, const DccPeasant()])),
            icon: const Icon(Icons.person_add),
            label: const Text('Add peasant'),
          ),
        ),
      ],
    );
  }

  Widget _peasantCard(BuildContext context, WidgetRef ref, DccSheet s, int i) {
    final p = s.peasants[i];
    void setP(DccPeasant np) {
      final list = [...s.peasants];
      list[i] = np;
      _save(ref, s.copyWith(peasants: list));
    }

    final titleStyle = p.alive
        ? null
        : const TextStyle(
            decoration: TextDecoration.lineThrough, color: Colors.grey);

    return Card(
      child: ExpansionTile(
        key: Key('dcc-peasant-$i'),
        title: Text(p.name.isEmpty ? 'Peasant ${i + 1}' : p.name,
            style: titleStyle),
        subtitle: Text('HP ${p.hp}  •  ${p.alive ? "alive" : "dead"}'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: [
          TextFormField(
            key: Key('dcc-peasant-$i-name'),
            initialValue: p.name,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (v) => setP(p.copyWith(name: v)),
          ),
          TextFormField(
            key: Key('dcc-peasant-$i-occupation'),
            initialValue: p.occupation,
            decoration: const InputDecoration(labelText: 'Occupation'),
            onChanged: (v) => setP(p.copyWith(occupation: v)),
          ),
          TextFormField(
            key: Key('dcc-peasant-$i-weapon'),
            initialValue: p.weapon,
            decoration: const InputDecoration(labelText: 'Weapon'),
            onChanged: (v) => setP(p.copyWith(weapon: v)),
          ),
          TextFormField(
            key: Key('dcc-peasant-$i-goods'),
            initialValue: p.tradeGoods,
            decoration: const InputDecoration(labelText: 'Trade goods'),
            onChanged: (v) => setP(p.copyWith(tradeGoods: v)),
          ),
          const SizedBox(height: 8),
          _stepper('dcc-peasant-$i-hp', 'HP', p.hp,
              min: 1, max: 8, onSet: (v) => setP(p.copyWith(hp: v))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final k in kDccStats)
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${kDccStatLabels[k]} (${_sign(p.mod(k))})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                _stepper('dcc-peasant-$i-$k', '', p.stats[k] ?? 10,
                    min: 3,
                    max: 18,
                    onSet: (v) => setP(p.copyWith(stats: {...p.stats, k: v}))),
              ]),
          ]),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            children: [
              TextButton(
                key: Key('dcc-peasant-$i-${p.alive ? "kill" : "revive"}'),
                onPressed: () => setP(p.copyWith(alive: !p.alive)),
                child: Text(p.alive ? 'Mark dead' : 'Mark alive'),
              ),
              if (p.alive)
                FilledButton(
                  key: Key('dcc-peasant-$i-graduate'),
                  onPressed: () => _graduateDialog(context, ref, s, i),
                  child: const Text('Graduate →'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _graduateDialog(
      BuildContext context, WidgetRef ref, DccSheet s, int i) async {
    var cls = 'Warrior';
    var align = 'Neutral';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Graduate to 1st level'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButton<String>(
              key: const Key('dcc-graduate-class'),
              value: cls,
              isExpanded: true,
              items: kDccClasses
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) => setState(() => cls = v ?? cls),
            ),
            DropdownButton<String>(
              key: const Key('dcc-graduate-alignment'),
              value: align,
              isExpanded: true,
              items: kDccAlignments
                  .map((x) => DropdownMenuItem(value: x, child: Text(x)))
                  .toList(),
              onChanged: (v) => setState(() => align = v ?? align),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                key: const Key('dcc-graduate-confirm'),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Graduate')),
          ],
        ),
      ),
    );
    if (ok == true) _save(ref, s.graduate(i, cls, align));
  }

  // ===================== LEVELED =====================

  Future<int?> _askDc(BuildContext context) {
    // A self-managing TextFormField (initialValue + onChanged into a closure)
    // avoids owning a TextEditingController — no leak, and nothing to dispose
    // mid-route-pop. Mirrors the closure-state pattern in _graduateDialog.
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

  Future<void> _rollSave(BuildContext context, DccSheet s, String key) async {
    final dc = await _askDc(context);
    if (dc == null || !context.mounted) return;
    final roll = Random().nextInt(20) + 1 + (s.saves[key] ?? 0);
    final pass = roll >= dc;
    _snack(context,
        '${kDccSaveLabels[key]}: $roll vs DC $dc — ${pass ? "Pass" : "Fail"}');
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
          _stepper('dcc-level', 'Level', s.level,
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
        TextFormField(
          key: const Key('dcc-lucky-sign'),
          initialValue: s.luckySign,
          decoration:
              const InputDecoration(labelText: 'Lucky Sign / Birth Augur'),
          onChanged: (v) => save(s.copyWith(luckySign: v)),
        ),
        const SizedBox(height: 12),
        sheetSection(context, 'Combat'),
        Wrap(spacing: 16, runSpacing: 8, children: [
          _stepper('dcc-hp', 'HP', s.currentHp,
              max: s.maxHp, onSet: (v) => save(s.copyWith(currentHp: v))),
          _stepper('dcc-maxhp', 'Max', s.maxHp,
              onSet: (v) => save(s.copyWith(maxHp: v))),
          _stepper('dcc-ac', 'AC', s.ac,
              min: 0, max: 30, onSet: (v) => save(s.copyWith(ac: v))),
          _stepper('dcc-atk', 'Atk', s.attackBonus,
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
            _stepper('dcc-save-$k', '', s.saves[k] ?? 0,
                min: -5,
                max: 20,
                onSet: (v) => save(s.copyWith(saves: {...s.saves, k: v}))),
            IconButton(
              key: Key('dcc-$k-roll'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.casino_outlined, size: 18),
              tooltip: 'Roll vs DC',
              onPressed: () => _rollSave(context, s, k),
            ),
          ]),
        const SizedBox(height: 12),
        if (s.hasDeedDie) _deedSection(context, ref, s),
        if (s.isCaster) _spellburnSection(context, ref, s),
        if (s.isCleric) _disapprovalSection(context, ref, s),
        sheetSection(context, 'Occupation'),
        TextFormField(
          key: const Key('dcc-occupation'),
          initialValue: s.occupation,
          decoration: const InputDecoration(labelText: 'Occupation'),
          onChanged: (v) => save(s.copyWith(occupation: v)),
        ),
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'dcc'),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('dcc-notes'),
          initialValue: s.notes,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Notes / Equipment'),
          onChanged: (v) => save(s.copyWith(notes: v)),
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
          _stepper('dcc-stat-$k', '', s.stats[k] ?? 10,
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
          icon: const Icon(Icons.casino_outlined, size: 18),
          label: const Text('Attack + Deed'),
          onPressed: () {
            final atk = Random().nextInt(20) + 1 + s.attackBonus;
            final deedSides = int.parse(s.deedDie.substring(1));
            final deed = Random().nextInt(deedSides) + 1;
            final ok = deed >= 3;
            _snack(context,
                'Attack: $atk, Deed: $deed — ${ok ? "Deed succeeds!" : "no deed"}');
          },
        ),
      ]),
      const SizedBox(height: 12),
    ]);
  }

  Widget _spellburnSection(BuildContext context, WidgetRef ref, DccSheet s) {
    final castStat = s.castingStat!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, 'Spellburn'),
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final k in s.burnableStats)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${kDccStatLabels[k]}  ${s.effectiveScore(k)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            _stepper('dcc-burn-$k', 'burn', s.burned(k),
                min: 0,
                max: 18,
                onSet: (v) => _save(ref, s.copyWith(burns: {...s.burns, k: v}))),
          ]),
      ]),
      Wrap(spacing: 8, runSpacing: 4,
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
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Spell check'),
          onPressed: () async {
            final dc = await _askDc(context);
            if (dc == null || !context.mounted) return;
            final sides = int.parse(s.actionDie.substring(1));
            final base = Random().nextInt(sides) +
                1 +
                s.level +
                dccAbilityMod(s.stats[castStat] ?? 10);
            final total = base + s.totalSpellburn;
            _snack(context,
                'Spell check: $total (base $base + ${s.totalSpellburn} spellburn) vs DC $dc — ${total >= dc ? "Success" : "Fail"}');
          },
        ),
      ]),
      const SizedBox(height: 12),
    ]);
  }

  Widget _disapprovalSection(BuildContext context, WidgetRef ref, DccSheet s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      sheetSection(context, 'Disapproval'),
      Wrap(spacing: 8, runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
        Text('Range 1–${s.disapprovalRange}'),
        IconButton(
          key: const Key('dcc-disapproval-inc'),
          icon: const Icon(Icons.add),
          tooltip: '+1 after failed casting',
          onPressed: () =>
              _save(ref, s.copyWith(disapprovalRange: s.disapprovalRange + 1)),
        ),
        TextButton(
          key: const Key('dcc-disapproval-reset'),
          onPressed: () => _save(ref, s.copyWith(disapprovalRange: 1)),
          child: const Text('Reset'),
        ),
        FilledButton.icon(
          key: const Key('dcc-disapproval-roll'),
          icon: const Icon(Icons.casino_outlined, size: 18),
          label: const Text('Check'),
          onPressed: () {
            final roll = Random().nextInt(20) + 1;
            final bad = roll <= s.disapprovalRange;
            _snack(context,
                'Disapproval check: $roll vs 1–${s.disapprovalRange} — ${bad ? "Disapproval!" : "Safe"}');
          },
        ),
      ]),
      const SizedBox(height: 12),
    ]);
  }
}
