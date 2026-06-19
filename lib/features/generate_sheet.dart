import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/generator_registry.dart';
import '../state/providers.dart';

/// Opens the flavor-generator sheet from the journal composer.
Future<void> showGenerateSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const GenerateSheet(),
    );

/// The "inspire" sheet: flavor generators grouped by section. Tapping one rolls
/// it and appends the result to the journal.
class GenerateSheet extends ConsumerWidget {
  const GenerateSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oracle = ref.watch(oracleProvider).valueOrNull;
    if (oracle == null) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('Generators still loading…')),
      );
    }
    final bySection = <GenSection, List<GeneratorDef>>{};
    for (final g in flavorGenerators) {
      bySection.putIfAbsent(g.section, () => []).add(g);
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final section in GenSection.values)
              if (bySection[section]?.isNotEmpty ?? false) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text(section.label,
                      style: Theme.of(context).textTheme.labelMedium),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in bySection[section]!)
                      ActionChip(
                        key: Key('gen-${g.label}'),
                        label: Text(g.label),
                        onPressed: () {
                          final r = g.run(oracle);
                          ref.read(journalProvider.notifier).addResult(
                              r.title, r.asText,
                              sourceTool: sourceToolFor(g.section),
                              payload: r.toPayload());
                          Navigator.of(context).pop();
                        },
                      ),
                  ],
                ),
              ],
          ],
        ),
      ),
    );
  }
}
