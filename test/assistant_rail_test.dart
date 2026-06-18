import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/assistant_rail.dart';
import 'package:juice_oracle/shared/destination.dart';
import 'package:juice_oracle/shared/shell_route.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> pumpRail(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'juice.sessions.v1':
        '{"active":"default","sessions":[{"id":"default","name":"C1"}]}',
    'juice.journal.v2.default': '[]',
    'juice.threads.v1.default': '[]',
  });
  final c = ProviderContainer();
  await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: AssistantRail()))));
  await tester.pumpAndSettle();
  return c;
}

void main() {
  testWidgets('renders the always-on oracle chip', (tester) async {
    await pumpRail(tester);
    expect(find.text('Roll the oracle'), findsOneWidget);
  });

  testWidgets('navigate chip routes via shellRouteProvider', (tester) async {
    final c = await pumpRail(tester); // empty campaign → start-scene present
    await tester.tap(find.text('Start a scene'));
    await tester.pumpAndSettle();
    final route = c.read(shellRouteProvider);
    expect(route.destination, Destination.track);
    expect(route.subtab, 'scenes');
  });
}
