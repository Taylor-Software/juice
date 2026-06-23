import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';

import 'fake_interpreter.dart';

void main() {
  testWidgets('tapping an inline dice token logs a rerollable dice entry',
      (tester) async {
    const journalJson =
        '[{"id":"1","timestamp":"2026-06-11T10:00:00.000","title":"Note",'
        '"body":"2d6+3","kind":"result"}]';
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.journal.v2.default': journalJson,
    });
    final data = OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>);
    final fake = FakeInterpreterService();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        interpreterServiceProvider.overrideWithValue(fake),
        oracleProvider.overrideWith((ref) async => Oracle(data)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(JournalScreen)));

    // Find the inline dice span and fire its tap recognizer.
    TapGestureRecognizer? diceTap;
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      void walk(InlineSpan s) {
        if (s is TextSpan) {
          if (s.text == '2d6+3' && s.recognizer is TapGestureRecognizer) {
            diceTap = s.recognizer as TapGestureRecognizer;
          }
          s.children?.forEach(walk);
        }
      }

      walk(rt.text);
    }
    expect(diceTap, isNotNull, reason: 'dice token should be tappable');
    diceTap!.onTap!();
    await tester.pumpAndSettle();

    final entries = container.read(journalProvider).valueOrNull ?? const [];
    expect(entries, hasLength(2)); // original + the rolled entry
    final rolled = entries.first; // newest-first
    expect(rolled.sourceTool, 'dice');
    expect(rolled.payload?['expression'], '2d6+3'); // rerollable
  });
}
