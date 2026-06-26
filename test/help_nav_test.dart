import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/help_data.dart';
import 'package:juice_oracle/features/help_screen.dart';
import 'package:juice_oracle/shared/help_nav.dart';
import 'package:juice_oracle/state/interpreter.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_interpreter.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Minimal HelpData with one section/page so HelpScreen can build.
  final fakeHelpData = HelpData({
    'sections': [
      {
        'id': 'guide',
        'title': 'Guide',
        'pages': [
          {
            'id': 'start',
            'title': 'Getting started',
            'blocks': [
              {'p': 'Test content.'},
            ],
          },
        ],
      },
    ],
  });

  List<Override> overrides(ProviderContainer c) => [
        interpreterServiceProvider.overrideWithValue(FakeInterpreterService()),
        helpDataProvider.overrideWith((_) => Future.value(fakeHelpData)),
      ];

  testWidgets('openHelp without topic — pushes HelpScreen, topic stays null',
      (t) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    late WidgetRef capturedRef;
    await t.pumpWidget(ProviderScope(
      overrides: overrides(container),
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, _) {
          capturedRef = ref;
          return TextButton(
            key: const Key('open'),
            onPressed: () => openHelp(ctx, ref),
            child: const Text('Open'),
          );
        }),
      ),
    ));

    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();

    expect(find.byType(HelpScreen), findsOneWidget);
    expect(capturedRef.read(helpTopicProvider), isNull);
  });

  testWidgets(
      'openHelp with topic — sets helpTopicProvider then pushes HelpScreen',
      (t) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    String? capturedTopic;
    await t.pumpWidget(ProviderScope(
      overrides: overrides(container),
      child: MaterialApp(
        home: Consumer(builder: (ctx, ref, _) {
          return TextButton(
            key: const Key('open'),
            onPressed: () {
              openHelp(ctx, ref, topic: 'start');
              // Read immediately after the call — before HelpScreen consumes it
              capturedTopic = ref.read(helpTopicProvider);
            },
            child: const Text('Open'),
          );
        }),
      ),
    ));

    await t.tap(find.byKey(const Key('open')));
    expect(capturedTopic, 'start'); // set synchronously in openHelp

    await t.pumpAndSettle();
    expect(find.byType(HelpScreen), findsOneWidget);
  });
}
