import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/interpreter.dart';
import '../state/providers.dart';

/// First-run offer to turn on the on-device AI enhancements. Shown once (gated
/// by [aiOfferSeenProvider]) when the platform supports on-device AI but it
/// isn't enabled yet. Accepting flips the app-global [aiEnabledProvider] on and
/// kicks off the one-time model download via the shared interpreter service —
/// the SAME `warmUp()` path the Settings sheet uses — then confirms with a
/// SnackBar (live progress + re-download control live in Settings).
///
/// This does not bypass the download-consent posture: the user explicitly taps
/// "Enable & download" knowing the size shown here; nothing downloads otherwise.
Future<void> showAiFirstRunOffer(BuildContext context, WidgetRef ref) async {
  final downloadLabel = ref.read(interpreterServiceProvider).downloadLabel;
  // Mark seen up front: whatever the user chooses (or if they dismiss by
  // tapping outside), the offer has served its one-and-only appearance.
  await ref.read(aiOfferSeenProvider.notifier).markSeen();
  if (!context.mounted) return;

  final enable = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('ai-offer-dialog'),
      title: const Text('Bring the oracle to life'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Optional AI enhancements interpret your oracle rolls, voice NPCs, '
            'and recap your story — all on-device, private, and offline.',
          ),
          const SizedBox(height: 12),
          Text(
            'One-time model download ($downloadLabel) over Wi-Fi. You can also '
            'turn this on later in Settings.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('ai-offer-later'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const Key('ai-offer-enable'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Enable & download'),
        ),
      ],
    ),
  );

  if (enable != true || !context.mounted) return;

  // Flip the app-global flag on and start the download (fire-and-forget: the
  // service is app-global and single-flight, so the install keeps running even
  // after we leave this screen).
  await ref.read(aiEnabledProvider.notifier).setEnabled(true);
  unawaited(ref.read(interpreterServiceProvider).warmUp());
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Downloading the AI model in the background — track progress in '
          'Settings. Enhancements switch on once it finishes.',
        ),
      ),
    );
  }
}
