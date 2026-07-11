import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/models.dart';
import '../engine/next_beat.dart';
import '../engine/oracle_interpreter.dart';
import '../engine/solo_oracle.dart';
import '../engine/tally.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'generate_sheet.dart';
import 'journal_screen.dart';

/// Ephemeral loop-UI state that survives Track-tab navigation (the [LoopBar]
/// State is disposed when the subtab is switched away). These are file-private,
/// NOT autoDispose, NOT persisted — app-global lifetime, reset on app restart.
final _loopOddsProvider =
    StateProvider<SoloLikelihood>((_) => SoloLikelihood.even);
final _loopLastProvider = StateProvider<SoloYesNo?>((_) => null);
final _loopQuestionProvider = StateProvider<String>((_) => '');
final _loopCaptureProvider = StateProvider<String>((_) => '');
final _loopTallyRollProvider = StateProvider<String?>((_) => null);
final _loopBeatOpenProvider = StateProvider<bool>((_) => false);
final _loopInterpretedProvider = StateProvider<bool>((_) => false);
final _loopInterpretSeedProvider = StateProvider<OracleSeed?>((_) => null);

/// The "Solo Loop" controls bar: a checklist that wires the active scene, a d10
/// yes/no oracle, the inspire sheet, success-tally tasks, and journal logging.
class LoopBar extends ConsumerStatefulWidget {
  const LoopBar({super.key});
  @override
  ConsumerState<LoopBar> createState() => _LoopBarState();
}

class _LoopBarState extends ConsumerState<LoopBar> {
  final _capture = TextEditingController();
  final _taskName = TextEditingController();
  final _question = TextEditingController();
  final _captureFocus = FocusNode();
  (String, int, int) _preset = kTallyPresets[1]; // Minor challenge 3(6)

  @override
  void initState() {
    super.initState();
    // Re-seed the controllers from the nav-surviving providers (the State is
    // disposed/recreated on tab switch, the providers persist the text).
    _capture.text = ref.read(_loopCaptureProvider);
    _question.text = ref.read(_loopQuestionProvider);
  }

  @override
  void dispose() {
    _capture.dispose();
    _taskName.dispose();
    _question.dispose();
    _captureFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = ref.watch(journalProvider).valueOrNull ?? const [];
    final ctx = ref.watch(playContextProvider).valueOrNull;
    final scene = activeSceneEntry(journal, ctx?.activeSceneId);
    final threads = ref.watch(threadsProvider).valueOrNull ?? const [];
    final tallied = threads.where((t) => t.tally != null).toList();
    final aiReady = ref.watch(interpretReadyProvider);
    final odds = ref.watch(_loopOddsProvider);
    final last = ref.watch(_loopLastProvider);
    final tallyRoll = ref.watch(_loopTallyRollProvider);
    final interpreted = ref.watch(_loopInterpretedProvider);
    final beatOpen = ref.watch(_loopBeatOpenProvider);
    final actions = nextBeatActions(
      hasScene: scene != null,
      hasRecentAsk: last != null,
      interpretDone: interpreted,
      aiReady: aiReady,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // A themed FilledButton has minimumSize width == infinity
          // (Size.fromHeight in theme.dart), so it must NOT sit in a width-
          // unbounding parent like Row/Wrap (which would force infinite width).
          // As a direct Padding child it clamps to the available width — a
          // full-width primary "Next beat" button, which is the intended look.
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: FilledButton.icon(
            key: const Key('loop-next-beat'),
            icon: const Icon(Icons.bolt),
            // Surfaces the top recommended action so the button never reads
            // as a no-op (stranger-test audit S4): first tap reveals the
            // action row, subsequent taps RUN the leading action.
            label: Text(beatOpen && actions.isNotEmpty
                ? 'Next beat — ${_beatLabel(actions.first)}'
                : 'Next beat'),
            onPressed: () {
              if (!beatOpen) {
                ref.read(_loopBeatOpenProvider.notifier).state = true;
              } else if (actions.isNotEmpty) {
                _runBeat(actions.first);
              }
            },
          ),
        ),
        if (beatOpen)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final a in actions)
                OutlinedButton.icon(
                  key: Key('beat-${a.name}'),
                  icon: Icon(_beatIcon(a)),
                  label: Text(_beatLabel(a)),
                  onPressed: () => _runBeat(a),
                ),
            ]),
          ),
        if (ref.watch(_loopInterpretSeedProvider) case final seed?)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: _InterpretCard(
              key: const Key('loop-interpret-card'),
              seed: seed,
              onDone: () {
                ref.read(_loopInterpretSeedProvider.notifier).state = null;
                ref.read(_loopInterpretedProvider.notifier).state = true;
              },
            ),
          ),
        ExpansionTile(
          key: const Key('loop-steps'),
          title: const Text('Steps'),
          initiallyExpanded: false,
          // Stretch, or the default (center) alignment shrinks each step Card
          // to its content width and floats it in dead gutters.
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          children: [
            _step(context, '1 · Scene',
                scene == null ? 'No scene yet.' : scene.title, [
              FilledButton.tonalIcon(
                key: const Key('loop-new-scene'),
                // Natural width in the _step Wrap (the app-wide filledButtonTheme
                // full-width Size.fromHeight minimumSize would otherwise stretch
                // it to the whole run).
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                icon: const Icon(Icons.add),
                label: const Text('New scene'),
                onPressed: _newScene,
              ),
            ]),
            _step(context, '2 · Ask a question',
                'Type your question, pick the odds, roll a d10.', [
              SizedBox(
                width: 360,
                child: TextField(
                  key: const Key('loop-ask-question'),
                  controller: _question,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'e.g. Is the bridge guarded?',
                  ),
                  onChanged: (v) =>
                      ref.read(_loopQuestionProvider.notifier).state = v,
                  onSubmitted: (_) => _ask(),
                ),
              ),
              SegmentedButton<SoloLikelihood>(
                segments: const [
                  ButtonSegment(
                      value: SoloLikelihood.unlikely, label: Text('Unlikely')),
                  ButtonSegment(
                      value: SoloLikelihood.even, label: Text('Even')),
                  ButtonSegment(
                      value: SoloLikelihood.likely, label: Text('Likely')),
                ],
                selected: {odds},
                onSelectionChanged: (s) =>
                    ref.read(_loopOddsProvider.notifier).state = s.first,
              ),
              FilledButton(
                key: const Key('loop-ask'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _ask,
                child: const Text('Ask'),
              ),
              if (last != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${last.phrase} (d10=${last.roll})',
                    key: const Key('loop-ask-result'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
            ]),
            _step(context, '3 · Inspire', 'Open the generators for a prompt.', [
              OutlinedButton.icon(
                key: const Key('loop-inspire'),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Inspire'),
                onPressed: () => showGenerateSheet(context),
              ),
            ]),
            _step(
              context,
              '4 · Tasks',
              tallied.isEmpty ? 'No tasks yet — name one below.' : null,
              [
                for (final t in tallied)
                  ListTile(
                    key: Key('loop-task-${t.id}'),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.title),
                    subtitle: Text(t.tally!.won
                        ? 'Success'
                        : t.tally!.failed
                            ? 'Failed'
                            : t.tally!.label),
                    trailing: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          IconButton(
                            key: Key('loop-task-dec-${t.id}'),
                            icon: const Icon(Icons.remove),
                            onPressed: () => ref
                                .read(threadsProvider.notifier)
                                .adjustTally(t.id, -1),
                          ),
                          IconButton(
                            key: Key('loop-task-inc-${t.id}'),
                            icon: const Icon(Icons.add),
                            onPressed: () => ref
                                .read(threadsProvider.notifier)
                                .adjustTally(t.id, 1),
                          ),
                          IconButton(
                            key: Key('loop-task-roll-${t.id}'),
                            icon: const Icon(Icons.casino_outlined),
                            tooltip: 'Tally roll',
                            onPressed: () => _tallyRoll(t),
                          ),
                        ]),
                  ),
                if (tallyRoll != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      tallyRoll,
                      key: const Key('loop-tally-roll-result'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('loop-task-name'),
                          controller: _taskName,
                          decoration: const InputDecoration(
                            hintText: 'New task name…',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _newTask(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 150,
                        child: DropdownButton<(String, int, int)>(
                          key: const Key('loop-task-preset'),
                          value: _preset,
                          isExpanded: true,
                          items: [
                            for (final p in kTallyPresets)
                              DropdownMenuItem(
                                value: p,
                                child: Text('${p.$1} ${p.$2}(${p.$3})',
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (p) =>
                              setState(() => _preset = p ?? _preset),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: FilledButton.tonalIcon(
                      key: const Key('loop-task-new'),
                      icon: const Icon(Icons.add_task),
                      label: const Text('Track it'),
                      onPressed: _newTask,
                    ),
                  ),
                ),
              ],
            ),
            _step(context, '5 · Capture', null, [
              SizedBox(
                width: double.infinity,
                child: TextField(
                  key: const Key('loop-capture-field'),
                  controller: _capture,
                  focusNode: _captureFocus,
                  decoration: InputDecoration(
                    hintText: 'Quick note to the journal…',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      key: const Key('loop-capture-send'),
                      icon: const Icon(Icons.send),
                      tooltip: 'Log',
                      onPressed: _captureNote,
                    ),
                  ),
                  onChanged: (v) =>
                      ref.read(_loopCaptureProvider.notifier).state = v,
                  onSubmitted: (_) => _captureNote(),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                'Solo loop inspired by Cairn Solo (CC-BY-SA 4.0, Andrew Cavanagh, EpicEmpires.org).',
                key: const Key('loop-credit'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _step(BuildContext context, String title, String? body,
          List<Widget> children) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (body != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(body),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: children,
              ),
            ],
          ),
        ),
      );

  Future<void> _newScene() async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('New scene'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('loop-scene-name'),
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Scene title…'),
              onSubmitted: (v) => Navigator.pop(dialogCtx, v),
            ),
            const SizedBox(height: 8),
            // Inspiration at the point of need (audit F6): fill the title
            // from the scene generator; tap again to reroll, edit freely.
            TextButton.icon(
              key: const Key('loop-scene-seed'),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Roll a seed'),
              // Await the FUTURE (not .valueOrNull) so a cold oracle fills
              // when loaded instead of silently no-oping on first tap.
              onPressed: () async {
                final g = (await ref.read(oracleProvider.future)).newScene();
                controller.text = g.summary ?? g.title;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (title == null) return; // cancelled — no scene created
    final name = title.trim().isEmpty ? 'New scene' : title.trim();
    final id = await ref.read(journalProvider.notifier).addScene(name);
    if (!mounted) return;
    await ref.read(playContextProvider.notifier).setActiveScene(id);
  }

  Future<void> _newTask() async {
    final name = _taskName.text.trim();
    if (name.isEmpty) return;
    final p = _preset;
    final id = await ref.read(threadsProvider.notifier).addReturningId(name);
    await ref.read(threadsProvider.notifier).setTally(
          id,
          Tally(start: p.$2, current: p.$2, target: p.$3),
        );
    _taskName.clear();
  }

  Future<void> _tallyRoll(Thread t) async {
    final outcome = rollVsTally(t.tally!, Dice());
    final text =
        '${t.title}: ${outcome == TallyRollOutcome.clean ? 'clean' : 'complication'}';
    ref.read(_loopTallyRollProvider.notifier).state = text;
    await ref.read(journalProvider.notifier).addResult(
          'Tally roll',
          text,
          sourceTool: 'solo-loop',
        );
  }

  Future<void> _ask() async {
    final result = soloYesNo(ref.read(_loopOddsProvider), Dice());
    ref.read(_loopLastProvider.notifier).state = result;
    final g = result.toGenResult(question: _question.text);
    await ref.read(journalProvider.notifier).addResult(
          g.title,
          g.asText,
          sourceTool: 'solo-loop',
          payload: g.toPayload(),
        );
    // The question was answered — clear the field for the next beat.
    _question.clear();
    ref.read(_loopQuestionProvider.notifier).state = '';
  }

  /// Seed the inline interpret card from the last yes/no roll.
  /// The card handles the LLM call + Keep/Discard in-place.
  void _interpret() {
    final last = ref.read(_loopLastProvider);
    if (last == null) return;
    final g = last.toGenResult();
    final journal =
        ref.read(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final ctx = ref.read(playContextProvider).valueOrNull;
    final scene = activeSceneEntry(journal, ctx?.activeSceneId);
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const CampaignSettings();
    ref.read(_loopInterpretSeedProvider.notifier).state = OracleSeed(
      resultText: g.asText,
      genre: settings.genre,
      tone: settings.tone,
      sceneContext: scene == null ? '' : '${scene.title}\n${scene.body}'.trim(),
      activeCharacter: ref.read(activeCharacterLineProvider),
      systemPrimer: ref.read(systemPrimerProvider),
    );
  }

  IconData _beatIcon(BeatAction a) => switch (a) {
        BeatAction.nameScene => Icons.add,
        BeatAction.ask || BeatAction.askAgain => Icons.help_outline,
        BeatAction.interpret => Icons.auto_awesome,
        BeatAction.inspire => Icons.lightbulb_outline,
        BeatAction.capture => Icons.edit_note,
      };

  String _beatLabel(BeatAction a) => switch (a) {
        BeatAction.nameScene => 'Name the scene',
        BeatAction.ask => 'Ask oracle',
        BeatAction.askAgain => 'Ask again',
        BeatAction.interpret => 'Interpret',
        BeatAction.inspire => 'Inspire',
        BeatAction.capture => 'Capture',
      };

  Future<void> _runBeat(BeatAction a) async {
    switch (a) {
      case BeatAction.nameScene:
        await _newScene();
      case BeatAction.ask:
      case BeatAction.askAgain:
        // Starting a fresh roll: drop any visible interpret card (it read the
        // PREVIOUS roll) and reset the interpreted flag.
        ref.read(_loopInterpretSeedProvider.notifier).state = null;
        ref.read(_loopInterpretedProvider.notifier).state = false;
        await _ask();
      case BeatAction.interpret:
        _interpret();
      case BeatAction.inspire:
        unawaited(showGenerateSheet(context));
      case BeatAction.capture:
        FocusScope.of(context).requestFocus(_captureFocus);
    }
  }

  Future<void> _captureNote() async {
    final text = _capture.text.trim();
    if (text.isEmpty) return;
    await ref.read(journalProvider.notifier).addText(text);
    _capture.clear();
    ref.read(_loopCaptureProvider.notifier).state = '';
  }
}

// ---------------------------------------------------------------------------
// Inline interpretation card
// ---------------------------------------------------------------------------

class _InterpretCard extends ConsumerStatefulWidget {
  const _InterpretCard({super.key, required this.seed, required this.onDone});
  final OracleSeed seed;
  final VoidCallback onDone;
  @override
  ConsumerState<_InterpretCard> createState() => _InterpretCardState();
}

class _InterpretCardState extends ConsumerState<_InterpretCard> {
  late Future<List<OracleInterpretation>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(interpreterServiceProvider).interpret(widget.seed);
  }

  @override
  void didUpdateWidget(_InterpretCard old) {
    super.didUpdateWidget(old);
    // Re-kick the reading if the card is reused with a new seed (defensive:
    // the parent currently clears the card before re-seeding, but this keeps
    // the displayed reading in sync with the seed either way).
    if (widget.seed != old.seed) {
      _future = ref.read(interpreterServiceProvider).interpret(widget.seed);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FutureBuilder<List<OracleInterpretation>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const SizedBox(
                    height: 48,
                    child: Center(child: CircularProgressIndicator()));
              }
              if (snap.hasError || (snap.data?.isEmpty ?? true)) {
                return Row(children: [
                  const Expanded(child: Text('Reading failed.')),
                  TextButton(
                    key: const Key('loop-interpret-retry'),
                    onPressed: () => setState(() => _future = ref
                        .read(interpreterServiceProvider)
                        .interpret(widget.seed)),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                      onPressed: widget.onDone, child: const Text('Dismiss')),
                ]);
              }
              final card = snap.data!.first;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('(${card.lens}): ${card.reading}'),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      key: const Key('loop-interpret-discard'),
                      onPressed: widget.onDone,
                      child: const Text('Discard'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('loop-interpret-keep'),
                      // Override the theme's full-width (Size.fromHeight)
                      // minimumSize so this button can sit natural-width beside
                      // Discard in a Row without forcing an infinite width.
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 40)),
                      onPressed: () async {
                        await ref.read(journalProvider.notifier).addResult(
                              'Oracle reading',
                              '(${card.lens}): ${card.reading}',
                              sourceTool: 'interpret',
                            );
                        widget.onDone();
                      },
                      child: const Text('Keep'),
                    ),
                  ]),
                ],
              );
            },
          ),
        ),
      );
}

/// The "Play" destination body: the collapsible Solo-Loop bar above the live
/// journal feed.
///
/// Layout: a slim toggle header, then (when expanded) the [LoopBar] at its
/// natural height capped at ~45% of the play area (scrolling internally beyond
/// that), then [JournalScreen] fills — and owns the scroll of — the rest.
///
/// The loop bar is a NON-flex child so the journal always keeps priority. An
/// earlier `Flexible(fit: loose)` had the DEFAULT flex: 1, identical to the
/// journal's `Expanded` flex: 1, so the column split its height ~50/50 — the
/// loop bar reserved half the screen and squeezed the feed to a sliver that
/// couldn't scroll. Collapse state is sticky ([loopBarExpandedProvider]).
class PlayScreen extends ConsumerStatefulWidget {
  const PlayScreen({super.key});
  @override
  ConsumerState<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends ConsumerState<PlayScreen> {
  // Owned so the always-visible Scrollbar and the capped scroll view share a
  // position — the visible thumb is the "there is more below" affordance the
  // bare capped scroll region lacked (stranger-test S3: clipped Steps read as
  // nonexistent).
  final _loopScroll = ScrollController();

  @override
  void dispose() {
    _loopScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expanded = ref.watch(loopBarExpandedProvider).valueOrNull ?? true;
    return LayoutBuilder(
      builder: (context, constraints) {
        final cap = constraints.maxHeight.isFinite
            ? constraints.maxHeight * 0.45
            : double.infinity;
        return Column(
          children: [
            InkWell(
              key: const Key('loop-collapse-toggle'),
              onTap: () => ref
                  .read(loopBarExpandedProvider.notifier)
                  .setExpanded(!expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: Row(
                  children: [
                    Icon(expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20),
                    const SizedBox(width: 6),
                    Text('Solo Loop',
                        style: Theme.of(context).textTheme.labelMedium),
                  ],
                ),
              ),
            ),
            if (expanded)
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: cap),
                child: Scrollbar(
                  controller: _loopScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _loopScroll,
                    child: const LoopBar(),
                  ),
                ),
              ),
            const Expanded(child: JournalScreen()),
          ],
        );
      },
    );
  }
}
