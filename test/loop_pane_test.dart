import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:juice_oracle/features/loop_pane.dart';
import 'package:juice_oracle/state/providers.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: LoopPane())),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders the five steps', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('loop-new-scene')), findsOneWidget);
    expect(find.byKey(const Key('loop-ask')), findsOneWidget);
    expect(find.byKey(const Key('loop-inspire')), findsOneWidget);
    // Capture field is further down the ListView; scroll to it.
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-capture-field')), findsOneWidget);
  });

  testWidgets('Ask rolls, shows a result, and logs one journal entry',
      (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('loop-ask')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('loop-ask-result')), findsOneWidget);

    final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('loop-ask'))));
    final journal = container.read(journalProvider).valueOrNull ?? const [];
    expect(journal.where((e) => e.sourceTool == 'solo-loop'), hasLength(1));
  });
}
