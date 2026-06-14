import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/lonelog_data.dart';
import '../engine/lonelog_highlight.dart';
import '../state/providers.dart';

/// Read-only reference for the Lonelog journaling notation. Renders the legend
/// (symbols, tags, blocks, addons) plus worked examples rendered through the
/// [highlight] classifier. No interactive state — a plain scroll, so it dodges
/// the loose-constraint freeze (no TabBarView / non-flex Material buttons).
class LonelogReferenceScreen extends ConsumerWidget {
  const LonelogReferenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lonelogDataProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load Lonelog legend: $e')),
      data: (data) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section('Core symbols', [
            for (final s in data.symbols)
              _Row('${s.symbol}  —  ${s.name}', s.role),
          ]),
          _Section('Tags & references', [
            for (final p in data.tagPrefixes)
              _Row('[${p.prefix}:…]  —  ${p.name}', p.meaning),
          ]),
          _Section('Blocks', [
            for (final b in data.blocks) _Row(b.openTag, b.purpose),
          ]),
          _Section('Addons', [
            for (final a in data.addons)
              _Row('${a.title}  (${a.status})', a.summary),
          ]),
          _Section('Worked examples', [
            for (final ex in data.examples) _Example(ex),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.head, this.body);
  final String head;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(head, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(body, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Example extends StatelessWidget {
  const _Example(this.example);
  final LonelogExample example;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color colorFor(LonelogSpanKind k) => switch (k) {
          LonelogSpanKind.symbol => scheme.primary,
          LonelogSpanKind.actor => scheme.tertiary,
          LonelogSpanKind.tag => scheme.secondary,
          LonelogSpanKind.block => scheme.error,
          LonelogSpanKind.meta => scheme.outline,
          LonelogSpanKind.text => scheme.onSurface,
        };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(example.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final line in example.lines)
            RichText(
              text: TextSpan(
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                children: [
                  for (final span in highlight(line))
                    TextSpan(
                        text: span.text,
                        style: TextStyle(color: colorFor(span.kind))),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
