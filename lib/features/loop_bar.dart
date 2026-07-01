import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/models.dart';
import '../engine/next_beat.dart';
import '../engine/oracle_interpreter.dart';
import '../engine/solo_oracle.dart';
import '../engine/tally.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'generate_sheet.dart';
import 'journal_screen.dart';
import 'oracle_interpretation_sheet.dart';

/// Ephemeral loop-UI state that survives Track-tab navigation (the [LoopBar]
/// State is disposed when the subtab is switched away). These are file-private,
/// NOT autoDispose, NOT persisted — app-global lifetime, reset on app restart.
final _loopOddsProvider =
    StateProvider<SoloLikelihood>((_) => SoloLikelihood.even);
final _loopLastProvider = StateProvider<SoloYesNo?>((_) => null);
final _loopCaptureProvider = StateProvider<String>((_) => '');
final _loopTallyRollProvider = StateProvider<String?>((_) => null);
final _loopBeatOpenProvider = StateProvider<bool>((_) => false);
final _loopInterpretedProvider = StateProvider<bool>((_) => false);

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
  final _captureFocus = FocusNode();
  (String, int, int) _preset = kTallyPresets[1]; // Minor challenge 3(6)

  @override
  void initState() {
    super.initState();
    // Re-seed the controller from the nav-surviving provider (the State is
    // disposed/recreated on tab switch, the provider persists the text).
    _capture.text = ref.read(_loopCaptureProvider);
  }

  @override
  void dispose() {
    _capture.dispose();
    _taskName.dispose();
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
    final aiReady = ref.watch(aiReadyProvider);
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(children: [
            FilledButton.icon(
              key: const Key('loop-next-beat'),
              icon: const Icon(Icons.bolt),
              label: const Text('Next beat'),
              onPressed: () =>
                  ref.read(_loopBeatOpenProvider.notifier).update((v) => !v),
            ),
          ]),
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
        ExpansionTile(
          key: const Key('loop-steps'),
          title: const Text('Steps'),
          initiallyExpanded: false,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          children: [
            _step(context, '1 · Scene',
                scene == null ? 'No scene yet.' : scene.title, [
              FilledButton.tonalIcon(
                key: const Key('loop-new-scene'),
                icon: const Icon(Icons.add),
                label: const Text('New scene'),
                onPressed: _newScene,
              ),
            ]),
            _step(context, '2 · Ask a question', 'Roll a d10 yes/no.', [
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
              if (aiReady && last != null)
                OutlinedButton(
                  key: const Key('loop-interpret'),
                  onPressed: _interpret,
                  child: const Text('Interpret'),
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
                    trailing: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                      IconButton(
                        key: Key('loop-task-dec-${t.id}'),
                        icon: const Icon(Icons.remove),
                        onPressed: () =>
                            ref.read(threadsProvider.notifier).adjustTally(t.id, -1),
                      ),
                      IconButton(
                        key: Key('loop-task-inc-${t.id}'),
                        icon: const Icon(Icons.add),
                        onPressed: () =>
                            ref.read(threadsProvider.notifier).adjustTally(t.id, 1),
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
        content: TextField(
          key: const Key('loop-scene-name'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Scene title…'),
          onSubmitted: (v) => Navigator.pop(dialogCtx, v),
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
    final g = result.toGenResult();
    await ref.read(journalProvider.notifier).addResult(
          g.title,
          g.asText,
          sourceTool: 'solo-loop',
          payload: g.toPayload(),
        );
  }

  /// Interpret the last yes/no roll inline (on-device LLM): seed from the
  /// result + the active scene + PC, run the shared interpretation sheet, log
  /// the reading. Mirrors run_screen's `_interpret` (here `_last` is a
  /// [SoloYesNo], so seed from its [SoloYesNo.toGenResult]).
  Future<void> _interpret() async {
    final last = ref.read(_loopLastProvider);
    if (last == null) return;
    final g = last.toGenResult();
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
      sceneContext: scene == null ? '' : '${scene.title}\n${scene.body}'.trim(),
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
        ref.read(_loopInterpretedProvider.notifier).state = false;
        await _ask();
      case BeatAction.interpret:
        await _interpret();
      case BeatAction.inspire:
        showGenerateSheet(context);
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

/// The "Play" destination body: the loop controls above the live journal feed.
///
/// Layout: [LoopBar] scrolls within its natural min-height (but can shrink if
/// needed), then [JournalScreen] fills the remaining space.
class PlayScreen extends StatelessWidget {
  const PlayScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: SingleChildScrollView(
            child: LoopBar(),
          ),
        ),
        Expanded(child: JournalScreen()),
      ],
    );
  }
}
