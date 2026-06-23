import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../engine/dice_scan.dart';
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
    this.onDiceTap,
    this.lonelog = false,
  });
  final String body;
  final TextStyle? style;
  final void Function(String id)? onCharacterTap;
  final void Function(String id)? onThreadTap;

  /// Called with the dice notation when a player taps an inline dice token
  /// (e.g. `2d6+3`) in non-lonelog prose. Null disables dice detection.
  final void Function(String notation)? onDiceTap;
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
    if (!widget.lonelog) {
      if (widget.onDiceTap == null) return [TextSpan(text: text, style: base)];
      return _diceSpans(text, base, scheme);
    }
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

  /// Splits a plain text run into plain spans + tappable dice-notation spans
  /// (link-styled, like a mention). Recognizers go in [_recognizers], which
  /// build() clears each frame and dispose() tears down.
  List<InlineSpan> _diceSpans(
      String text, TextStyle? base, ColorScheme scheme) {
    final dice = scanDice(text);
    if (dice.isEmpty) return [TextSpan(text: text, style: base)];
    final linkStyle = (base ?? const TextStyle())
        .copyWith(color: scheme.primary, fontWeight: FontWeight.w600);
    final out = <InlineSpan>[];
    var cursor = 0;
    for (final d in dice) {
      if (d.start > cursor) {
        out.add(TextSpan(text: text.substring(cursor, d.start), style: base));
      }
      final rec = TapGestureRecognizer()
        ..onTap = () => widget.onDiceTap!(d.notation);
      _recognizers.add(rec);
      out.add(TextSpan(
          text: text.substring(d.start, d.end),
          style: linkStyle,
          recognizer: rec));
      cursor = d.end;
    }
    if (cursor < text.length) {
      out.add(TextSpan(text: text.substring(cursor), style: base));
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
