import 'package:flutter/material.dart';

import '../engine/campaign_surfaces.dart';

/// Compact, read-only preview of which app surfaces a campaign's systems
/// decisions light up. Reads `surfacesFor` (the single source).
class CampaignPreviewPane extends StatelessWidget {
  const CampaignPreviewPane({super.key, required this.systems});
  final Set<String> systems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final verbs = surfacesFor(systems);
    final activeCount = verbs.expand((v) => v.rows).where((r) => r.on).length;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.disabledColor, fontSize: 11);

    return Column(
      key: const Key('campaign-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Preview', style: theme.textTheme.labelLarge),
          const SizedBox(width: 8),
          Text('$activeCount surfaces active',
              key: const Key('campaign-preview-count'),
              style: theme.textTheme.bodySmall),
        ]),
        const SizedBox(height: 4),
        for (final v in verbs)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.verb,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              Wrap(spacing: 8, runSpacing: 2, children: [
                for (final r in v.rows)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(r.on ? Icons.check : Icons.remove,
                        size: 13,
                        color: r.on
                            ? theme.colorScheme.primary
                            : theme.disabledColor),
                    const SizedBox(width: 2),
                    Text(r.name,
                        style: r.on ? theme.textTheme.bodySmall : muted),
                  ]),
              ]),
            ]),
          ),
      ],
    );
  }
}
