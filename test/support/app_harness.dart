// test/support/app_harness.dart
//
// Canonical harness for widget/layout tests: pump under the REAL app theme.
//
// WHY THIS EXISTS — theme-induced layout crashes.
// `AppTheme` (lib/shared/theme.dart) installs a full-width `filledButtonTheme`
// (`minimumSize: Size.fromHeight(48)`, i.e. min-width == infinity). A
// `FilledButton` in an unbounded-width slot (a non-flex `Row` child, a
// `ListTile` leading/trailing, a horizontal scroll child) then throws
// "BoxConstraints forces an infinite width" at layout time.
//
// A plain `MaterialApp(home: ...)` uses Flutter's DEFAULT theme, which has no
// such `filledButtonTheme`, so those crashes are invisible in the test — a
// button can be tapped in a test and still ship broken in the app (this is
// exactly how the `cards-draw-spread` crash shipped past `fate_cards_test`).
//
// POLICY: widget/layout tests pump through [appHarness] / [PumpApp.pumpApp] so
// the theme is applied by default and theme-induced layout assertions surface
// in `tester.takeException()`. Assert `expect(tester.takeException(), isNull)`
// in a layout regression test to guard the fix.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/theme.dart';

/// Wrap [child] in a `ProviderScope` + `MaterialApp` that use the real
/// [AppTheme] (light by default). Set [wrapInScaffold] false when [child] is
/// itself a screen that provides its own `Scaffold`.
Widget appHarness(
  Widget child, {
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  bool wrapInScaffold = true,
}) {
  final theme = brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light();
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: theme,
      home: wrapInScaffold ? Scaffold(body: child) : child,
    ),
  );
}

extension PumpApp on WidgetTester {
  /// Pump [child] under the real [AppTheme]. See [appHarness].
  Future<void> pumpApp(
    Widget child, {
    List<Override> overrides = const [],
    Brightness brightness = Brightness.light,
    bool wrapInScaffold = true,
  }) =>
      pumpWidget(appHarness(
        child,
        overrides: overrides,
        brightness: brightness,
        wrapInScaffold: wrapInScaffold,
      ));
}
