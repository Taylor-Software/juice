import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../engine/dice_notation.dart';

/// A brief "tumble" over a [DiceRollResult]: each die flashes random faces,
/// then settles on its rolled value with a scale-bounce; the total reveals
/// after. Honors reduced-motion. No deps (AnimationController + Timer).
/// [rollId] bumps per roll — a change replays the tumble.
class DiceRollAnimation extends StatefulWidget {
  const DiceRollAnimation(
      {super.key, required this.result, required this.rollId});
  final DiceRollResult result;
  final int rollId;

  @override
  State<DiceRollAnimation> createState() => _DiceRollAnimationState();
}

class _DiceRollAnimationState extends State<DiceRollAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  Timer? _flash;
  bool _tumbling = false;
  bool _started = false;
  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          _flash?.cancel();
          _flash = null;
          setState(() => _tumbling = false);
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _start();
    }
  }

  @override
  void didUpdateWidget(covariant DiceRollAnimation old) {
    super.didUpdateWidget(old);
    if (widget.rollId != old.rollId) _start();
  }

  void _start() {
    _flash?.cancel();
    if (MediaQuery.of(context).disableAnimations) {
      setState(() => _tumbling = false);
      return;
    }
    setState(() => _tumbling = true);
    _ctrl.forward(from: 0);
    _flash = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _flash?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  String _faceFor(RolledGroup g) {
    final m = RegExp(r'd(F|%|\d+)', caseSensitive: false).firstMatch(g.label);
    final spec = m?.group(1)?.toLowerCase();
    if (spec == 'f') return const ['+', '−', '0'][_rng.nextInt(3)];
    final sides = spec == '%' ? 100 : (int.tryParse(spec ?? '') ?? 6);
    return '${_rng.nextInt(sides) + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedScale(
          scale: _tumbling ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.centerLeft,
          child: Text(
            '${r.total}',
            key: const Key('dice-total'),
            style: theme.textTheme.displaySmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        for (final g in r.groups)
          if (g.dice.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${g.label}: ', style: theme.textTheme.bodyMedium),
                  for (final d in g.dice)
                    _DieFace(
                      face: _tumbling ? _faceFor(g) : d.display,
                      kept: d.kept,
                      settled: !_tumbling,
                    ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Chip(
                  label: Text(g.label), visualDensity: VisualDensity.compact),
            ),
      ],
    );
  }
}

class _DieFace extends StatelessWidget {
  const _DieFace(
      {required this.face, required this.kept, required this.settled});
  final String face;
  final bool kept;
  final bool settled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedScale(
      scale: settled ? 1.0 : 0.92,
      duration: const Duration(milliseconds: 120),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: kept
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: kept
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          face,
          style: theme.textTheme.titleMedium?.copyWith(
            decoration: kept ? null : TextDecoration.lineThrough,
            color: kept ? null : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
