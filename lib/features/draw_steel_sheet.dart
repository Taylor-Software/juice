import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/sheet_rolls.dart';
import '../state/providers.dart';
import 'sheet_widgets.dart';

/// Facts-only Draw Steel sheet. Class/characteristic NAMES are authored
/// constants (non-copyrightable game-mechanic facts); all values are
/// player-editable. Published under the Draw Steel Creator License;
/// not affiliated with MCDM Productions, LLC.
class DrawSteelSheetView extends ConsumerWidget {
  const DrawSteelSheetView(
      {super.key, required this.character, required this.onBack});
  final Character character;
  final VoidCallback onBack;

  DrawSteelSheet get _s => character.drawSteel!;

  void _save(WidgetRef ref, DrawSteelSheet next) => ref
      .read(charactersProvider.notifier)
      .replace(character.copyWith(drawSteel: next));

  void _roll(BuildContext context, WidgetRef ref, String charKey) {
    final dice = ref.read(diceProvider);
    final r = drawSteelPowerRoll(
        dice.dN(10), dice.dN(10), _s.characteristics[charKey] ?? 0);
    final label = charKey[0].toUpperCase() + charKey.substring(1);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label: ${r.total} — ${r.outcome}'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = _s;
    return ListView(
      key: const Key('draw-steel-sheet'),
      padding: const EdgeInsets.all(12),
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        sheetNameHeader(context, ref, character,
            onBack: onBack, nameKey: 'draw-steel-name'),
        Text('Draw Steel', style: theme.textTheme.labelSmall),
        const SizedBox(height: 8),

        // ── Class + Ancestry + Level ─────────────────────────────────────────
        DropdownButton<String>(
          key: const Key('draw-steel-class'),
          isExpanded: true,
          value: kDrawSteelClasses.contains(s.className)
              ? s.className
              : kDrawSteelClasses.first,
          items: [
            for (final c in kDrawSteelClasses)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) =>
              v == null ? null : _save(ref, s.copyWith(className: v)),
        ),
        DebouncedTextField(
          key: const Key('draw-steel-ancestry'),
          initialValue: s.ancestry,
          label: 'Ancestry',
          onSave: (v) => _save(ref, s.copyWith(ancestry: v)),
        ),
        const SizedBox(height: 8),
        sheetStepper('draw-steel-level', 'Level', s.level,
            min: 1, max: 10, onSet: (v) => _save(ref, s.copyWith(level: v))),

        // ── Characteristics + Power Roll ────────────────────────────────────
        const SizedBox(height: 12),
        Text('Characteristics', style: theme.textTheme.titleMedium),
        const Text(
          'Power roll: 2d10 + characteristic → T1 (≤11) / T2 (12–16) / T3 (≥17)',
          style: TextStyle(fontSize: 11),
        ),
        const SizedBox(height: 4),
        for (final k in kDrawSteelCharacteristics)
          Row(children: [
            SizedBox(
              width: 80,
              child: Text(k[0].toUpperCase() + k.substring(1)),
            ),
            sheetStepper(
              'draw-steel-char-$k',
              '',
              s.characteristics[k] ?? 0,
              min: -5,
              max: 5,
              onSet: (v) => _save(ref,
                  s.copyWith(characteristics: {...s.characteristics, k: v})),
            ),
            const Spacer(),
            IconButton(
              key: Key('draw-steel-roll-$k'),
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.casino_outlined, size: 18),
              tooltip: 'Roll 2d10 + $k',
              onPressed: () => _roll(context, ref, k),
            ),
          ]),

        // ── Stamina ──────────────────────────────────────────────────────────
        const SizedBox(height: 12),
        Text('Stamina', style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          sheetStepper('draw-steel-stamina', 'Current', s.currentStamina,
              max: s.maxStamina,
              onSet: (v) => _save(ref, s.copyWith(currentStamina: v))),
          sheetStepper('draw-steel-max-stamina', 'Max', s.maxStamina,
              onSet: (v) => _save(ref, s.copyWith(maxStamina: v))),
        ]),

        // ── Recoveries ───────────────────────────────────────────────────────
        const SizedBox(height: 12),
        Text('Recoveries', style: theme.textTheme.titleMedium),
        Wrap(spacing: 16, runSpacing: 8, children: [
          sheetStepper('draw-steel-recoveries', 'Used', s.recoveries,
              onSet: (v) => _save(ref, s.copyWith(recoveries: v))),
          sheetStepper('draw-steel-max-recoveries', 'Max', s.maxRecoveries,
              onSet: (v) => _save(ref, s.copyWith(maxRecoveries: v))),
        ]),

        // ── Stability ────────────────────────────────────────────────────────
        const SizedBox(height: 12),
        sheetStepper('draw-steel-stability', 'Stability', s.stability,
            onSet: (v) => _save(ref, s.copyWith(stability: v))),

        // ── Heroic Resource ──────────────────────────────────────────────────
        const SizedBox(height: 12),
        Text(s.resourceLabel, style: theme.textTheme.titleMedium),
        sheetStepper('draw-steel-resource', '', s.heroicResource,
            onSet: (v) => _save(ref, s.copyWith(heroicResource: v))),

        // ── Conditions ───────────────────────────────────────────────────────
        const SizedBox(height: 12),
        conditionsSection(context, ref, character, 'draw-steel'),

        // ── Skills + Notes ───────────────────────────────────────────────────
        const SizedBox(height: 12),
        DebouncedTextField(
          key: const Key('draw-steel-skills'),
          initialValue: s.skills,
          maxLines: 3,
          label: 'Skills',
          onSave: (v) => _save(ref, s.copyWith(skills: v)),
        ),
        DebouncedTextField(
          key: const Key('draw-steel-notes'),
          initialValue: s.notes,
          maxLines: 3,
          label: 'Notes',
          onSave: (v) => _save(ref, s.copyWith(notes: v)),
        ),
      ],
    );
  }
}
