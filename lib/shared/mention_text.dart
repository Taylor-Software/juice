import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../engine/mention_parser.dart';

/// Renders journal prose with `@`-mentions as tappable links.
class MentionText extends StatefulWidget {
  const MentionText(
    this.body, {
    super.key,
    this.style,
    this.onCharacterTap,
    this.onThreadTap,
  });
  final String body;
  final TextStyle? style;
  final void Function(String id)? onCharacterTap;
  final void Function(String id)? onThreadTap;

  @override
  State<MentionText> createState() => _MentionTextState();
}

class _MentionTextState extends State<MentionText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
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
        spans.add(TextSpan(text: seg.text, style: base));
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
