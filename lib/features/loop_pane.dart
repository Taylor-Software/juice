import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/solo_oracle.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'generate_sheet.dart';

/// The "Solo Loop" Track subtab: a checklist that wires the active scene, a d10
/// yes/no oracle, the inspire sheet, success-tally tasks, and journal logging.
class LoopPane extends ConsumerStatefulWidget {
  const LoopPane({super.key});
  @override
  ConsumerState<LoopPane> createState() => _LoopPaneState();
}

class _LoopPaneState extends ConsumerState<LoopPane> {
  SoloLikelihood _odds = SoloLikelihood.even;
  SoloYesNo? _last;
  final _capture = TextEditingController();

  @override
  void dispose() {
    _capture.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final journal = ref.watch(journalProvider).valueOrNull ?? const [];
    final ctx = ref.watch(playContextProvider).valueOrNull;
    final scene = activeSceneEntry(journal, ctx?.activeSceneId);
    final threads = ref.watch(threadsProvider).valueOrNull ?? const [];
    final tallied = threads.where((t) => t.tally != null).toList();

    return ListView(
      padding: const EdgeInsets.all(12),
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
            selected: {_odds},
            onSelectionChanged: (s) => setState(() => _odds = s.first),
          ),
          FilledButton(
            key: const Key('loop-ask'),
            onPressed: _ask,
            child: const Text('Ask'),
          ),
          if (_last != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${_last!.phrase} (d10=${_last!.roll})',
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
          tallied.isEmpty
              ? 'No tallied tasks. Add one on a thread (Track → Threads).'
              : null,
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
                trailing: Wrap(children: [
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
                ]),
              ),
          ],
        ),
        _step(context, '5 · Capture', null, [
          SizedBox(
            width: double.infinity,
            child: TextField(
              key: const Key('loop-capture-field'),
              controller: _capture,
              decoration: const InputDecoration(
                hintText: 'Quick note to the journal…',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _captureNote(),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Text(
          'Solo loop inspired by Cairn Solo (CC-BY-SA 4.0, Andrew Cavanagh, EpicEmpires.org).',
          key: const Key('loop-credit'),
          style: Theme.of(context).textTheme.bodySmall,
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
    final id =
        await ref.read(journalProvider.notifier).addScene('New scene');
    await ref.read(playContextProvider.notifier).setActiveScene(id);
  }

  Future<void> _ask() async {
    final result = soloYesNo(_odds, Dice());
    setState(() => _last = result);
    final g = result.toGenResult();
    await ref.read(journalProvider.notifier).addResult(
          g.title,
          g.asText,
          sourceTool: 'solo-loop',
          payload: g.toPayload(),
        );
  }

  Future<void> _captureNote() async {
    final text = _capture.text.trim();
    if (text.isEmpty) return;
    await ref.read(journalProvider.notifier).addText(text);
    _capture.clear();
  }
}
