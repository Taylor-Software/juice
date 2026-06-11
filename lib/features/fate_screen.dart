import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/oracle.dart';
import '../shared/result_card.dart';
import '../state/providers.dart';

class FateScreen extends ConsumerStatefulWidget {
  const FateScreen({super.key, required this.oracle});
  final Oracle oracle;

  @override
  ConsumerState<FateScreen> createState() => _FateScreenState();
}

class _FateScreenState extends ConsumerState<FateScreen> {
  Likelihood _likelihood = Likelihood.normal;
  FateResult? _last;
  int _oddsIndex = 4; // 50/50
  GenResult? _mythicLast;

  void _roll() => setState(() => _last = widget.oracle.fateCheck(_likelihood));

  String _glyph(int v) => v > 0 ? '+' : (v < 0 ? '−' : '0');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _last;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Fate Check', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text('Ask a yes/no question, then roll 2dF + 1d6.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        SegmentedButton<Likelihood>(
          segments: const [
            ButtonSegment(value: Likelihood.unlikely, label: Text('Unlikely')),
            ButtonSegment(value: Likelihood.normal, label: Text('Normal')),
            ButtonSegment(value: Likelihood.likely, label: Text('Likely')),
          ],
          selected: {_likelihood},
          onSelectionChanged: (s) => setState(() => _likelihood = s.first),
        ),
        const SizedBox(height: 16),
        if (last != null) _FateResultCard(result: last, glyph: _glyph),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _roll,
          icon: const Icon(Icons.casino_outlined),
          label: const Text('Roll Fate Check'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _logGen(widget.oracle.randomEvent()),
                child: const Text('Random Event'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _logGen(widget.oracle.payThePrice()),
                child: const Text('Pay the Price'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(),
        Text('Mythic GME', style: theme.textTheme.headlineSmall),
        Text(
          'Mythic Game Master Emulator © Word Mill Games (wordmillgames.com), '
          'used under CC-BY-NC 4.0.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Builder(builder: (context) {
          final crawl =
              ref.watch(crawlProvider).valueOrNull ?? const CrawlState();
          final chaos = crawl.chaosFactor.clamp(1, 9);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Chaos Factor: $chaos',
                      style: theme.textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: chaos > 1
                        ? () => ref.read(crawlProvider.notifier).save(
                            crawl.copyWith(chaosFactor: chaos - 1))
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: chaos < 9
                        ? () => ref.read(crawlProvider.notifier).save(
                            crawl.copyWith(chaosFactor: chaos + 1))
                        : null,
                  ),
                ],
              ),
              DropdownMenu<int>(
                initialSelection: _oddsIndex,
                label: const Text('Odds'),
                dropdownMenuEntries: [
                  for (var i = 0; i < widget.oracle.data.mythicOdds.length; i++)
                    DropdownMenuEntry(
                        value: i, label: widget.oracle.data.mythicOdds[i]),
                ],
                onSelected: (v) =>
                    setState(() => _oddsIndex = v ?? _oddsIndex),
              ),
              const SizedBox(height: 12),
              if (_mythicLast != null) ...[
                ResultCard(
                  result: _mythicLast!,
                  onLog: () {
                    ref.read(logProvider.notifier).add(
                        _mythicLast!.title, _mythicLast!.asText);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logged')),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: () => setState(() => _mythicLast =
                    widget.oracle.mythicFate(_oddsIndex, chaos)),
                icon: const Icon(Icons.casino_outlined),
                label: const Text('Fate Chart'),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _mythicLast =
                          widget.oracle.mythicSceneTest(chaos)),
                      child: const Text('Scene Test'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final threads = (ref
                                    .read(threadsProvider)
                                    .valueOrNull ??
                                const <Thread>[])
                            .where((t) => t.open)
                            .map((t) => t.title)
                            .toList();
                        final characters = (ref
                                    .read(charactersProvider)
                                    .valueOrNull ??
                                const <Character>[])
                            .map((c) => c.name)
                            .toList();
                        setState(() => _mythicLast =
                            widget.oracle.mythicEventFocus(
                                threads: threads, characters: characters));
                      },
                      child: const Text('Event Focus'),
                    ),
                  ),
                ],
              ),
            ],
          );
        }),
      ],
    );
  }

  void _logGen(GenResult g) {
    ref.read(logProvider.notifier).add(g.title, g.asText);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${g.title}: ${g.summary ?? g.rolls.first.value}')),
    );
  }
}

class _FateResultCard extends ConsumerWidget {
  const _FateResultCard({required this.result, required this.glyph});
  final FateResult result;
  final String Function(int) glyph;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isYes = result.result.contains('Yes') || result.result == 'Favorable';
    final isNo = result.result.contains('No') || result.result == 'Unfavorable';
    final accent = isYes
        ? scheme.primary
        : isNo
            ? scheme.error
            : scheme.tertiary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Die(label: glyph(result.primary), filled: true),
                _Die(label: glyph(result.secondary), filled: false),
                _Die(label: '${result.intensityRoll}', filled: false),
                Text(result.shorthand,
                    style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        )),
                IconButton(
                  tooltip: 'Log this result',
                  icon: const Icon(Icons.bookmark_add_outlined),
                  onPressed: () {
                    ref.read(logProvider.notifier).add(
                          'Fate Check (${result.likelihood.label})',
                          '${result.result} — ${result.intensity}  [${result.shorthand}]',
                        );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Logged')),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(result.result,
                style: theme.textTheme.headlineMedium
                    ?.copyWith(color: accent, fontWeight: FontWeight.w600)),
            Text('Intensity: ${result.intensity}',
                style: theme.textTheme.titleMedium),
            if (result.isRandomEvent)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('→ also triggers a Random Event',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.tertiary)),
              ),
            if (result.isInvalidAssumption)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('→ re-ask: your question assumed something false',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.tertiary)),
              ),
          ],
        ),
      ),
    );
  }
}

class _Die extends StatelessWidget {
  const _Die({required this.label, required this.filled});
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(label,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold)),
    );
  }
}
