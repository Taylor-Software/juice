import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/solo_oracle.dart';
import '../state/providers.dart';

/// Ask-first yes/no oracle dialog: type the question (optional but front and
/// center), pick the odds, roll a d10. Logs one journal entry whose title is
/// the question, so the log stays meaningful later (stranger-test audit S1/S2).
///
/// Returns the [SoloYesNo] result, or null when cancelled.
Future<SoloYesNo?> showAskOracleDialog(BuildContext context, WidgetRef ref) =>
    showDialog<SoloYesNo>(
      context: context,
      builder: (_) => const _AskOracleDialog(),
    );

class _AskOracleDialog extends ConsumerStatefulWidget {
  const _AskOracleDialog();

  @override
  ConsumerState<_AskOracleDialog> createState() => _AskOracleDialogState();
}

class _AskOracleDialogState extends ConsumerState<_AskOracleDialog> {
  final _question = TextEditingController();
  SoloLikelihood _odds = SoloLikelihood.even;

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final result = soloYesNo(_odds, Dice());
    final g = result.toGenResult(question: _question.text);
    await ref.read(journalProvider.notifier).addResult(
          g.title,
          g.asText,
          sourceTool: 'solo-loop',
          payload: g.toPayload(),
        );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(
      content: Text(_question.text.trim().isEmpty
          ? result.phrase
          : '${_question.text.trim()} — ${result.phrase}'),
    ));
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('ask-oracle-dialog'),
      title: const Text('Ask the oracle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const Key('ask-oracle-question'),
            controller: _question,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Your question',
              hintText: 'e.g. Is the bridge guarded?',
            ),
            onSubmitted: (_) => _ask(),
          ),
          const SizedBox(height: 16),
          SegmentedButton<SoloLikelihood>(
            segments: const [
              ButtonSegment(
                  value: SoloLikelihood.unlikely, label: Text('Unlikely')),
              ButtonSegment(value: SoloLikelihood.even, label: Text('Even')),
              ButtonSegment(
                  value: SoloLikelihood.likely, label: Text('Likely')),
            ],
            selected: {_odds},
            onSelectionChanged: (s) => setState(() => _odds = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            'The oracle answers yes or no — you write what it means.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('ask-oracle-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('ask-oracle-roll'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _ask,
          child: const Text('Ask'),
        ),
      ],
    );
  }
}
