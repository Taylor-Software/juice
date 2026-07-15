import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// The single consistent AI marker: the ✦ ([Icons.auto_awesome]) glyph in the
/// terracotta accent, with an optional [label]. Use this everywhere a prominent
/// AI-assisted action is offered so the marker reads the same across the app.
class AiBadge extends StatelessWidget {
  const AiBadge({
    super.key,
    this.label,
    this.size = 14,
    this.wrapLabel = false,
  });

  /// Optional text shown after the glyph (e.g. 'Interpret').
  final String? label;

  /// Glyph size; the label scales off this for a balanced pairing.
  final double size;

  /// Let a long label wrap instead of forcing the row past its parent.
  ///
  /// Off by default because the badge's usual home is a button label inside a
  /// `Wrap` (see journal_entry_tile), where the incoming width is UNBOUNDED —
  /// a flex child there throws "RenderFlex children have non-zero flex but
  /// incoming width constraints are unbounded". Only set this where the parent
  /// bounds the width, e.g. a card's Column. Short labels never need it; it
  /// exists for headline-length ones like the AI nudge card's.
  final bool wrapLabel;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    final glyph = Icon(Icons.auto_awesome, size: size, color: tk.terracotta);
    if (label == null) return glyph;
    Widget text = Text(
      label!,
      style: tk.uiLabel.copyWith(
        color: tk.terracotta,
        fontSize: size,
        fontWeight: FontWeight.w600,
      ),
    );
    if (wrapLabel) text = Flexible(child: text);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        const SizedBox(width: 6),
        text,
      ],
    );
  }
}
