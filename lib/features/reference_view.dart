import 'package:flutter/material.dart';
import '../engine/spell.dart';

/// Read-only glance card for a spell. Pure display; no state.
class SpellCard extends StatelessWidget {
  const SpellCard({super.key, required this.spell});
  final SpellEntry spell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final levelLabel = spell.level == 0 ? 'Cantrip' : 'Level ${spell.level}';
    final meta = [
      if (spell.castingTime.isNotEmpty) 'Casting: ${spell.castingTime}',
      if (spell.range.isNotEmpty) 'Range: ${spell.range}',
      if (spell.components.isNotEmpty) 'Components: ${spell.components}',
      if (spell.duration.isNotEmpty) 'Duration: ${spell.duration}',
    ].join('\n');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(spell.name, style: theme.textTheme.titleLarge),
          Text(
            [levelLabel, if (spell.school.isNotEmpty) spell.school].join(' · '),
            style: theme.textTheme.labelMedium!
                .copyWith(color: theme.colorScheme.primary),
          ),
          Wrap(spacing: 6, children: [
            if (spell.concentration) const Chip(label: Text('Concentration')),
            if (spell.ritual) const Chip(label: Text('Ritual')),
            if (spell.classes.isNotEmpty) Chip(label: Text(spell.classes.join(', '))),
          ]),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(meta, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Text(spell.description, style: theme.textTheme.bodyMedium),
          if (spell.higherLevels != null) ...[
            const SizedBox(height: 8),
            Text('At Higher Levels', style: theme.textTheme.titleSmall),
            Text(spell.higherLevels!, style: theme.textTheme.bodyMedium),
          ],
        ],
      ),
    );
  }
}
