import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../engine/lonelog_highlight.dart';
import '../engine/mention_parser.dart';

/// Renders journal prose with `@`-mentions as tappable links. When [lonelog]
/// is true, non-mention text is additionally syntax-highlighted as Lonelog
/// notation (symbols/tags/blocks/etc.) via [highlight]. Mentions are
/// pre-extracted by [parseMentions], so juice's `@[..](..)` markup never
/// collides with Lonelog's bare `@` action symbol.
class MentionText extends StatefulWidget {
  const MentionText(
    this.body, {
    super.key,
    this.style,
    this.onCharacterTap,
    this.onThreadTap,
    this.lonelog = false,
  });
  final String body;
  final TextStyle? style;
  final void Function(String id)? onCharacterTap;
  final void Function(String id)? onThreadTap;
  final bool lonelog;

  @override
  State<MentionText> createState() => _MentionTextState();
}

Color _lonelogColor(ColorScheme s, LonelogSpanKind k) => switch (k) {
      LonelogSpanKind.symbol => s.primary,
      LonelogSpanKind.actor => s.tertiary,
      LonelogSpanKind.tag => s.secondary,
      LonelogSpanKind.block => s.error,
      LonelogSpanKind.meta => s.outline,
      LonelogSpanKind.text => s.onSurface,
    };

class _MentionTextState extends State<MentionText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  /// Spans for a plain (non-mention) text run — optionally Lonelog-highlighted
  /// line by line, preserving the newlines between lines.
  List<InlineSpan> _textSpans(
      String text, TextStyle? base, ColorScheme scheme) {
    if (!widget.lonelog) return [TextSpan(text: text, style: base)];
    final out = <InlineSpan>[];
    final lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      for (final span in highlight(lines[i])) {
        out.add(TextSpan(
          text: span.text,
          style: (base ?? const TextStyle())
              .copyWith(color: _lonelogColor(scheme, span.kind)),
        ));
      }
      if (i < lines.length - 1) out.add(TextSpan(text: '\n', style: base));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
    final theme = Theme.of(context);
    final base = widget.style ?? theme.textTheme.bodyMedium;
    final linkStyle = base?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[];
    for (final seg in parseMentions(widget.body)) {
      if (seg.kind == MentionKind.text) {
        spans.addAll(_textSpans(seg.text, base, theme.colorScheme));
      } else {
        final rec = TapGestureRecognizer()
          ..onTap = () {
            if (seg.kind == MentionKind.character) {
              widget.onCharacterTap?.call(seg.id!);
            } else {
              widget.onThreadTap?.call(seg.id!);
            }
          };
        _recognizers.add(rec);
        spans.add(TextSpan(text: seg.text, style: linkStyle, recognizer: rec));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }
}
