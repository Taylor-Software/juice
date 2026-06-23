import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/mention_text.dart';
import 'package:juice_oracle/shared/theme.dart';

Future<void> pumpMentionText(
  WidgetTester tester,
  String body, {
  void Function(String)? onCharacterTap,
  void Function(String)? onThreadTap,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: Center(
        child: MentionText(
          body,
          onCharacterTap: onCharacterTap,
          onThreadTap: onThreadTap,
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('plain text renders as-is with no tappable spans',
      (tester) async {
    await pumpMentionText(tester, 'hello world');
    expect(find.text('hello world'), findsOneWidget);
    // No RichText recognizer spans; tapping anywhere is a no-op.
  });

  testWidgets('char mention renders the display name', (tester) async {
    await pumpMentionText(tester, 'met @[Mara](char:c1) at dawn');
    // The Text.rich widget shows "met Mara at dawn" in fragments.
    // Find the RichText widget and verify the full displayed text.
    final richText = tester.widget<RichText>(find.byType(RichText).first);
    final full = richText.text.toPlainText();
    expect(full, contains('Mara'));
    expect(full, isNot(contains('@[')));
  });

  testWidgets('tapping a char mention calls onCharacterTap with the id',
      (tester) async {
    String? tappedId;
    await pumpMentionText(
      tester,
      '@[Mara](char:c1)',
      onCharacterTap: (id) => tappedId = id,
    );
    await tester.tap(find.byType(RichText));
    await tester.pump();
    expect(tappedId, 'c1');
  });

  testWidgets('tapping a thread mention calls onThreadTap with the id',
      (tester) async {
    String? tappedId;
    await pumpMentionText(
      tester,
      '@[The Vow](thread:t9)',
      onThreadTap: (id) => tappedId = id,
    );
    await tester.tap(find.byType(RichText));
    await tester.pump();
    expect(tappedId, 't9');
  });

  testWidgets('MentionText on plain text renders identically to Text',
      (tester) async {
    await pumpMentionText(tester, 'just a note');
    final richText = tester.widget<RichText>(find.byType(RichText).first);
    expect(richText.text.toPlainText(), 'just a note');
  });

  // -- Lonelog notation highlighting (P3) -------------------------------------

  Set<Color?> colors(WidgetTester t) {
    final rt = t.widget<RichText>(find.byType(RichText).first);
    final out = <Color?>{};
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        out.add(s.style?.color);
        s.children?.forEach(walk);
      }
    }

    walk(rt.text);
    return out;
  }

  bool hasRecognizer(WidgetTester t) {
    final rt = t.widget<RichText>(find.byType(RichText).first);
    var found = false;
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        if (s.recognizer != null) found = true;
        s.children?.forEach(walk);
      }
    }

    walk(rt.text);
    return found;
  }

  testWidgets('lonelog highlighting adds distinct colours vs plain rendering',
      (tester) async {
    const body = '@ Pick the lock [N:Bob]';
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: MentionText(body, lonelog: true)),
    ));
    final highlighted = colors(tester); // @ symbol, text, [N:Bob] tag distinct
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: MentionText(body, lonelog: false)),
    ));
    final plain = colors(tester);
    expect(highlighted.length, greaterThan(plain.length));
    expect(highlighted.length, greaterThan(2));
  });

  testWidgets('a mention stays tappable under lonelog highlighting',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MentionText('@ Talk to @[Bob](char:c1) now',
            lonelog: true, onCharacterTap: (_) {}),
      ),
    ));
    expect(hasRecognizer(tester), isTrue);
  });

  // -- Inline tappable dice ---------------------------------------------------

  // Collects TextSpans carrying a tap recognizer, as (text, span) pairs.
  List<(String, TextSpan)> recognizerSpans(WidgetTester t) {
    final rt = t.widget<RichText>(find.byType(RichText).first);
    final out = <(String, TextSpan)>[];
    void walk(InlineSpan s) {
      if (s is TextSpan) {
        if (s.recognizer != null && s.text != null) out.add((s.text!, s));
        s.children?.forEach(walk);
      }
    }

    walk(rt.text);
    return out;
  }

  testWidgets('a dice token becomes a tappable span that fires onDiceTap',
      (tester) async {
    String? rolled;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MentionText('hit it for 2d6+3 now', onDiceTap: (n) => rolled = n),
      ),
    ));
    final dice = recognizerSpans(tester).where((p) => p.$1 == '2d6+3').toList();
    expect(dice, hasLength(1));
    (dice.single.$2.recognizer as TapGestureRecognizer).onTap!();
    expect(rolled, '2d6+3');
  });

  testWidgets('no dice spans under lonelog highlighting', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MentionText('roll 2d6 now', lonelog: true, onDiceTap: (_) {}),
      ),
    ));
    expect(recognizerSpans(tester).any((p) => p.$1 == '2d6'), isFalse);
  });

  testWidgets('a body with a mention AND dice yields both links',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: MentionText('@[Mara](char:c1) rolls 2d6',
            onCharacterTap: (_) {}, onDiceTap: (_) {}),
      ),
    ));
    final spans = recognizerSpans(tester);
    expect(spans.any((p) => p.$1 == 'Mara'), isTrue); // mention link
    expect(spans.any((p) => p.$1 == '2d6'), isTrue); // dice link
  });

  testWidgets('no onDiceTap → dice text stays plain', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: MentionText('roll 2d6 now')),
    ));
    expect(recognizerSpans(tester).any((p) => p.$1 == '2d6'), isFalse);
  });
}
