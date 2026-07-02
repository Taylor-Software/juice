import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/oracle.dart';
import 'package:juice_oracle/engine/oracle_data.dart';
import 'package:juice_oracle/features/fate_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';

/// Layout regression guard for the theme-induced "BoxConstraints forces an
/// infinite width" crash.
///
/// The app theme makes every FilledButton full-width (min-width == infinity),
/// so the `cards-draw-spread` button — a non-flex child of a Row beside an
/// Expanded dropdown — throws at layout time unless it pins a finite
/// minimumSize. This pumps FateScreen under the REAL theme via [appHarness];
/// a plain `MaterialApp()` (default theme) can NOT reproduce the crash, which
/// is why `fate_cards_test` tapped the same button yet the bug shipped.
/// See lib/shared/theme.dart and lib/features/fate_screen.dart.
void main() {
  testWidgets('FateScreen cards section lays out under the app theme',
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

    await tester.pumpApp(FateScreen(oracle: Oracle(data)));
    await tester.pumpAndSettle();

    // The cards section (incl. the Draw-spread Row) built without a layout
    // assertion firing.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('cards-draw-spread')), findsOneWidget);

    // Drawing a spread builds the Log-spread affordance too — still no crash.
    await tester.tap(find.byKey(const Key('cards-draw-spread')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
