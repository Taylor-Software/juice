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
}
