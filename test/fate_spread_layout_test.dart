import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/fate_screen.dart';
import 'package:juice_oracle/shared/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regression guard for the "BoxConstraints forces an infinite width" crash in
/// the Cards -> Spreads row (fate_screen.dart). The draw-spread FilledButton is
/// a NON-flex child of a Row whose other child (the spread picker) is Expanded;
/// the flex sizing pass measures the button with unbounded width, and the
/// app-wide filledButtonTheme minimumSize (Size.fromHeight => infinite min
/// width) then throws.
///
/// This test MUST pump under the real [AppTheme]. The sibling fate_cards_test
/// uses MaterialApp's default theme (no filledButtonTheme), so it never
/// reproduced the crash even though it taps the same button — which is exactly
/// why the bug shipped.
void main() {
  testWidgets('Spreads row lays out under AppTheme without infinite width',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'juice.sessions.v1':
          '{"active":"default","sessions":[{"id":"default","name":"C1",'
              '"systems":["cards"]}]}',
    });
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final data = OracleData(
        jsonDecode(File('assets/oracle_data.json').readAsStringSync())
            as Map<String, dynamic>);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: FateScreen(oracle: Oracle(data))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('cards-draw-spread')), findsOneWidget);
  });
}
