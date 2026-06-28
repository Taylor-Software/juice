import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../state/providers.dart';

/// Width at or above which the run-screen shows a two-column dashboard;
/// below it the panels stack in a single scrolling column.
const double kRunWideBreakpoint = 720;

/// The live GM run-screen: a read-and-act dashboard composing initiative,
/// party HP, the active scene, and quick dice/oracle over existing providers.
class RunScreen extends ConsumerWidget {
  const RunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      key: const Key('run-screen'),
      builder: (context, c) {
        final wide = c.maxWidth >= kRunWideBreakpoint;
        const initiative = _InitiativePanel();
        const party = _PartyPanel();
        const scene = _ScenePanel();
        const dice = _DiceOraclePanel();
        const capture = _CapturePanel();
        if (wide) {
          return const SingleChildScrollView(
            padding: EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(children: [
                    initiative,
                    SizedBox(height: 12),
                    party,
                  ]),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(children: [
                    scene,
                    SizedBox(height: 12),
                    dice,
                    SizedBox(height: 12),
                    capture,
                  ]),
                ),
              ],
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: const [
            initiative,
            SizedBox(height: 12),
            party,
            SizedBox(height: 12),
            scene,
            SizedBox(height: 12),
            dice,
            SizedBox(height: 12),
            capture,
          ],
        );
      },
    );
  }
}

/// Shared card chrome for a run-screen panel.
class _Panel extends StatelessWidget {
  const _Panel({required this.k, required this.title, required this.child});
  final Key k;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: k,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _InitiativePanel extends ConsumerWidget {
  const _InitiativePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final enc = ref.watch(encounterProvider).valueOrNull ?? const EncounterState();
    final notifier = ref.read(encounterProvider.notifier);
    final rows = <Widget>[];
    for (var i = 0; i < enc.combatants.length; i++) {
      final c = enc.combatants[i];
      final current = i == enc.turnIndex;
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: current
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.surfaceContainerHighest,
            child: Text('${c.initiative}',
                style: theme.textTheme.labelMedium),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(c.name,
                style: c.defeated
                    ? const TextStyle(decoration: TextDecoration.lineThrough)
                    : (current
                        ? TextStyle(color: theme.colorScheme.primary)
                        : null)),
          ),
          if (c.track != null)
            Text('${c.track!.current}/${c.track!.max}',
                style: theme.textTheme.bodySmall),
        ]),
      ));
    }

    return _Panel(
      k: const Key('run-panel-initiative'),
      title: 'Initiative · Round ${enc.round}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (enc.combatants.isEmpty)
            const Text('No encounter yet.', key: Key('run-init-empty'))
          else
            ...rows,
          const SizedBox(height: 8),
          Row(children: [
            Flexible(
              child: FilledButton.tonal(
                key: const Key('run-init-next'),
                onPressed:
                    enc.combatants.isEmpty ? null : () => notifier.nextTurn(),
                child: const Text('Next turn'),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: OutlinedButton(
                key: const Key('run-init-roll-all'),
                onPressed: enc.combatants.isEmpty
                    ? null
                    : () => notifier.rollInitiativeForAll(),
                child: const Text('Roll all init'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _PartyPanel extends ConsumerWidget {
  const _PartyPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(charactersProvider).valueOrNull ?? const <Character>[];
    final notifier = ref.read(charactersProvider.notifier);
    final party = all
        .where((c) =>
            c.role == CharacterRole.pc || c.role == CharacterRole.companion)
        .toList();

    return _Panel(
      k: const Key('run-panel-party'),
      title: 'Party',
      child: party.isEmpty
          ? const Text('No party yet.', key: Key('run-party-empty'))
          : Column(
              children: [
                for (final c in party)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: theme.textTheme.bodyMedium),
                            Builder(builder: (_) {
                              final hp = characterHpPool(c);
                              final cond = c.conditions.join(', ');
                              final parts = [
                                if (hp != null) '${hp.$1}/${hp.$2}',
                                if (cond.isNotEmpty) cond,
                              ];
                              return Text(parts.join(' · '),
                                  style: theme.textTheme.bodySmall);
                            }),
                          ],
                        ),
                      ),
                      IconButton(
                        key: Key('run-party-${c.id}-dec'),
                        icon: const Icon(Icons.remove, size: 18),
                        onPressed: () => notifier.replace(c.withHpDelta(-1)),
                      ),
                      IconButton(
                        key: Key('run-party-${c.id}-inc'),
                        icon: const Icon(Icons.add, size: 18),
                        onPressed: () => notifier.replace(c.withHpDelta(1)),
                      ),
                    ]),
                  ),
              ],
            ),
    );
  }
}

class _ScenePanel extends ConsumerWidget {
  const _ScenePanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _Panel(
      k: Key('run-panel-scene'), title: 'Scene', child: SizedBox());
}

class _DiceOraclePanel extends ConsumerWidget {
  const _DiceOraclePanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _Panel(
      k: Key('run-panel-dice'), title: 'Dice & oracle', child: SizedBox());
}

class _CapturePanel extends ConsumerWidget {
  const _CapturePanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _Panel(
      k: Key('run-panel-capture'), title: 'Capture', child: SizedBox());
}
