import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Widget build(BuildContext context, WidgetRef ref) => const _Panel(
      k: Key('run-panel-initiative'), title: 'Initiative', child: SizedBox());
}

class _PartyPanel extends ConsumerWidget {
  const _PartyPanel();
  @override
  Widget build(BuildContext context, WidgetRef ref) => const _Panel(
      k: Key('run-panel-party'), title: 'Party', child: SizedBox());
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
