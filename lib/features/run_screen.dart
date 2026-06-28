import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import 'sheet_widgets.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/play_context.dart';
import '../state/providers.dart';

/// Width at or above which the run-screen shows a two-column dashboard;
/// below it the panels stack in a single scrolling column.
const double kRunWideBreakpoint = 720;

/// Formats a duration in seconds as `M:SS` (or `H:MM:SS` past an hour).
/// Negative clamps to `0:00`.
String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final ss = (s % 60).toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

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
        const timers = _TimersPanel();
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
                    timers,
                    SizedBox(height: 12),
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
            timers,
            SizedBox(height: 12),
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

/// Real-time pacing: a turn stopwatch (resets each Next-turn) + a session
/// stopwatch, ticking only while an encounter is active. Widget-local +
/// ephemeral; the timer is cancelled on dispose.
class _TimersPanel extends ConsumerStatefulWidget {
  const _TimersPanel();
  @override
  ConsumerState<_TimersPanel> createState() => _TimersPanelState();
}

class _TimersPanelState extends ConsumerState<_TimersPanel> {
  Timer? _timer;
  int _session = 0;
  int _turn = 0;
  int? _lastRound;
  int? _lastTurnIndex;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensureTicking() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _session++;
        _turn++;
      });
    });
  }

  void _stopTicking() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final enc =
        ref.watch(encounterProvider).valueOrNull ?? const EncounterState();
    final active = enc.combatants.isNotEmpty;

    if (!active) {
      _stopTicking();
      _session = 0;
      _turn = 0;
      _lastRound = null;
      _lastTurnIndex = null;
      return const _Panel(
        k: Key('run-panel-timers'),
        title: 'Timers',
        child: Text('—', key: Key('run-timers-idle')),
      );
    }

    // Reset the turn stopwatch when the turn pointer / round changes.
    if (_lastRound != enc.round || _lastTurnIndex != enc.turnIndex) {
      _turn = 0;
      _lastRound = enc.round;
      _lastTurnIndex = enc.turnIndex;
    }
    // Start ticking after the frame (can't setState during build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureTicking();
    });

    return _Panel(
      k: const Key('run-panel-timers'),
      title: 'Timers',
      child: Text(
        'Turn ${formatDuration(_turn)} · Session ${formatDuration(_session)}',
        key: const Key('run-timers-readout'),
      ),
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
      rows.add(InkWell(
        key: Key('run-init-row-${c.id}'),
        onTap: (c.statBlock != null && !c.statBlock!.isEmpty)
            ? () => _showStatBlock(context, c)
            : null,
        child: Padding(
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
        ),
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

  void _showStatBlock(BuildContext context, Combatant c) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(c.name),
        content: SingleChildScrollView(
          child: StatBlockView(
            block: c.statBlock!,
            curHp: c.track?.current,
            maxHp: c.track?.max,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final journal =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final ctx = ref.watch(playContextProvider).valueOrNull;
    final scene = activeSceneEntry(journal, ctx?.activeSceneId);
    final chaos = ref.watch(crawlProvider).valueOrNull?.chaosFactor;

    return _Panel(
      k: const Key('run-panel-scene'),
      title: 'Scene',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (scene == null)
            const Text('No active scene.', key: Key('run-scene-empty'))
          else ...[
            Text(scene.title.isEmpty ? '(untitled scene)' : scene.title,
                style: theme.textTheme.titleSmall),
            if (scene.body.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(scene.body, style: theme.textTheme.bodySmall),
              ),
          ],
          if (chaos != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Text('Chaos $chaos', style: theme.textTheme.bodyMedium),
                const Spacer(),
                IconButton(
                  key: const Key('run-scene-chaos-dec'),
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: () =>
                      ref.read(crawlProvider.notifier).setChaos(chaos - 1),
                ),
                IconButton(
                  key: const Key('run-scene-chaos-inc'),
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () =>
                      ref.read(crawlProvider.notifier).setChaos(chaos + 1),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

class _DiceOraclePanel extends ConsumerWidget {
  const _DiceOraclePanel();

  void _roll(WidgetRef ref) {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final defaultOracle =
        ref.read(settingsProvider).valueOrNull?.defaultOracle ?? 'juice';
    final chaos = ref.read(crawlProvider).valueOrNull?.chaosFactor ?? 5;
    final GenResult g;
    final String tool;
    switch (defaultOracle) {
      case 'mythic':
        g = oracle.mythicFate(4, chaos);
        tool = 'mythic';
      case 'roll-high':
        g = oracle.rollHigh('d100', 3);
        tool = 'roll-high';
      default:
        g = fateCheckGenResult(oracle.fateCheck(Likelihood.normal));
        tool = 'fate-check';
    }
    ref.read(journalProvider.notifier).addResult(g.title, g.asText,
        sourceTool: tool, payload: g.toPayload());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch the oracle (not just read in _roll): an unwatched FutureProvider is
    // AsyncLoading on first read, so _roll would early-return. Watching keeps it
    // warm + gates the button until it resolves.
    final oracle = ref.watch(oracleProvider).valueOrNull;
    final aiReady = ref.watch(aiReadyProvider);
    // A Row (not Wrap): Wrap measures children with unbounded width, and a
    // Material button's internal _InputPadding throws "forces an infinite
    // width" under unbounded constraints (see the loose-constraints note in
    // encounter_screen.dart). Flexible keeps the labels from overflowing narrow.
    return _Panel(
      k: const Key('run-panel-dice'),
      title: 'Dice & oracle',
      child: Row(
        children: [
          Flexible(
            child: OutlinedButton(
              key: const Key('run-dice-roll'),
              onPressed: oracle == null ? null : () => _roll(ref),
              child: const Text('Roll oracle'),
            ),
          ),
          if (aiReady) ...[
            const SizedBox(width: 8),
            Flexible(
              child: OutlinedButton(
                key: const Key('run-dice-interpret'),
                onPressed: () => ref
                    .read(shellRouteProvider.notifier)
                    .goTo(Destination.journal),
                child: const Text('Interpret in journal'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CapturePanel extends ConsumerStatefulWidget {
  const _CapturePanel();
  @override
  ConsumerState<_CapturePanel> createState() => _CapturePanelState();
}

class _CapturePanelState extends ConsumerState<_CapturePanel> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _log() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    ref.read(journalProvider.notifier).addText(text);
    _ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    // The Log action is the field's suffix IconButton (not a Row with a flex
    // TextField + a Material text button): RenderFlex measures a non-flex
    // FilledButton with unbounded width and its _InputPadding throws "forces an
    // infinite width". An IconButton has a fixed size and is immune.
    return _Panel(
      k: const Key('run-panel-capture'),
      title: 'Capture',
      child: TextField(
        key: const Key('run-capture-field'),
        controller: _ctrl,
        decoration: InputDecoration(
          hintText: 'What just happened…',
          suffixIcon: IconButton(
            key: const Key('run-capture-log'),
            icon: const Icon(Icons.send),
            onPressed: _log,
          ),
        ),
        onSubmitted: (_) => _log(),
      ),
    );
  }
}
