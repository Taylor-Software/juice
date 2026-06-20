import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// Bespoke lean Shadowdark character sheet. Renders for characters whose
/// [Character.shadowdark] is non-null; edits persist via charactersProvider.
class ShadowdarkSheetView extends ConsumerWidget {
  const ShadowdarkSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  ShadowdarkSheet get _s => character.shadowdark!;
  void _save(WidgetRef ref, ShadowdarkSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(shadowdark: next));

  Widget _dropdown(WidgetRef ref, String key, List<String> options,
          String value, ValueChanged<String> onSet) =>
      DropdownButton<String>(
        key: Key(key),
        value: options.contains(value) ? value : options.first,
        isExpanded: true,
        items: [
          for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
        ],
        onChanged: (v) => v == null ? null : onSet(v),
      );

  Widget _freeform(WidgetRef ref, String key, String label, String value,
          ValueChanged<String> onSet) =>
      TextFormField(
        key: Key(key),
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        onChanged: onSet,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('shadowdark-sheet'),
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
                  nameKey: 'sd-name', current: character.name);
              if (name != null) {
                await ref
                    .read(charactersProvider.notifier)
                    .replace(character.copyWith(name: name));
              }
            },
          ),
        ]),
        Text('Shadowdark', style: theme.textTheme.labelSmall),
        Row(children: [
          Expanded(
              child: _dropdown(ref, 'sd-class', kShadowdarkClasses, s.className,
                  (v) => _save(ref, s.copyWith(className: v)))),
          const SizedBox(width: 8),
          const Text('Level'),
          intStepper(
              prefix: 'sd',
              fieldKey: 'level',
              value: s.level,
              onSet: (v) => _save(ref, s.copyWith(level: v))),
        ]),
        Row(children: [
          Expanded(
              child: _dropdown(ref, 'sd-ancestry', kShadowdarkAncestries,
                  s.ancestry, (v) => _save(ref, s.copyWith(ancestry: v)))),
          const SizedBox(width: 8),
          Expanded(
              child: _dropdown(ref, 'sd-alignment', kShadowdarkAlignments,
                  s.alignment, (v) => _save(ref, s.copyWith(alignment: v)))),
        ]),
        _freeform(ref, 'sd-title', 'Title', s.title,
            (v) => _save(ref, s.copyWith(title: v))),
        if (s.className == 'Priest')
          _freeform(ref, 'sd-deity', 'Deity', s.deity,
              (v) => _save(ref, s.copyWith(deity: v))),
        _freeform(ref, 'sd-background', 'Background', s.background,
            (v) => _save(ref, s.copyWith(background: v))),
        Text('Hit die d${s.hitDie}', style: theme.textTheme.labelSmall),
        sheetSection(context, 'Ability Scores'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final a in kDndAbilities) _abilityBox(ref, s, a),
        ]),
        sheetSection(context, 'Combat'),
        // Wrap (not Row): steppers reflow to a second line on a narrow phone
        // instead of throwing a RenderFlex overflow.
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          const SizedBox(width: 64, child: Text('AC')),
          intStepper(
              prefix: 'sd',
              fieldKey: 'ac',
              value: s.ac,
              onSet: (v) => _save(ref, s.copyWith(ac: v))),
          const SizedBox(width: 12),
          const Text('XP'),
          intStepper(
              prefix: 'sd',
              fieldKey: 'xp',
              value: s.xp,
              onSet: (v) => _save(ref, s.copyWith(xp: v))),
        ]),
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          const SizedBox(width: 64, child: Text('HP')),
          intStepper(
              prefix: 'sd',
              fieldKey: 'hp-cur',
              value: s.currentHp,
              onSet: (v) => _save(ref, s.copyWith(currentHp: v))),
          Text(' / ${s.maxHp}'),
          const SizedBox(width: 8),
          const Text('Max'),
          intStepper(
              prefix: 'sd',
              fieldKey: 'hp-max',
              value: s.maxHp,
              onSet: (v) => _save(ref, s.copyWith(maxHp: v))),
        ]),
        sheetSection(context, 'Gear & Luck'),
        Row(children: [
          const SizedBox(width: 96, child: Text('Gear slots')),
          intStepper(
              prefix: 'sd',
              fieldKey: 'gear',
              value: s.gearSlotsUsed,
              onSet: (v) => _save(ref, s.copyWith(gearSlotsUsed: v))),
          Text(' / ${s.gearSlotCapacity}'),
        ]),
        CheckboxListTile(
          key: const Key('sd-luck'),
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: s.luckToken,
          title: const Text('Luck token'),
          onChanged: (on) => _save(ref, s.copyWith(luckToken: on ?? false)),
        ),
        sheetSection(context, 'Talents'),
        _freeform(ref, 'sd-talents', 'Talents (rolled boons)', s.talentsText,
            (v) => _save(ref, s.copyWith(talentsText: v))),
        if (s.isCaster) ...[
          sheetSection(context, 'Spellcasting'),
          Text(
              'Casts on d20 + ${kDndAbilityLabels[s.castingAbility]} (${fmtSigned(s.castingMod!)})'
              ' vs DC 10 + spell tier',
              style: theme.textTheme.bodySmall),
          _freeform(ref, 'sd-spells', 'Spells known', s.spellsText,
              (v) => _save(ref, s.copyWith(spellsText: v))),
        ],
        sheetSection(context, 'Notes'),
        Text(character.note.isEmpty ? '—' : character.note),
      ],
    );
  }

  Widget _abilityBox(WidgetRef ref, ShadowdarkSheet s, String a) => abilityBox(
        prefix: 'sd',
        abilityKey: a,
        label: kDndAbilityLabels[a]!,
        modText: fmtSigned(s.abilityMod(a)),
        score: s.score(a),
        onMinus: () => _save(
            ref, s.copyWith(abilities: {...s.abilities, a: s.score(a) - 1})),
        onPlus: () => _save(
            ref, s.copyWith(abilities: {...s.abilities, a: s.score(a) + 1})),
      );
}
