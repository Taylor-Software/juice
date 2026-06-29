import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../engine/oracle_interpreter.dart';
import 'oracle_interpretation_sheet.dart';
import 'reference_view.dart';
import 'sheet_widgets.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/play_context.dart';
import '../state/providers.dart';

/// Width at or above which the run-screen shows a two-column dashboard;
/// below it the panels stack in a single scrolling column.
const double kRunWideBreakpoint = 720;

String _oracleLabel(String id) => switch (id) {
      'mythic' => 'Mythic',
      'roll-high' => 'Roll High',
      _ => 'Juice',
    };

TextStyle _dimStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall!.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );

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
        const threads = _ThreadsRumorsPanel();
        const dice = _DiceOraclePanel();
        const capture = _CapturePanel();
        const reference = _ReferencePanel();
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
                    threads,
                    SizedBox(height: 12),
                    dice,
                    SizedBox(height: 12),
                    capture,
                    SizedBox(height: 12),
                    reference,
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
            threads,
            SizedBox(height: 12),
            dice,
            SizedBox(height: 12),
            capture,
            SizedBox(height: 12),
            reference,
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
      return _Panel(
        k: const Key('run-panel-timers'),
        title: 'Timers',
        child: Text(
          'No active encounter',
          key: const Key('run-timers-idle'),
          style: Theme.of(context)
              .textTheme
              .bodySmall!
              .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
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
            Text('No encounter yet.',
                key: const Key('run-init-empty'), style: _dimStyle(context))
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
          ? Text('No party yet.',
              key: const Key('run-party-empty'), style: _dimStyle(context))
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const Key('run-party-effect'),
                    icon: const Icon(Icons.bolt_outlined, size: 18),
                    label: const Text('Effect…'),
                    onPressed: () => _bulkEffect(context, ref, party),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _bulkEffect(
      BuildContext context, WidgetRef ref, List<Character> party) async {
    final result =
        await showDialog<({Set<String> ids, int hpDelta, List<String> conditions})>(
      context: context,
      builder: (_) => _RunEffectDialog(party: party),
    );
    if (result == null || result.ids.isEmpty) return;
    await ref.read(charactersProvider.notifier).applyPartyEffect(
          result.ids,
          hpDelta: result.hpDelta,
          addConditions: result.conditions,
        );
  }
}

/// Minimal bulk party-effect dialog for the run-screen: pick members, set an
/// HP delta and/or comma-separated conditions, apply via [applyPartyEffect].
class _RunEffectDialog extends StatefulWidget {
  const _RunEffectDialog({required this.party});
  final List<Character> party;
  @override
  State<_RunEffectDialog> createState() => _RunEffectDialogState();
}

class _RunEffectDialogState extends State<_RunEffectDialog> {
  final Set<String> _ids = {};
  final TextEditingController _hp = TextEditingController();
  final TextEditingController _cond = TextEditingController();

  @override
  void dispose() {
    _hp.dispose();
    _cond.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Party effect'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final c in widget.party)
            CheckboxListTile(
              key: Key('run-effect-target-${c.id}'),
              dense: true,
              value: _ids.contains(c.id),
              title: Text(c.name),
              onChanged: (on) => setState(() {
                if (on ?? false) {
                  _ids.add(c.id);
                } else {
                  _ids.remove(c.id);
                }
              }),
            ),
          TextField(
            key: const Key('run-effect-hp'),
            controller: _hp,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'HP delta (negative = damage)'),
          ),
          TextField(
            key: const Key('run-effect-conditions'),
            controller: _cond,
            decoration:
                const InputDecoration(labelText: 'Conditions (comma-separated)'),
          ),
        ]),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('run-effect-apply'),
          onPressed: () => Navigator.pop(context, (
            ids: _ids,
            hpDelta: int.tryParse(_hp.text.trim()) ?? 0,
            conditions: _cond.text
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList(),
          )),
          child: const Text('Apply'),
        ),
      ],
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
            Text('No active scene.',
                key: const Key('run-scene-empty'), style: _dimStyle(context))
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

/// Read-only glance at the live plot: open threads (+ unresolved rumors in GM
/// mode). Tapping a row jumps to the matching Track subtab.
class _ThreadsRumorsPanel extends ConsumerWidget {
  const _ThreadsRumorsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final threads = (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[])
        .where((t) => t.open)
        .toList();
    final gm = ref.watch(modeProvider) == CampaignMode.gm;
    final rumors = gm
        ? (ref.watch(rumorsProvider).valueOrNull ?? const <Rumor>[])
            .where((r) => !r.resolved)
            .toList()
        : const <Rumor>[];
    final nav = ref.read(shellRouteProvider.notifier);

    if (threads.isEmpty && rumors.isEmpty) {
      return _Panel(
        k: const Key('run-panel-threads'),
        title: 'Threads',
        child: Builder(
          builder: (ctx) => Text('No open threads.',
              key: const Key('run-threads-empty'), style: _dimStyle(ctx)),
        ),
      );
    }

    return _Panel(
      k: const Key('run-panel-threads'),
      title: 'Threads',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in threads.take(5))
            InkWell(
              key: Key('run-thread-${t.id}'),
              onTap: () =>
                  nav.goTo(Destination.track, subtab: 'threads'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                      child: Text(t.title, style: theme.textTheme.bodyMedium)),
                  Text('${t.progress}/${t.progressMax}',
                      style: theme.textTheme.bodySmall),
                ]),
              ),
            ),
          if (rumors.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('RUMORS',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            for (final r in rumors.take(5))
              InkWell(
                key: Key('run-rumor-${r.id}'),
                onTap: () => nav.goTo(Destination.track, subtab: 'rumors'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(r.text, style: theme.textTheme.bodySmall),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DiceOraclePanel extends ConsumerStatefulWidget {
  const _DiceOraclePanel();
  @override
  ConsumerState<_DiceOraclePanel> createState() => _DiceOraclePanelState();
}

class _DiceOraclePanelState extends ConsumerState<_DiceOraclePanel> {
  GenResult? _last;

  void _roll() {
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
    setState(() => _last = g);
  }

  /// Interpret the last roll inline (on-device LLM): seed from the result + the
  /// active scene + PC, run the shared interpretation sheet, log the reading.
  Future<void> _interpret() async {
    final g = _last;
    if (g == null) return;
    final journal =
        ref.read(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final ctx = ref.read(playContextProvider).valueOrNull;
    final scene = activeSceneEntry(journal, ctx?.activeSceneId);
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const CampaignSettings();
    final seed = OracleSeed(
      resultText: g.asText,
      genre: settings.genre,
      tone: settings.tone,
      sceneContext: scene == null
          ? ''
          : '${scene.title}\n${scene.body}'.trim(),
      activeCharacter: ref.read(activeCharacterLineProvider),
      systemPrimer: ref.read(systemPrimerProvider),
    );
    final accepted = await showModalBottomSheet<OracleInterpretation>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => OracleInterpretationSheet(
        seed: seed,
        onAccept: (card) => Navigator.pop(sheetCtx, card),
      ),
    );
    if (accepted == null || !mounted) return;
    await ref.read(journalProvider.notifier).addResult(
          'Oracle reading',
          '(${accepted.lens}): ${accepted.reading}',
          sourceTool: 'interpret',
        );
  }

  @override
  Widget build(BuildContext context) {
    // Watch the oracle (not just read in _roll): an unwatched FutureProvider is
    // AsyncLoading on first read, so _roll would early-return. Watching keeps it
    // warm + gates the button until it resolves.
    final oracle = ref.watch(oracleProvider).valueOrNull;
    final aiReady = ref.watch(aiReadyProvider);
    final defaultOracle =
        ref.watch(settingsProvider).valueOrNull?.defaultOracle ?? 'juice';
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
              onPressed: oracle == null ? null : _roll,
              child: Text('Roll ${_oracleLabel(defaultOracle)}'),
            ),
          ),
          if (aiReady && _last != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: OutlinedButton(
                key: const Key('run-dice-interpret'),
                onPressed: _interpret,
                child: const Text('Interpret'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReferencePanel extends StatelessWidget {
  const _ReferencePanel();
  @override
  Widget build(BuildContext context) {
    return const _Panel(
      k: Key('run-panel-reference'),
      title: 'Reference',
      child: SizedBox(height: 320, child: ReferenceView()),
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
