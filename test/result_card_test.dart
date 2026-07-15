import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/result_card.dart';

const _result = GenResult(
  title: 'Mythic Fate Chart',
  rolls: [Roll(label: 'Answer', value: 'Yes')],
);

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  testWidgets('no action row when actions is null', (tester) async {
    await _pump(tester, const ResultCard(result: _result));
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('no inspire button when onInspire is null (AI off / not ready)',
      (tester) async {
    await _pump(tester, ResultCard(result: _result, onLog: () {}));
    expect(find.byKey(const Key('result-inspire')), findsNothing);
  });

  testWidgets('inspire button renders beside Add-to-journal and fires',
      (tester) async {
    var inspires = 0;
    var logs = 0;
    await _pump(
      tester,
      ResultCard(
        result: _result,
        onLog: () => logs++,
        onInspire: () => inspires++,
      ),
    );
    final btn = find.byKey(const Key('result-inspire'));
    expect(btn, findsOneWidget);
    await tester.tap(btn);
    await tester.pump();
    expect(inspires, 1);
    // Inspire is an alternative way to commit the result, not a replacement
    // for the plain log — both actions stay available.
    expect(logs, 0);
    expect(find.byIcon(Icons.bookmark_add_outlined), findsOneWidget);
  });

  testWidgets('renders action chips and taps fire their callback',
      (tester) async {
    var taps = 0;
    await _pump(
      tester,
      ResultCard(
        result: _result,
        actions: [
          ResultAction(
            label: 'Random Event',
            icon: Icons.bolt_outlined,
            onPressed: () => taps++,
          ),
        ],
      ),
    );
    final chip = find.byKey(const Key('result-action-Random Event'));
    expect(chip, findsOneWidget);
    expect(find.text('Random Event'), findsOneWidget);
    await tester.tap(chip);
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('a null onPressed disables the chip', (tester) async {
    await _pump(
      tester,
      const ResultCard(
        result: _result,
        actions: [
          ResultAction(label: 'Disabled', icon: Icons.bolt_outlined),
        ],
      ),
    );
    final chip = tester.widget<ActionChip>(find.byType(ActionChip));
    expect(chip.onPressed, isNull);
  });
}
