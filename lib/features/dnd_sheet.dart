import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

String _fmt(int n) => n >= 0 ? '+$n' : '$n';

/// Bespoke D&D 5e character sheet (P1). Renders for characters whose
/// [Character.dnd] is non-null; edits persist via charactersProvider.
class DndSheetView extends ConsumerWidget {
  const DndSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  DndSheet get _s => character.dnd!;
  void _save(WidgetRef ref, DndSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(dnd: next));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('dnd-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          IconButton(
            key: const Key('sheet-back'),
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(character.name,
                style: theme.textTheme.titleLarge,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Rename',
            onPressed: () async {
              final name = await renameDialog(context,
                  nameKey: 'dnd-name', current: character.name);
              if (name != null) {
                await ref
                    .read(charactersProvider.notifier)
                    .replace(character.copyWith(name: name));
              }
            },
          ),
        ]),
        Row(children: [
          Expanded(
            child: DropdownButton<String>(
              key: const Key('dnd-class'),
              value:
                  kDndClasses.contains(s.className) ? s.className : 'Fighter',
              isExpanded: true,
              items: [
                for (final c in kDndClasses)
                  DropdownMenuItem(value: c, child: Text(c)),
              ],
              onChanged: (c) =>
                  c == null ? null : _save(ref, s.copyWith(className: c)),
            ),
          ),
          const SizedBox(width: 12),
          const Text('Level'),
          intStepper(
              prefix: 'dnd',
              fieldKey: 'level',
              value: s.level,
              onSet: (v) => _save(ref, s.copyWith(level: v))),
        ]),
        Text(
            'Proficiency Bonus ${_fmt(s.proficiencyBonus)}  ·  Hit die d${s.hitDie}',
            style: theme.textTheme.labelSmall),
        sheetSection(context, 'Ability Scores'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in kDndAbilities) _abilityBox(ref, s, a),
        ]),
        sheetSection(context, 'Combat'),
        Row(children: [
          const SizedBox(width: 64, child: Text('AC')),
          intStepper(
              prefix: 'dnd',
              fieldKey: 'ac',
              value: s.ac,
              onSet: (v) => _save(ref, s.copyWith(ac: v))),
          const Spacer(),
          Text('Init ${_fmt(s.initiative)}   Speed ${s.speed}',
              style: theme.textTheme.bodySmall),
        ]),
        Row(children: [
          const SizedBox(width: 64, child: Text('HP')),
          intStepper(
              prefix: 'dnd',
              fieldKey: 'hp-cur',
              value: s.currentHp,
              onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          Text(' / ${s.maxHp}'),
          const SizedBox(width: 12),
          const Text('Max'),
          intStepper(
              prefix: 'dnd',
              fieldKey: 'hp-max',
              value: s.maxHp,
              onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
        ]),
        Row(children: [
          const SizedBox(width: 64, child: Text('Hit dice')),
          intStepper(
              prefix: 'dnd',
              fieldKey: 'hd',
              value: s.hitDiceRemaining,
              onSet: (v) => _save(ref, s.copyWith(hitDiceRemaining: v))),
          Text(' / ${s.level} (d${s.hitDie})'),
        ]),
        sheetSection(context, 'Saving Throws'),
        for (final a in kDndAbilities) _saveRow(ref, s, a),
        sheetSection(context, 'Skills'),
        for (final sk in kDndSkills) _skillRow(ref, s, sk),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Passive Perception ${s.passivePerception}',
              style: Theme.of(context).textTheme.bodySmall),
        ),
        sheetSection(context, 'Conditions'),
        toggleChips(
          chipPrefix: 'dnd-cond',
          labels: kDndConditions,
          selected: s.conditions,
          onChanged: (c) => _save(ref, s.copyWith(conditions: c)),
        ),
        Row(children: [
          const SizedBox(width: 96, child: Text('Exhaustion')),
          intStepper(
              prefix: 'dnd',
              fieldKey: 'exhaustion',
              value: s.exhaustionLevel,
              onSet: (v) => _save(ref, s.copyWith(exhaustionLevel: v))),
          Text('/ 6', style: Theme.of(context).textTheme.bodySmall),
        ]),
        Row(children: [
          const SizedBox(width: 96, child: Text('Death saves')),
          const Text('✓'),
          intStepper(
              prefix: 'dnd',
              fieldKey: 'death-ok',
              value: s.deathSaveSuccesses,
              onSet: (v) => _save(ref, s.copyWith(deathSaveSuccesses: v))),
          const SizedBox(width: 8),
          const Text('✗'),
          intStepper(
              prefix: 'dnd',
              fieldKey: 'death-bad',
              value: s.deathSaveFailures,
              onSet: (v) => _save(ref, s.copyWith(deathSaveFailures: v))),
        ]),
        CheckboxListTile(
          key: const Key('dnd-inspiration'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: s.inspiration,
          title: const Text('Inspiration'),
          onChanged: (on) => _save(ref, s.copyWith(inspiration: on ?? false)),
        ),
        sheetSection(context, 'Features & Traits'),
        TextFormField(
          key: const Key('dnd-features'),
          initialValue: s.featuresText,
          maxLines: null,
          decoration: const InputDecoration(
              hintText: 'Class features, racial traits, feats, attacks…'),
          onChanged: (v) => _save(ref, s.copyWith(featuresText: v)),
        ),
        sheetSection(context, 'Notes'),
        Text(character.note.isEmpty ? '—' : character.note),
      ],
    );
  }

  Widget _abilityBox(WidgetRef ref, DndSheet s, String a) => SizedBox(
        width: 110,
        child: Column(children: [
          Text(kDndAbilityLabels[a]!, style: const TextStyle(fontSize: 11)),
          Text(_fmt(s.abilityMod(a)),
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(
              key: Key('dnd-ability-$a-minus'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.remove, size: 16),
              onPressed: () => _save(ref,
                  s.copyWith(abilities: {...s.abilities, a: s.score(a) - 1})),
            ),
            Text('${s.score(a)}'),
            IconButton(
              key: Key('dnd-ability-$a-plus'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 16),
              onPressed: () => _save(ref,
                  s.copyWith(abilities: {...s.abilities, a: s.score(a) + 1})),
            ),
          ]),
        ]),
      );

  Widget _saveRow(WidgetRef ref, DndSheet s, String a) {
    final prof = s.saveProficiencies.contains(a);
    return Row(children: [
      Checkbox(
        key: Key('dnd-save-$a'),
        value: prof,
        onChanged: (on) {
          final next = {...s.saveProficiencies};
          if (on ?? false) {
            next.add(a);
          } else {
            next.remove(a);
          }
          _save(ref, s.copyWith(saveProficiencies: next));
        },
      ),
      SizedBox(width: 48, child: Text(kDndAbilityLabels[a]!)),
      Text(_fmt(s.saveBonus(a))),
    ]);
  }

  Widget _skillRow(WidgetRef ref, DndSheet s, (String, String, String) sk) {
    final (id, label, ability) = sk;
    final prof = s.skillProficiencies.contains(id);
    final exp = s.skillExpertise.contains(id);
    return Row(children: [
      Checkbox(
        key: Key('dnd-skill-$id-prof'),
        value: prof,
        onChanged: (on) {
          final p = {...s.skillProficiencies};
          final e = {...s.skillExpertise};
          if (on ?? false) {
            p.add(id);
          } else {
            p.remove(id);
            e.remove(id); // expertise requires proficiency
          }
          _save(ref, s.copyWith(skillProficiencies: p, skillExpertise: e));
        },
      ),
      Checkbox(
        key: Key('dnd-skill-$id-exp'),
        value: exp,
        onChanged: (on) {
          final p = {...s.skillProficiencies};
          final e = {...s.skillExpertise};
          if (on ?? false) {
            e.add(id);
            p.add(id); // expertise implies proficiency
          } else {
            e.remove(id);
          }
          _save(ref, s.copyWith(skillProficiencies: p, skillExpertise: e));
        },
      ),
      Expanded(child: Text('$label (${kDndAbilityLabels[ability]})')),
      Text(_fmt(s.skillBonus(id))),
    ]);
  }
}
