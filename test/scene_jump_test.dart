import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:juice_oracle/features/journal_screen.dart';
import 'package:juice_oracle/features/scene_jump_sheet.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'fake_interpreter.dart';

/// Newest-first journal: an old scene buried under 40 filler entries.
String _journalJson() {
  final entries = <Map<String, dynamic>>[
    for (var i = 40; i >= 1; i--)
      {
        'id': 'f$i',
        'timestamp':
            '2026-07-11T10:${(i % 60).toString().padLeft(2, '0')}:00.000',
        'title': 'Filler $i',
        'body': 'Body of filler entry $i, long enough to take some height.',
        'kind': 'result',
      },
    {
      'id': 'scene-old',
      'timestamp': '2026-07-11T09:00:00.000',
      'title': 'The Buried Scene',
      'body': '',
      'kind': 'scene',
    },
  ];
  return jsonEncode(entries);
}

void main() {
  testWidgets('scene jump scroll-hunts the reverse list to an old scene',
      (t) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
      'juice.ai_nudge_seen.v1': true,
      'juice.recap_suppressed.v1': true,
      'juice.journal.v2.default': _journalJson(),
    });
    final c = ProviderContainer(overrides: [
      interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
    ]);
    addTearDown(c.dispose);
    await t.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: JournalScreen()),
      ),
    ));
    await t.pumpAndSettle();

    // The old scene is far above the fold in the lazy reverse list. Scene
    // dividers render the title uppercased inside a Text.rich.
    final buried = find.textContaining('THE BURIED SCENE', findRichText: true);
    expect(buried, findsNothing);

    c.read(journalRevealProvider.notifier).state = 'scene-old';
    await t.pumpAndSettle();

    expect(buried, findsOneWidget);
    // The one-shot request was consumed.
    expect(c.read(journalRevealProvider), isNull);
  });
}
