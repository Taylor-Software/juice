import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// The single consistent AI marker: the ✦ ([Icons.auto_awesome]) glyph in the
/// terracotta accent, with an optional [label]. Use this everywhere a prominent
/// AI-assisted action is offered so the marker reads the same across the app.
class AiBadge extends StatelessWidget {
  const AiBadge({super.key, this.label, this.size = 14});

  /// Optional text shown after the glyph (e.g. 'Interpret').
  final String? label;

  /// Glyph size; the label scales off this for a balanced pairing.
  final double size;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    final glyph = Icon(Icons.auto_awesome, size: size, color: tk.terracotta);
    if (label == null) return glyph;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        const SizedBox(width: 6),
        Text(
          label!,
          style: tk.uiLabel.copyWith(
            color: tk.terracotta,
            fontSize: size,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
