import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dice.dart';
import '../engine/dice_notation.dart';
import '../state/providers.dart';

/// Free-form dice roller: notation input, quick chips, breakdown, history.
class DiceRollerScreen extends ConsumerStatefulWidget {
  const DiceRollerScreen({super.key, required this.dice});
  final Dice dice;

  @override
  ConsumerState<DiceRollerScreen> createState() => _DiceRollerScreenState();
}

class _DiceRollerScreenState extends ConsumerState<DiceRollerScreen> {
  static const _quickDice = ['d4', 'd6', 'd8', 'd10', 'd12', 'd20', 'd100', 'dF'];
  static const _historyCap = 20;

  final TextEditingController _input = TextEditingController();
  String? _error;
  DiceRollResult? _last;
  final List<DiceRollResult> _history = [];

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _validate(String text) {
    String? error;
    if (text.trim().isNotEmpty) {
      try {
        parseDice(text);
      } on FormatException catch (e) {
        error = e.message;
      }
    }
    setState(() => _error = error);
  }

  void _tapChip(String die) {
    final t = _input.text.trim();
    String next;
    if (t.isEmpty) {
      next = die;
    } else {
      final segments = t.split('+');
      final pattern = die == 'dF' ? r'^(\d*)d[fF]$' : '^(\\d*)$die\$';
      final match =
          RegExp(pattern, caseSensitive: false).firstMatch(segments.last.trim());
      if (match != null) {
        final count = match.group(1)!;
        final n = count.isEmpty ? 2 : int.parse(count) + 1;
        segments[segments.length - 1] = '$n$die';
        next = segments.join('+');
      } else {
        next = '$t+$die';
      }
    }
    _input.text = next;
    _validate(next);
  }

  void _roll() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final DiceRollResult result;
    try {
      result = parseDice(text).roll(widget.dice);
    } on FormatException {
      return;
    }
    setState(() => _record(result));
  }

  void _record(DiceRollResult result) {
    _last = result;
    _history.insert(0, result);
    if (_history.length > _historyCap) {
      _history.removeRange(_historyCap, _history.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _last;
    final canRoll = _error == null && _input.text.trim().isNotEmpty;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Dice Roller', style: theme.textTheme.headlineSmall),
        Text(
          'NdX, d%, dF, kh/kl/dh/dl, adv/dis — e.g. 4d6kh3+2',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('dice-input'),
          controller: _input,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _roll(),
          onChanged: _validate,
          decoration: InputDecoration(
            labelText: 'Expression',
            errorText: _error,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final die in _quickDice)
              ActionChip(
                label: Text(die),
                onPressed: () => _tapChip(die),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.casino_outlined),
          label: const Text('Roll'),
          onPressed: canRoll ? _roll : null,
        ),
        if (last != null) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(last.expression,
                            style: theme.textTheme.titleMedium),
                      ),
                      IconButton(
                        tooltip: 'Add to journal',
                        icon: const Icon(Icons.bookmark_add_outlined),
                        onPressed: () {
                          // Unlike journal-adjacent screens, this panel never
                          // watches journalProvider, so wait for the notifier
                          // to finish building before mutating it.
                          final notifier = ref.read(journalProvider.notifier);
                          ref.read(journalProvider.future).then(
                              (_) => notifier.add('Dice Roll', last.asText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Added to journal')),
                          );
                        },
                      ),
                    ],
                  ),
                  Text(
                    '${last.total}',
                    key: const Key('dice-total'),
                    style: theme.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  for (final g in last.groups)
                    if (g.dice.isNotEmpty)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '${g.label}: '),
                            for (var i = 0; i < g.dice.length; i++) ...[
                              if (i > 0) const TextSpan(text: ', '),
                              TextSpan(
                                text: g.dice[i].display,
                                style: g.dice[i].kept
                                    ? null
                                    : TextStyle(
                                        decoration: TextDecoration.lineThrough,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                              ),
                            ],
                          ],
                        ),
                        style: theme.textTheme.bodyMedium,
                      )
                    else
                      Text(g.label, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        ],
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('History', style: theme.textTheme.titleMedium),
          for (var i = 0; i < _history.length; i++)
            ListTile(
              key: Key('dice-history-$i'),
              dense: true,
              title: Text('${_history[i].expression} = ${_history[i].total}'),
              trailing: const Icon(Icons.replay),
              onTap: () {
                final expression = _history[i].expression;
                setState(() =>
                    _record(parseDice(expression).roll(widget.dice)));
              },
            ),
        ],
      ],
    );
  }
}
