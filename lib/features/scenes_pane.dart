import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../engine/models.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/play_context.dart';
import '../state/providers.dart';

/// Tracking → Scenes: derived list of journal scene dividers, newest first.
class ScenesPane extends ConsumerWidget {
  const ScenesPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final scenes = entries.where((e) => e.kind == JournalKind.scene).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text('Scenes',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              // Flexible bounds the button under the loose tool-host width
              // constraints (see the freeze rule).
              Flexible(
                child: FilledButton.tonalIcon(
                  key: const Key('scenes-new'),
                  icon: const Icon(Icons.add),
                  label: const Text('New scene'),
                  onPressed: () => _newScene(context, ref),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: FilledButton.tonalIcon(
                  key: const Key('generate-scene'),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Generate'),
                  onPressed: () => _generateScene(context, ref),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: scenes.isEmpty
              ? const Center(child: Text('No scenes yet.'))
              : ListView(
                  children: [
                    for (final s in scenes)
                      ListTile(
                        leading: const Icon(Icons.movie_outlined),
                        title: Text(s.title),
                        subtitle:
                            (s.chaosFactor != null || s.body.trim().isNotEmpty)
                                ? Text([
                                    if (s.chaosFactor != null)
                                      'Chaos ${s.chaosFactor}',
                                    if (s.body.trim().isNotEmpty) s.body.trim(),
                                  ].join('\n'))
                                : null,
                        onTap: () => ref
                            .read(shellRouteProvider.notifier)
                            .goTo(Destination.journal),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _newScene(BuildContext context, WidgetRef ref,
      {String initialTitle = ''}) async {
    final usesMythic =
        (ref.read(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
                kAllSystems)
            .contains('mythic');
    final result = await showDialog<({String title, bool rollTest})>(
      context: context,
      builder: (_) =>
          _NewSceneDialog(initialTitle: initialTitle, usesMythic: usesMythic),
    );
    if (result == null || result.title.trim().isEmpty) return;
    final chaos = ref.read(crawlProvider).valueOrNull?.chaosFactor;
    final id = await ref
        .read(journalProvider.notifier)
        .addScene(result.title.trim(), chaosFactor: chaos);
    await ref.read(playContextProvider.notifier).setActiveScene(id);
    if (usesMythic && result.rollTest) {
      // `?? 5` only fires before any crawl state exists; 5 is the Mythic 2e
      // default Chaos Factor (matches CrawlState.chaosFactor's default).
      await _rollSceneTest(ref, chaos ?? 5);
    }
  }

  /// Rolls a Mythic Scene Test and logs it as a journal result. An interrupted
  /// scene additionally rolls (and logs) a random event — the canonical Mythic
  /// "scene is replaced" follow-up — reusing [Oracle.mythicRandomEvent].
  Future<void> _rollSceneTest(WidgetRef ref, int chaos) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final journal = ref.read(journalProvider.notifier);
    final test = oracle.mythicSceneTest(chaos);
    await journal.addResult(test.title, test.asText,
        sourceTool: 'mythic', payload: test.toPayload());
    // Literal must match the outcome string emitted by Oracle.mythicSceneTest.
    if (test.rolls.first.value == 'Interrupted Scene') {
      final threads =
          (ref.read(threadsProvider).valueOrNull ?? const <Thread>[])
              .where((t) => t.open)
              .map((t) => t.title)
              .toList();
      final characters =
          (ref.read(charactersProvider).valueOrNull ?? const <Character>[])
              .map((c) => c.name)
              .toList();
      final event =
          oracle.mythicRandomEvent(threads: threads, characters: characters);
      await journal.addResult(event.title, event.asText,
          sourceTool: 'mythic', payload: event.toPayload());
    }
  }

  Future<void> _generateScene(BuildContext context, WidgetRef ref) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final g = oracle.newScene();
    await _newScene(context, ref, initialTitle: g.summary ?? g.title);
  }
}

/// New-scene dialog: a title field (with a name-roll die) and, when Mythic is
/// enabled, a "Roll Scene Test" toggle. Owns its own controller so it is
/// disposed only after the dialog is fully gone (avoids a use-after-dispose
/// race with the exit animation). Pops `({title, rollTest})` or null.
class _NewSceneDialog extends ConsumerStatefulWidget {
  const _NewSceneDialog({required this.initialTitle, required this.usesMythic});
  final String initialTitle;
  final bool usesMythic;

  @override
  ConsumerState<_NewSceneDialog> createState() => _NewSceneDialogState();
}

class _NewSceneDialogState extends ConsumerState<_NewSceneDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);
  late bool _rollTest = widget.usesMythic;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ({String title, bool rollTest}) get _value =>
      (title: _controller.text, rollTest: _rollTest);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New scene'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Scene title',
              suffixIcon: IconButton(
                icon: const Icon(Icons.casino_outlined),
                tooltip: 'Roll a name',
                onPressed: () {
                  final oracle = ref.read(oracleProvider).valueOrNull;
                  if (oracle == null) return;
                  _controller.text = oracle.generateName().summary ?? '';
                },
              ),
            ),
            onSubmitted: (_) => Navigator.pop(context, _value),
          ),
          // Mythic GME: a scene test against Chaos decides whether the scene
          // plays as expected, is altered, or is interrupted (a random event).
          // Folds that roll into scene creation.
          if (widget.usesMythic)
            CheckboxListTile(
              key: const Key('scene-roll-test'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Roll Mythic Scene Test'),
              value: _rollTest,
              onChanged: (v) => setState(() => _rollTest = v ?? false),
            ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _value),
            child: const Text('Start scene')),
      ],
    );
  }
}
