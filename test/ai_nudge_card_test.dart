import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/ai_nudge_card.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps just the [AiNudgeCard] (no JournalScreen) so the test stays fast and
/// focused. Real providers back it — the card reads/writes [aiNudgeSeenProvider]
/// directly. [disableAnimations] exercises the static (reduced-motion) path.
Future<void> _pumpCard(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  SharedPreferences.setMockInitialValues(const {});
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // Match the real journal: the card sits at the top of a vertical list area
  // with a bounded width.
  const child = Scaffold(
    body: Align(
      alignment: Alignment.topCenter,
      child: SizedBox(width: 700, child: AiNudgeCard()),
    ),
  );
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.light(),
      // Override disableAnimations while PRESERVING the inherited size/padding
      // (a bare MediaQuery would zero the size and break layout).
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
        ),
        child: widget!,
      ),
      home: child,
    ),
  ));
  await tester
      .pump(); // let didChangeDependencies run; avoid settle on a repeat
}

void main() {
  testWidgets('renders with its key and both buttons', (tester) async {
    await _pumpCard(tester);
    expect(find.byType(AiNudgeCard), findsOneWidget);
    expect(find.byKey(const Key('ai-nudge-card')), findsOneWidget);
    expect(find.byKey(const Key('ai-nudge-enable')), findsOneWidget);
    expect(find.byKey(const Key('ai-nudge-later')), findsOneWidget);
  });

  testWidgets('Later flips aiNudgeSeen to true', (tester) async {
    await _pumpCard(tester);

    final container =
        ProviderScope.containerOf(tester.element(find.byType(AiNudgeCard)));
    expect(await container.read(aiNudgeSeenProvider.future), isFalse);

    await tester.tap(find.byKey(const Key('ai-nudge-later')));
    await tester.pump();

    expect(await container.read(aiNudgeSeenProvider.future), isTrue);
    expect(container.read(aiNudgeSeenProvider).valueOrNull, isTrue);
  });

  testWidgets('reduced-motion renders a static card without crashing',
      (tester) async {
    await _pumpCard(tester, disableAnimations: true);
    // Static path: card still renders, no ticker scheduled.
    expect(find.byKey(const Key('ai-nudge-card')), findsOneWidget);
    expect(find.byKey(const Key('ai-nudge-enable')), findsOneWidget);
    // pumpAndSettle would hang on a repeating controller — it must complete
    // here because reduced-motion creates no controller.
    await tester.pumpAndSettle();
    expect(find.byType(AiNudgeCard), findsOneWidget);
  });
}
