import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/interpreter.dart';
import '../state/providers.dart';

/// App-wide settings. P1 holds a single "AI assistant" section that owns the
/// on-device model download + the global enable toggle. AI affordances stay
/// hidden across the app until the model is downloaded AND enabled here.
Future<void> showSettingsSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SettingsSheet(),
    );

class _SettingsSheet extends ConsumerWidget {
  const _SettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final supported = ref.watch(aiSupportedProvider);
    final enabled = ref.watch(aiEnabledProvider).valueOrNull ?? false;
    final status = ref.watch(interpreterStatusProvider).valueOrNull;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Settings', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('AI assistant', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            if (!supported)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text("On-device AI isn't available on this platform."),
              )
            else ...[
              SwitchListTile(
                key: const Key('settings-ai-toggle'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable AI assistant'),
                subtitle: const Text(
                    'Interpret rolls, voice lines, recaps — all on-device.'),
                value: enabled,
                onChanged: (v) =>
                    ref.read(aiEnabledProvider.notifier).setEnabled(v),
              ),
              if (enabled) _statusBlock(context, ref, status),
            ],
            const SizedBox(height: 16),
            Text('Third-party content', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            const Text(
              'Draw Steel content is an independent product published under '
              'the Draw Steel Creator License and is not affiliated with '
              'MCDM Productions, LLC.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tales of Argosa text is used under Creative Commons '
              'Attribution-ShareAlike 4.0 (CC BY-SA 4.0), '
              '© Pickpocket Press / S J Grodzicki. '
              'Not affiliated with Pickpocket Press.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBlock(
      BuildContext context, WidgetRef ref, InterpreterStatus? status) {
    final service = ref.read(interpreterServiceProvider);
    final phase = status?.phase ?? InterpreterPhase.loading;
    switch (phase) {
      case InterpreterPhase.needsDownload:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Runs on-device. Download the model (${service.downloadLabel}) '
                'over Wi-Fi. One time only.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('settings-ai-download'),
              icon: const Icon(Icons.download),
              label: const Text('Download model'),
              onPressed: service.warmUp,
            ),
          ],
        );
      case InterpreterPhase.installing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Downloading… ${status?.progress ?? 0}%'),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: (status?.progress ?? 0) / 100),
          ],
        );
      case InterpreterPhase.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Loading model…'),
          ]),
        );
      case InterpreterPhase.ready:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(Icons.check_circle, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Text('Ready'),
          ]),
        );
      case InterpreterPhase.error:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status?.message ?? 'Something went wrong.'),
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('settings-ai-retry'),
              onPressed: service.warmUp,
              child: const Text('Retry'),
            ),
          ],
        );
      case InterpreterPhase.unsupported:
        return const SizedBox.shrink();
    }
  }
}
