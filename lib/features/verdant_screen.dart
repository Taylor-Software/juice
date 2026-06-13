import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/verdant.dart';
import '../engine/verdant_data.dart';
import '../state/providers.dart';
import '../state/verdant.dart';

/// Solo journey tracker / play-aid for Verdant Hexcrawling. Owns the
/// Safety-Level / Encounter-Risk / Watch state and the dice; the player
/// resolves tasks. Terrain + POIs plot onto the shared hex map (mapProvider).
class VerdantScreen extends ConsumerWidget {
  const VerdantScreen({super.key, required this.oracle});

  final Oracle oracle;

  static const _watchNames = ['Morning', 'Afternoon', 'Evening', 'Night'];
  static const _stepNames = [
    'Round Starts — declare Watch',
    'Travel — move to next hex',
    'Task Assignment',
    'Task Execution — roll checks',
    'Time Passes — reveal hexes',
    'Danger! — roll encounter',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journeyAsync = ref.watch(verdantProvider);
    final dataAsync = ref.watch(verdantDataProvider);
    final mapAsync = ref.watch(mapProvider);

    return journeyAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Verdant error: $e')),
      data: (j) => dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Verdant data error: $e')),
        data: (data) => _body(context, ref, j, data, mapAsync.valueOrNull),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, VerdantJourney j,
      VerdantData data, MapState? map) {
    final theme = Theme.of(context);
    final notifier = ref.read(verdantProvider.notifier);

    // Manual loop to avoid firstOrNull (no collection dependency).
    HexCell? currentHex;
    if (map != null && map.currentHexCol != null && map.currentHexRow != null) {
      for (final h in map.hexes) {
        if (h.col == map.currentHexCol && h.row == map.currentHexRow) {
          currentHex = h;
          break;
        }
      }
    }

    return ListView(
      key: const Key('verdant-list'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // -- Header: day / watch / party / ER --
        Text('Day ${j.day}', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text('Watch', style: theme.textTheme.labelLarge),
        Wrap(
          spacing: 6,
          children: [
            for (var i = 0; i < 4; i++)
              ChoiceChip(
                key: Key('watch-${i + 1}'),
                label: Text('${_watchNames[i]}${i >= 2 ? ' 🌖' : ''}'),
                selected: j.watch == i + 1,
                onSelected: (_) => notifier.setWatch(i + 1),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _stepper(context, 'Party in party', j.partySize,
            (v) => notifier.setPartySize(v),
            min: 1, keyName: 'party'),
        _stepper(context, 'Independent followers (excluded from ER)',
            j.independentFollowers, (v) => notifier.setFollowers(v),
            min: 0, keyName: 'followers'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text('Encounter Risk: ${j.er}',
              key: const Key('verdant-er'),
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.primary)),
        ),
        const Divider(),

        // -- Pace + transport --
        Text('Travel pace', style: theme.textTheme.labelLarge),
        SegmentedButton<Pace>(
          segments: const [
            ButtonSegment(value: Pace.normal, label: Text('Normal')),
            ButtonSegment(value: Pace.slow, label: Text('Slow +2')),
            ButtonSegment(value: Pace.fast, label: Text('Fast −2')),
          ],
          selected: {j.pace},
          showSelectedIcon: false,
          onSelectionChanged: (s) => notifier.setPace(s.first),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Transport', style: theme.textTheme.labelLarge),
            const SizedBox(width: 12),
            Flexible(
              child: DropdownButton<String?>(
                key: const Key('verdant-transport'),
                isExpanded: true,
                value: j.transport,
                items: [
                  const DropdownMenuItem(value: null, child: Text('On foot')),
                  for (final m in data.transportModes)
                    DropdownMenuItem(value: m.key, child: Text(m.name)),
                ],
                onChanged: (v) => notifier.setTransport(v),
              ),
            ),
            if (j.transport == 'mount') ...[
              const SizedBox(width: 8),
              // Flexible bounds the button: a bare FilledButton as a non-flex
              // Row child next to the Flexible dropdown above is measured at
              // maxWidth:Infinity and throws under the loose tool host.
              Flexible(
                child: FilledButton.tonal(
                  key: const Key('verdant-rush'),
                  onPressed: j.rushUsedToday ? null : () => notifier.useRush(),
                  child: Text(j.rushUsedToday ? 'Rushed' : 'Rush'),
                ),
              ),
            ],
          ],
        ),
        const Divider(),

        // -- Safety dial --
        Text('Safety Level', style: theme.textTheme.labelLarge),
        Text('${j.safetyLevel >= 0 ? '+' : ''}${j.safetyLevel}',
            key: const Key('verdant-safety'),
            style: theme.textTheme.displaySmall),
        Text(_baselineHint(j),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: const Key('verdant-safer'),
              onPressed: () => notifier.applyDelta(data.safer),
              child: const Text('Safer +2'),
            ),
            FilledButton.tonal(
              key: const Key('verdant-riskier'),
              onPressed: () => notifier.applyDelta(data.riskier),
              child: const Text('Riskier −1'),
            ),
            OutlinedButton(
              key: const Key('verdant-deadly'),
              onPressed: () => notifier.applyDelta(data.deadly),
              child: const Text('Deadly −2'),
            ),
          ],
        ),
        const Divider(),

        // -- Round stepper --
        Text('Journey Round', style: theme.textTheme.labelLarge),
        Text('${j.step}. ${_stepNames[j.step - 1]}',
            key: const Key('verdant-step'), style: theme.textTheme.bodyLarge),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: const Key('verdant-advance'),
              onPressed: () => notifier.advanceStep(),
              child: const Text('Next step'),
            ),
            FilledButton.tonal(
              key: const Key('verdant-danger'),
              onPressed: () => _rollDanger(context, ref, j, data),
              child: const Text('Danger! (roll)'),
            ),
            OutlinedButton(
              key: const Key('verdant-new-round'),
              onPressed: () => notifier.newRound(),
              child: const Text('New round'),
            ),
            OutlinedButton(
              key: const Key('verdant-next-watch'),
              onPressed: () => notifier.nextWatch(),
              child: const Text('Next watch'),
            ),
          ],
        ),
        const Divider(),

        // -- Current hex (shared map) --
        Text('Current hex', style: theme.textTheme.labelLarge),
        Text(
          currentHex == null
              ? 'No hex yet — Travel to reveal one.'
              : '${_terrainName(data, currentHex.terrain)}'
                  '${currentHex.pois.isEmpty ? '' : ' · POIs: '
                      '${currentHex.pois.map((n) => data.pointsOfInterest[n - 1].name).join(', ')}'}',
          key: const Key('verdant-current-hex'),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.tonal(
              key: const Key('verdant-travel'),
              onPressed: () => _travel(ref),
              child: const Text('Travel (reveal hex)'),
            ),
            OutlinedButton(
              key: const Key('verdant-set-terrain'),
              onPressed: currentHex == null
                  ? null
                  : () => _setTerrain(context, ref, data),
              child: const Text('Set terrain'),
            ),
            OutlinedButton(
              key: const Key('verdant-explore'),
              onPressed: currentHex == null
                  ? null
                  : () => _explore(context, ref, data),
              child: const Text('Explore (roll POI)'),
            ),
          ],
        ),
        const Divider(),

        // -- Reference --
        _reference(context, data),
      ],
    );
  }

  String _baselineHint(VerdantJourney j) {
    final parts = <String>[];
    if (j.isNight) parts.add('−2 night');
    if (j.pace == Pace.slow) parts.add('+2 slow');
    if (j.pace == Pace.fast) parts.add('−2 fast');
    final base = parts.isEmpty ? '0' : parts.join(' ');
    return 'New-round baseline: $base = ${j.newRoundSafety}';
  }

  String _terrainName(VerdantData data, String? key) {
    if (key == null) return 'Unset terrain';
    return data.terrainByKey(key)?.name ?? key;
  }

  Future<void> _travel(WidgetRef ref) async {
    // Reveal the next hex (envRow placeholder; Verdant terrain overrides display).
    await ref
        .read(mapProvider.notifier)
        .revealHex(envRow: 1, lost: false, dice: oracle.dice);
  }

  Future<void> _explore(
      BuildContext context, WidgetRef ref, VerdantData data) async {
    final map = ref.read(mapProvider).valueOrNull;
    if (map?.currentHexCol == null) return;
    final poi = rollPoi(oracle.dice, data);
    await ref
        .read(mapProvider.notifier)
        .addHexPoi(map!.currentHexCol!, map.currentHexRow!, poi.n);
    await ref
        .read(journalProvider.notifier)
        .add('Verdant — Point of Interest', '${poi.name}. ${poi.text}');
    if (context.mounted) {
      _snack(context, 'Found: ${poi.name}');
    }
  }

  Future<void> _setTerrain(
      BuildContext context, WidgetRef ref, VerdantData data) async {
    final map = ref.read(mapProvider).valueOrNull;
    if (map?.currentHexCol == null) return;
    final key = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              key: const Key('terrain-roll'),
              leading: const Icon(Icons.casino_outlined),
              title: const Text('Roll random terrain (homebrew)'),
              onTap: () =>
                  Navigator.pop(ctx, rollTerrain(oracle.dice, data).key),
            ),
            const Divider(),
            for (final t in data.terrain)
              ListTile(
                key: Key('terrain-${t.key}'),
                title: Text(t.name),
                subtitle: Text(t.traits.map(data.traitName).join(' · ')),
                onTap: () => Navigator.pop(ctx, t.key),
              ),
          ],
        ),
      ),
    );
    if (key == null) return;
    await ref
        .read(mapProvider.notifier)
        .setHexTerrain(map!.currentHexCol!, map.currentHexRow!, key);
  }

  Future<void> _rollDanger(BuildContext context, WidgetRef ref,
      VerdantJourney j, VerdantData data) async {
    final r = rollEncounter(oracle.dice, safety: j.safetyLevel, er: j.er);
    final label = switch (r.outcome) {
      EncounterOutcome.danger => 'Encounter!',
      EncounterOutcome.benign => 'Benign encounter',
      EncounterOutcome.none => 'Clear',
    };
    var body = 'd12 ${r.d12} + safety ${j.safetyLevel} vs ER ${j.er} → $label';
    if (r.outcome != EncounterOutcome.none) {
      final qe = rollQuickEncounter(oracle.dice, data);
      body = '$body\n${qe.name}: ${qe.text}';
    }
    await ref
        .read(journalProvider.notifier)
        .add('Verdant — Day ${j.day} ${_watchNames[j.watch - 1]}', body);
    if (context.mounted) _snack(context, label);
  }

  void _snack(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _stepper(BuildContext context, String label, int value,
      void Function(int) onChanged,
      {required int min, required String keyName}) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: Key('$keyName-minus'),
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        Text('$value', key: Key('$keyName-value')),
        IconButton(
          key: Key('$keyName-plus'),
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => onChanged(value + 1),
        ),
      ],
    );
  }

  Widget _reference(BuildContext context, VerdantData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExpansionTile(
          key: const Key('ref-tasks'),
          title: const Text('Journey Tasks'),
          children: [
            for (final t in data.tasks)
              ListTile(
                dense: true,
                title: Text('${t.name}'
                    '${t.attribute == null ? '' : ' (${t.attribute})'}'),
                subtitle: Text('${t.types.join('/')} · '
                    '✓ ${t.success} / ✗ ${t.failure}'
                    '${t.dependency == null ? '' : ' · needs ${t.dependency}'}'),
              ),
          ],
        ),
        ExpansionTile(
          key: const Key('ref-terrain'),
          title: const Text('Terrain & Traits'),
          children: [
            for (final t in data.terrain)
              ListTile(
                dense: true,
                title: Text(t.name),
                subtitle: Text([
                  ...t.traits.map(data.traitName),
                  if (t.special != null) '★ ${t.special}',
                ].join(' · ')),
              ),
          ],
        ),
        ExpansionTile(
          key: const Key('ref-poi'),
          title: const Text('Points of Interest (d12)'),
          children: [
            for (final p in data.pointsOfInterest)
              ListTile(
                  dense: true,
                  leading: Text('${p.n}'),
                  title: Text(p.name),
                  subtitle: Text(p.text)),
          ],
        ),
        ExpansionTile(
          key: const Key('ref-quick'),
          title: const Text('Quick Encounters (d10)'),
          children: [
            for (final q in data.quickEncounters)
              ListTile(
                  dense: true,
                  leading: Text('${q.n}'),
                  title: Text(q.name),
                  subtitle: Text(q.text)),
          ],
        ),
        ExpansionTile(
          key: const Key('ref-transport'),
          title: const Text('Modes of Transportation'),
          children: [
            for (final m in data.transportModes)
              ListTile(
                  dense: true, title: Text(m.name), subtitle: Text(m.text)),
            for (final f in data.terrainFeatures)
              ListTile(
                  dense: true, title: Text(f.name), subtitle: Text(f.text)),
          ],
        ),
      ],
    );
  }
}
