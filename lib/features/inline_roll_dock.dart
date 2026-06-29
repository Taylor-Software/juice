import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/suggestions.dart';
import '../shared/design_tokens.dart';
import '../state/providers.dart';
import '../state/suggestions_provider.dart';
import 'generate_sheet.dart';

/// Always-visible horizontal strip of quick-roll chips, pinned directly above
/// the journal composer. Surfaces the inline oracle rolls (`roll-oracle` /
/// `scene-event`) that used to hide inside the collapsed assistant rail, plus
/// an always-present Inspire chip (the same generator sheet as `composer-inspire`).
///
/// The roll behavior is the shared [rollInlineSuggestion] — this widget never
/// duplicates the roll → addResult pipeline. [onRolled] fires after a roll's
/// journal write completes so the host can scroll the new entry into view.
class InlineRollDock extends ConsumerWidget {
  const InlineRollDock({super.key, this.onRolled});

  /// Called after an inline roll has appended its journal entry.
  final VoidCallback? onRolled;

  Future<void> _roll(WidgetRef ref, Suggestion s) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return; // oracle data still loading: skip safely
    await rollInlineSuggestion(ref, oracle, s);
    onRolled?.call();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = context.juice;
    final suggestions = ref.watch(suggestionsProvider);
    // The dock surfaces only the inline-action suggestions; navigate chips stay
    // in the assistant rail. scene-event appears only when its suggestion is
    // present (already context/system-gated by suggestionsProvider).
    Suggestion? byId(String id) {
      for (final s in suggestions) {
        if (s.id == id) return s;
      }
      return null;
    }

    final rollOracle = byId('roll-oracle');
    final sceneEvent = byId('scene-event');
    final askYesNo = byId('ask-yes-no');

    Widget chip({
      required Key key,
      required String label,
      required Color bg,
      required Color fg,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ActionChip(
          key: key,
          backgroundColor: bg,
          side: BorderSide(color: tk.hairline),
          label: Text(label,
              style: tk.uiLabel.copyWith(
                  color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
          onPressed: onTap,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Roll oracle — always present; the primary filled action.
            chip(
              key: const Key('dock-roll-oracle'),
              label: '⚀ Roll oracle',
              bg: tk.terracotta,
              fg: Colors.white,
              onTap: () => _roll(ref, rollOracle ?? _fallbackRollOracle),
            ),
            // Scene test — only when the scene-event suggestion is present.
            if (sceneEvent != null)
              chip(
                key: const Key('dock-scene-event'),
                label: 'Scene test',
                bg: tk.selected,
                fg: tk.terracottaDeep,
                onTap: () => _roll(ref, sceneEvent),
              ),
            // Ask yes/no — direct one-tap d10 solo oracle (even odds).
            if (askYesNo != null)
              chip(
                key: const Key('dock-ask-yes-no'),
                label: '? Yes/No',
                bg: tk.selected,
                fg: tk.terracottaDeep,
                onTap: () => _roll(ref, askYesNo),
              ),
            // Inspire — always present; reuses the composer-inspire generator
            // sheet (no roll, no journal write here).
            chip(
              key: const Key('dock-inspire'),
              label: '✦ Inspire',
              bg: tk.selected,
              fg: tk.terracottaDeep,
              onTap: () => showGenerateSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  // suggestionsFor always emits roll-oracle, so this fallback is a defensive
  // belt-and-braces for the (loading) empty-suggestions frame.
  static const Suggestion _fallbackRollOracle =
      Suggestion('roll-oracle', 'Roll the oracle', SuggestionAction.inline);
}
