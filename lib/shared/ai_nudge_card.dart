import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings_sheet.dart';
import '../state/providers.dart';
import 'ai_badge.dart';
import 'design_tokens.dart';

/// A one-shot, dismissible card inviting the player to turn on the on-device AI.
/// Shown at the top of the journal while AI is supported but not yet enabled.
/// A slow sheen sweeps across it once on appear ONLY when motion is allowed
/// (reduced-motion → a fully static card, no controller running). The sweep is
/// a finite `forward()` (not a `repeat()`) so it settles — a perpetual loop
/// would hang every `pumpAndSettle` that renders the journal.
class AiNudgeCard extends ConsumerStatefulWidget {
  const AiNudgeCard({super.key});

  @override
  ConsumerState<AiNudgeCard> createState() => _AiNudgeCardState();
}

class _AiNudgeCardState extends ConsumerState<AiNudgeCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _sheen;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start the sheen only when motion is allowed. Reduced-motion keeps the
    // card fully static (no controller created → no ticker running).
    final motionOk = !MediaQuery.of(context).disableAnimations;
    if (motionOk && _sheen == null) {
      _sheen = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1400),
      )..forward();
    } else if (!motionOk && _sheen != null) {
      _sheen!.dispose();
      _sheen = null;
    }
  }

  @override
  void dispose() {
    _sheen?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    final card = Container(
      key: const Key('ai-nudge-card'),
      // Fill the available width rather than shrink-wrapping the button Row
      // (which would force its children to infinite width when the parent
      // constraints aren't tight).
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: tk.aiNudgeGradient),
        border: Border.all(color: const Color(0xFFF0CDB8)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline-length label: it must wrap on a phone rather than run off
          // the card. Safe here — the Column inside this fixed-width Container
          // bounds it.
          const AiBadge(
            label: 'Bring the oracle to life',
            size: 15,
            wrapLabel: true,
          ),
          const SizedBox(height: 6),
          Text(
            'On-device AI interprets your rolls, voices NPCs, and recaps your '
            'story — all private, all offline.',
            style: tk.narrative.copyWith(fontSize: 13.5, color: tk.inkBody),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton(
                key: const Key('ai-nudge-enable'),
                // Size to content: the app's FilledButton theme defaults to a
                // full-width minimum (Size.fromHeight), which two side-by-side
                // buttons in a Row can't satisfy.
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                ),
                onPressed: () => showSettingsSheet(context),
                child: const Text('Enable AI'),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('ai-nudge-later'),
                onPressed: () =>
                    ref.read(aiNudgeSeenProvider.notifier).markSeen(),
                child: const Text('Later'),
              ),
            ],
          ),
        ],
      ),
    );

    final sheen = _sheen;
    if (sheen == null) return card;
    // A slow diagonal highlight sweeping left→right across the card.
    return AnimatedBuilder(
      animation: sheen,
      builder: (context, child) {
        final t = sheen.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(-1.0 + 2.0 * t - 0.4, -1),
            end: Alignment(-1.0 + 2.0 * t + 0.4, 1),
            colors: const [
              Color(0x00FFFFFF),
              Color(0x33FFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(rect),
          child: child,
        );
      },
      child: card,
    );
  }
}
