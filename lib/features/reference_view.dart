import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/content_registry.dart';
import '../engine/models.dart';
import '../engine/spell.dart';
import '../state/providers.dart';
import 'quick_ref_view.dart';
import 'sheet_widgets.dart';

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

class ReferenceView extends ConsumerStatefulWidget {
  const ReferenceView({
    super.key,
    this.initialQuery = '',
    this.initialType = ContentType.all,
  });
  final String initialQuery;
  final ContentType initialType;

  @override
  ConsumerState<ReferenceView> createState() => _ReferenceViewState();
}

class _ReferenceViewState extends ConsumerState<ReferenceView> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialQuery);
  late ContentType _type = widget.initialType;
  String? _system; // null = all systems

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRules = _type == ContentType.rules;
    final monsters = isRules
        ? const <Creature>[]
        : ref.watch(contentMonstersProvider).valueOrNull ?? const <Creature>[];
    final spells = isRules
        ? const <SpellEntry>[]
        : ref.watch(contentSpellsProvider).valueOrNull ?? const <SpellEntry>[];
    final results = isRules
        ? const ContentResults(monsters: [], spells: [])
        : searchContent(
            query: _ctrl.text,
            filter: _type,
            system: _system,
            monsters: monsters,
            spells: spells,
          );
    return Column(
      children: [
        if (!isRules)
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              key: const Key('reference-search'),
              controller: _ctrl,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search spells & monsters',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
        SegmentedButton<ContentType>(
          segments: const [
            ButtonSegment(value: ContentType.all, label: Text('All')),
            ButtonSegment(value: ContentType.monsters, label: Text('Monsters')),
            ButtonSegment(value: ContentType.spells, label: Text('Spells')),
            ButtonSegment(value: ContentType.rules, label: Text('Rules')),
          ],
          selected: {_type},
          onSelectionChanged: (s) => setState(() => _type = s.first),
        ),
        if (isRules)
          const Expanded(child: QuickRefView(useProvider: true))
        else
          Expanded(
            // Spells first, then monsters. Lazy-built so off-screen tiles aren't
            // constructed on every keystroke (the full list is ~400+ entries).
            child: ListView.builder(
              itemCount: results.spells.length + results.monsters.length,
              itemBuilder: (context, i) {
                if (i < results.spells.length) {
                  final s = results.spells[i];
                  return ListTile(
                    key: Key('reference-spell-${s.id}'),
                    dense: true,
                    leading: const Icon(Icons.auto_fix_high),
                    title: Text(s.name),
                    subtitle: Text(s.level == 0
                        ? 'Cantrip · ${s.school}'
                        : 'Lvl ${s.level} · ${s.school}'),
                    onTap: () => _glance(context, spell: s),
                  );
                }
                final m = results.monsters[i - results.spells.length];
                return ListTile(
                  key: Key('reference-monster-${m.id}'),
                  dense: true,
                  leading: const Icon(Icons.pets),
                  title: Text(m.name),
                  subtitle: Text([
                    if (m.statBlock.cr != null) 'CR ${m.statBlock.cr}',
                    if (m.maxHp > 0) 'HP ${m.maxHp}',
                  ].join(' · ')),
                  onTap: () => _glance(context, monster: m),
                );
              },
            ),
          ),
        const _AttributionFooter(),
      ],
    );
  }

  void _glance(BuildContext context, {SpellEntry? spell, Creature? monster}) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 360,
            child: spell != null
                ? SpellCard(spell: spell)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(monster!.name,
                          style: Theme.of(context).textTheme.titleLarge),
                      const SizedBox(height: 8),
                      Flexible(
                        child: SingleChildScrollView(
                          child: StatBlockView(
                            block: monster.statBlock,
                            maxHp: monster.maxHp > 0 ? monster.maxHp : null,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _AttributionFooter extends StatelessWidget {
  const _AttributionFooter();
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        key: const Key('reference-sources'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Sources & licenses'),
            content: SingleChildScrollView(
              child: Text(kContentAttributions.values.join('\n\n')),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
        child: const Text('Sources & licenses'),
      ),
    );
  }
}
